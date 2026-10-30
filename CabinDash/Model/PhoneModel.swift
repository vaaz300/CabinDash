import CabinCore
import CallKit
import Contacts
import Foundation
import Observation
import OSLog
import UIKit

private let systemLog = Logger(subsystem: "app.cabindash", category: "phone")

/// The Phone screen's four sections.
enum PhoneTab: String, CaseIterable, Hashable {
    case favourites
    case recents
    case contacts
    case keypad

    var title: String {
        switch self {
        case .favourites: return "Favourites"
        case .recents: return "Recents"
        case .contacts: return "Contacts"
        case .keypad: return "Keypad"
        }
    }

    var symbol: String {
        switch self {
        case .favourites: return "star.fill"
        case .recents: return "clock.fill"
        case .contacts: return "person.crop.circle.fill"
        case .keypad: return "circle.grid.3x3.fill"
        }
    }
}

/// How much of the iPhone's Contacts Cabin Dash may read. iOS 18 added "limited": only the people the owner picked.
enum ContactsAccess: Equatable {
    case notDetermined
    case denied
    case restricted
    case limited
    case full

    var canRead: Bool { self == .full || self == .limited }
}

/// Contacts, favourites, the keypad, calls placed from Cabin Dash and what the phone's call is doing.
///
/// iOS hands every call to its own Phone app: Cabin Dash opens a `tel:` link, iOS asks "Call …?", and its call screen
/// takes over. iOS tells any app that a call started, connected or ended (`CXCallObserver`), but never who it is with,
/// so the call strip shows only the state and how long it has lasted.
@MainActor @Observable
final class PhoneModel {
    var tab: PhoneTab = .favourites
    var keypad = Keypad()
    var query = ""
    /// The contact whose card is open.
    var openContact: ContactEntry?

    private(set) var book: PhoneBook {
        didSet { save() }
    }
    private(set) var access: ContactsAccess = .notDetermined
    private(set) var contacts: [ContactEntry] = []
    private(set) var loadingContacts = false
    private(set) var callStatus: CallStatus = .none
    /// When the current call connected, for the timer on the call strip.
    private(set) var callConnectedAt: Date?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let toast: ToastCenter
    @ObservationIgnored private var watcher: CallWatcher?
    private static let bookKey = "cabin-dash.phonebook.v1"

    init(defaults: UserDefaults = .standard, toast: ToastCenter) {
        self.defaults = defaults
        self.toast = toast
        if let data = defaults.data(forKey: Self.bookKey), let saved = try? JSONDecoder().decode(PhoneBook.self, from: data) {
            book = saved
        } else {
            book = PhoneBook()
        }
        access = Self.currentAccess()
    }

    /// Starts listening for calls. Safe to call more than once.
    func start() {
        guard watcher == nil else { return }
        let watcher = CallWatcher { [weak self] snapshots in
            self?.noteCalls(snapshots)
        }
        self.watcher = watcher
        noteCalls(watcher.snapshots())
    }

    // MARK: Calls

