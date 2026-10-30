import Foundation

/// Phone numbers as Cabin Dash dials them. iOS places the call itself: Cabin Dash only builds the `tel:` link,
/// and iOS asks before dialling.
public enum PhoneNumber {
    /// The number with only what a phone dials: digits, `*`, `#`, and a `+` at the start. Spaces, brackets, dashes, dots,
    /// letters and a `tel:` prefix are dropped. Nil when no digit is left.
    public static func dialable(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("tel:") { text.removeFirst(4) }
        var result = ""
        for character in text {
            if character.isASCII, character.isNumber || character == "*" || character == "#" {
                result.append(character)
            } else if character == "+", result.isEmpty {
                result.append(character)
            }
        }
        return result.contains(where: { $0.isASCII && $0.isNumber }) ? result : nil
    }

    /// The `tel:` link for `raw`, or nil when there is nothing to dial. `#` is escaped, as a URL needs.
    public static func telURL(_ raw: String) -> URL? {
        guard let number = dialable(raw) else { return nil }
        return URL(string: "tel:" + number.replacingOccurrences(of: "#", with: "%23"))
    }

    /// True when both are the same dialable number, whatever their formatting.
    public static func same(_ a: String, _ b: String) -> Bool {
        guard let left = dialable(a), let right = dialable(b) else { return false }
        return left == right
    }
}

/// What has been typed on the Phone screen's keypad.
public struct Keypad: Equatable, Sendable {
    public static let maxLength = 32
    public private(set) var digits = ""

    public init() {}

    /// Adds one key: 0–9, `*`, `#`, or `+` as the first key. Anything else, and anything past `maxLength`, is ignored.
    public mutating func press(_ key: String) {
        guard key.count == 1, digits.count < Self.maxLength, let character = key.first else { return }
        if character.isASCII, character.isNumber || character == "*" || character == "#" {
            digits.append(character)
        } else if character == "+", digits.isEmpty {
            digits.append(character)
        }
    }

    public mutating func backspace() {
        if !digits.isEmpty { digits.removeLast() }
    }

    public mutating func clear() {
        digits = ""
    }

    public var canCall: Bool { PhoneNumber.dialable(digits) != nil }
}

/// One phone number on a contact card, with its label as the Contacts app shows it ("mobile", "home", …).
public struct ContactNumber: Equatable, Hashable, Sendable {
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

/// A contact as the Phone screen needs it: names and numbers. Read from the iPhone's Contacts with the person's permission.
public struct ContactEntry: Identifiable, Equatable, Sendable {
    public let id: String
    public let givenName: String
    public let familyName: String
    public let organization: String
    public let numbers: [ContactNumber]

    public init(id: String, givenName: String, familyName: String, organization: String, numbers: [ContactNumber]) {
        self.id = id
        self.givenName = givenName
        self.familyName = familyName
        self.organization = organization
        self.numbers = numbers
    }

    /// The name to show: given and family name, else the organisation, else the first number.
    public var displayName: String {
        let name = [givenName, familyName]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !name.isEmpty { return name }
        let org = organization.trimmingCharacters(in: .whitespaces)
        if !org.isEmpty { return org }
        return numbers.first?.value ?? "No name"
    }

    /// Up to two letters for a contact without a photo.
    public var initials: String {
        let parts = [givenName, familyName].compactMap { $0.trimmingCharacters(in: .whitespaces).first }
        if !parts.isEmpty { return String(parts.prefix(2)).uppercased() }
        return String(displayName.prefix(1)).uppercased()
    }
}

/// One letter of the A–Z list.
public struct ContactSection: Equatable, Sendable {
    public let letter: String
    public let entries: [ContactEntry]
}

public enum ContactDirectory {
    /// The callable contacts (those with at least one number) matching `query`, in A–Z sections. Names starting with
    /// anything but a letter go under `#`, last. Matching ignores case and accents; a query with three or more digits
    /// also matches numbers.
    public static func sections(_ entries: [ContactEntry], query: String) -> [ContactSection] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let queryDigits = trimmed.filter { $0.isASCII && $0.isNumber }
        let matching = entries.filter { entry in
            guard !entry.numbers.isEmpty else { return false }
            guard !trimmed.isEmpty else { return true }
            let haystack = [entry.displayName, entry.givenName, entry.familyName, entry.organization].joined(separator: " ")
            if haystack.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil { return true }
            if queryDigits.count >= 3 {
                return entry.numbers.contains { ($0.value.filter { $0.isASCII && $0.isNumber }).contains(queryDigits) }
            }
            return false
        }
        let sorted = matching.sorted {
            $0.displayName.compare($1.displayName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedAscending
        }
        var order: [String] = []
        var groups: [String: [ContactEntry]] = [:]
        for entry in sorted {
            let letter = sectionLetter(entry.displayName)
            if groups[letter] == nil { order.append(letter) }
            groups[letter, default: []].append(entry)
        }
        order.sort { left, right in
            if left == "#" { return false }
            if right == "#" { return true }
            return left < right
        }
        return order.map { ContactSection(letter: $0, entries: groups[$0] ?? []) }
    }