    /// Hands `number` to iOS, which asks before dialling. Records it in Recents once iOS has accepted the link.
    func call(_ number: String, name: String?) {
        guard let url = PhoneNumber.telURL(number) else {
            toast.show("That number can't be dialled")
            return
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let label = name ?? ContactDirectory.name(for: number, in: contacts)
        Task {
            if await UIApplication.shared.open(url) {
                self.book.noteCall(name: label, number: number, at: Date())
            } else {
                // The number is not logged: it is personal.
                systemLog.info("iOS refused a tel: link")
                self.toast.show("This iPhone can't place calls")
            }
        }
    }

    func callKeypad() {
        guard keypad.canCall else { return }
        call(keypad.digits, name: nil)
    }

    private func noteCalls(_ snapshots: [CallSnapshot]) {
        let status = CallStatus.from(snapshots)
        if status == .active, callConnectedAt == nil { callConnectedAt = Date() }
        if !status.isLive { callConnectedAt = nil }
        if status != callStatus { callStatus = status }
    }

    // MARK: Favourites

    func isPinned(_ number: String) -> Bool { book.isPinned(number) }

    func togglePin(name: String, number: String, contactID: String?) {
        if book.isPinned(number) {
            book.unpin(number)
            toast.show("Removed \(name) from Favourites")
        } else if book.pin(name: name, number: number, contactID: contactID) {
            toast.show("Added \(name) to Favourites")
        } else {
            toast.show("Favourites holds \(PhoneBook.maxFavourites) people. Remove one first.")
        }
    }

    func unpin(_ favourite: FavouriteContact) {
        book.unpin(favourite.number)
    }

    // MARK: Contacts

    /// Re-reads what iOS allows, and the contacts if that changed. Call when the app comes back to the front, since the
    /// owner may have changed access in Settings.
    func refreshAccess() {
        let now = Self.currentAccess()
        let changed = now != access
        access = now
        if now.canRead, changed || contacts.isEmpty { loadContacts() }
        if !now.canRead { contacts = [] }
    }

    /// Shows iOS's own Contacts permission question.
    func requestAccess() {
        Task {
            do {
                _ = try await CNContactStore().requestAccess(for: .contacts)
            } catch {
                systemLog.info("Contacts access request failed: \(error.localizedDescription, privacy: .public)")
            }
            self.refreshAccess()
            self.loadContacts()
        }
    }

    func loadContacts() {
        guard access.canRead, !loadingContacts else { return }
        loadingContacts = true
        Task {
            let entries = await Self.readContacts()
            self.contacts = entries
            self.loadingContacts = false
        }
    }

    var sections: [ContactSection] {
        ContactDirectory.sections(contacts, query: query)
    }

    /// Reads names and numbers only, off the main thread. Notes, photos and addresses are not read.
    private nonisolated static func readContacts() async -> [ContactEntry] {
        await Task.detached(priority: .userInitiated) {
            let keys: [CNKeyDescriptor] = [
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor,
                CNContactOrganizationNameKey as CNKeyDescriptor,
                CNContactPhoneNumbersKey as CNKeyDescriptor,
            ]
            let request = CNContactFetchRequest(keysToFetch: keys)
            var entries: [ContactEntry] = []
            do {
                try CNContactStore().enumerateContacts(with: request) { contact, _ in
                    let numbers = contact.phoneNumbers.map { labelled in
                        ContactNumber(
                            label: labelled.label.map { CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: $0) } ?? "phone",
                            value: labelled.value.stringValue
                        )
                    }
                    entries.append(ContactEntry(
                        id: contact.identifier, givenName: contact.givenName, familyName: contact.familyName,
                        organization: contact.organizationName, numbers: numbers
                    ))
                }
            } catch {
                systemLog.info("Reading contacts failed: \(error.localizedDescription, privacy: .public)")
            }
            return entries
        }.value
    }

    private static func currentAccess() -> ContactsAccess {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        case .authorized: return .full
        default:
            if #available(iOS 18.0, *), status == .limited { return .limited }
            return .denied
        }
    }

    // MARK: Saving

    private func save() {
        guard let data = try? JSONEncoder().encode(book) else { return }
        defaults.set(data, forKey: Self.bookKey)
    }
}

/// Tells Cabin Dash when the iPhone's call state changes. iOS shares only whether calls are outgoing, connected, on hold
/// or ended: never the number or the name.
private final class CallWatcher: NSObject, CXCallObserverDelegate {
    private let observer = CXCallObserver()
    private let onChange: @MainActor ([CallSnapshot]) -> Void

    init(onChange: @escaping @MainActor ([CallSnapshot]) -> Void) {
        self.onChange = onChange
        super.init()
        // nil queue: the delegate is called on the main queue.
        observer.setDelegate(self, queue: nil)
    }

    func snapshots() -> [CallSnapshot] {
        observer.calls.map {
            CallSnapshot(isOutgoing: $0.isOutgoing, hasConnected: $0.hasConnected, hasEnded: $0.hasEnded, isOnHold: $0.isOnHold)
        }
    }

    func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        let current = snapshots()
        MainActor.assumeIsolated {
            onChange(current)
        }
    }
}