    /// The contact name for a number, if one of `entries` has it.
    public static func name(for number: String, in entries: [ContactEntry]) -> String? {
        entries.first { entry in entry.numbers.contains { PhoneNumber.same($0.value, number) } }?.displayName
    }

    private static func sectionLetter(_ name: String) -> String {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en"))
        guard let first = folded.first, first.isASCII, first.isLetter else { return "#" }
        return String(first).uppercased()
    }
}

/// Someone pinned to the Phone screen's Favourites, with the number to call. The name and number are kept, so a
/// favourite still works with limited Contacts access.
public struct FavouriteContact: Codable, Equatable, Identifiable, Sendable {
    public let name: String
    public let number: String
    public let contactID: String?

    public var id: String { PhoneNumber.dialable(number) ?? number }

    public init(name: String, number: String, contactID: String?) {
        self.name = name
        self.number = number
        self.contactID = contactID
    }
}

/// A call placed from Cabin Dash. iOS does not let an app read the phone's own call history, so Recents lists only these.
public struct PlacedCall: Codable, Equatable, Identifiable, Sendable {
    public let name: String?
    public let number: String
    public let date: Date

    public var id: String { PhoneNumber.dialable(number) ?? number }

    public init(name: String?, number: String, date: Date) {
        self.name = name
        self.number = number
        self.date = date
    }
}

/// Favourites and the calls placed from Cabin Dash, saved together on the phone.
public struct PhoneBook: Codable, Equatable, Sendable {
    public static let maxFavourites = 12
    public static let maxCalls = 20

    public private(set) var favourites: [FavouriteContact]
    public private(set) var calls: [PlacedCall]

    public init(favourites: [FavouriteContact] = [], calls: [PlacedCall] = []) {
        self.favourites = favourites
        self.calls = calls
    }

    private enum CodingKeys: String, CodingKey { case favourites, calls }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            favourites: (try? c.decodeIfPresent([FavouriteContact].self, forKey: .favourites)) ?? [],
            calls: (try? c.decodeIfPresent([PlacedCall].self, forKey: .calls)) ?? []
        )
    }

    public func isPinned(_ number: String) -> Bool {
        favourites.contains { PhoneNumber.same($0.number, number) }
    }

    /// Pins a number. True when it is (or already was) a favourite; false when the number cannot be dialled or the
    /// list is full.
    @discardableResult
    public mutating func pin(name: String, number: String, contactID: String?) -> Bool {
        guard let clean = PhoneNumber.dialable(number) else { return false }
        if isPinned(clean) { return true }
        guard favourites.count < Self.maxFavourites else { return false }
        favourites.append(FavouriteContact(name: name, number: clean, contactID: contactID))
        return true
    }

    public mutating func unpin(_ number: String) {
        favourites.removeAll { PhoneNumber.same($0.number, number) }
    }

    /// Records a call at the top of Recents. Calling a number again moves it up rather than listing it twice.
    public mutating func noteCall(name: String?, number: String, at date: Date) {
        guard let clean = PhoneNumber.dialable(number) else { return }
        let keptName = name ?? calls.first { PhoneNumber.same($0.number, clean) }?.name
        calls.removeAll { PhoneNumber.same($0.number, clean) }
        calls.insert(PlacedCall(name: keptName, number: clean, date: date), at: 0)
        if calls.count > Self.maxCalls { calls.removeLast(calls.count - Self.maxCalls) }
    }
}

/// One call as iOS's call observer reports it. It never includes the number or the name.
public struct CallSnapshot: Equatable, Sendable {
    public let isOutgoing: Bool
    public let hasConnected: Bool
    public let hasEnded: Bool
    public let isOnHold: Bool

    public init(isOutgoing: Bool, hasConnected: Bool, hasEnded: Bool, isOnHold: Bool) {
        self.isOutgoing = isOutgoing
        self.hasConnected = hasConnected
        self.hasEnded = hasEnded
        self.isOnHold = isOnHold
    }
}

/// The phone's call activity as one state, for the call strip and the Phone screen.
public enum CallStatus: Equatable, Sendable {
    case none
    case dialing
    case ringing
    case active
    case onHold

    /// A live call beats one on hold, which beats one being placed, which beats one ringing in.
    public static func from(_ calls: [CallSnapshot]) -> CallStatus {
        let live = calls.filter { !$0.hasEnded }
        if live.contains(where: { $0.hasConnected && !$0.isOnHold }) { return .active }
        if live.contains(where: { $0.hasConnected && $0.isOnHold }) { return .onHold }
        if live.contains(where: { $0.isOutgoing && !$0.hasConnected }) { return .dialing }
        if live.contains(where: { !$0.isOutgoing && !$0.hasConnected }) { return .ringing }
        return .none
    }

    public var isLive: Bool { self != .none }

    public var title: String {
        switch self {
        case .none: return ""
        case .dialing: return "Calling\u{2026}"
        case .ringing: return "Incoming call"
        case .active: return "On a call"
        case .onHold: return "On hold"
        }
    }
}

public enum CallFormat {
    /// "0:05", "3:12", "1:02:03".
    public static func duration(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }
}
