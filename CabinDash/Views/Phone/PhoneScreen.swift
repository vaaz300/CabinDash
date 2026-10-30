import CabinCore
import ContactsUI
import SwiftUI
import UIKit

/// Phone inside Cabin Dash: Favourites, Recents (calls placed from here), Contacts and a Keypad, laid out like Music.
/// Tapping a person or Call hands the number to iOS, which asks before dialling and shows its own call screen.
struct PhoneScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var phone = model.phone
        VStack(spacing: 10) {
            PhoneTabs()
            PhoneStatusLine()
            Group {
                switch phone.tab {
                case .favourites: FavouritesPane()
                case .recents: RecentsPane()
                case .contacts: ContactsPane()
                case .keypad: KeypadPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Drawn on the same darkened, frosted background as Music (RootView).
        .environment(\.colorScheme, .dark)
        .padding(.leading, CarLayout.railReserve)
        .padding(.trailing, CarLayout.edge)
        .padding(.top, CarLayout.edge)
        .padding(.bottom, StripClearance.bottom(for: model.bottomStrips))
        .sheet(item: $phone.openContact) { contact in
            ContactCard(contact: contact)
                .preferredColorScheme(model.prefs.theme.colorScheme)
        }
        .onAppear { phone.refreshAccess() }
    }
}

/// The four sections, spread across the row like Music's.
private struct PhoneTabs: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let phone = model.phone
        HStack(spacing: 8) {
            ForEach(PhoneTab.allCases, id: \.self) { tab in
                let selected = phone.tab == tab
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    phone.tab = tab
                } label: {
                    Label(tab.title, systemImage: tab.symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(selected ? Color.black : Color.primary)
                        .padding(.horizontal, 18)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(selected ? Theme.accent : Color.primary.opacity(0.10), in: Capsule())
                }
                .buttonStyle(PressScaleStyle(scale: 0.96))
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
    }
}

/// The call in progress, if any, in the row under the tabs (the call strip is not shown on this screen).
/// Otherwise a reminder of how calls work.
private struct PhoneStatusLine: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let phone = model.phone
        HStack(spacing: 10) {
            if phone.callStatus.isLive {
                Label(phone.callStatus.title, systemImage: "phone.fill")
                    .foregroundStyle(Theme.good)
                if let since = phone.callConnectedAt {
                    TimelineView(.periodic(from: since, by: 1)) { context in
                        Text(CallFormat.duration(context.date.timeIntervalSince(since)))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Label("iOS asks before each call, then shows its own call screen", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 15, weight: .medium))
        .lineLimit(1)
        .padding(.horizontal, 6)
        .frame(minHeight: 30)
    }
}

// MARK: - Favourites

private struct FavouritesPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let phone = model.phone
        if phone.book.favourites.isEmpty {
            PaneNotice(
                symbol: "star",
                title: "No favourites yet",
                detail: "Open someone in Contacts or Recents and tap the star. Favourites stay one tap away while you drive."
            )
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)], spacing: 12) {
                    ForEach(phone.book.favourites) { favourite in
                        Button {
                            phone.call(favourite.number, name: favourite.name)
                        } label: {
                            VStack(spacing: 8) {
                                Initials(text: initials(of: favourite.name), size: 64)
                                Text(favourite.name)
                                    .font(.system(size: 17, weight: .semibold))
                                    .lineLimit(1)
                                Text(favourite.number)
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(PressScaleStyle(scale: 0.96))
                        .accessibilityLabel("Call \(favourite.name)")
                        .contextMenu {
                            Button(role: .destructive) {
                                phone.unpin(favourite)
                            } label: {
                                Label("Remove from Favourites", systemImage: "star.slash")
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func initials(of name: String) -> String {
        let words = name.split(separator: " ").prefix(2).compactMap(\.first)
        return words.isEmpty ? "#" : String(words).uppercased()
    }
}

// MARK: - Recents

private struct RecentsPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let phone = model.phone
        if phone.book.calls.isEmpty {
            PaneNotice(
                symbol: "clock",
                title: "No calls from Cabin Dash yet",
                detail: "Calls you place from here are listed here. iOS doesn't let other apps read the Phone app's own history."
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(phone.book.calls) { call in
                        let name = call.name ?? call.number
                        HStack(spacing: 12) {
                            Button {
                                phone.call(call.number, name: call.name)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "phone.arrow.up.right.fill")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(Theme.accent)
                                        .frame(width: 30)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(name)
                                            .font(.system(size: 17, weight: .semibold))
                                            .lineLimit(1)
                                        if call.name != nil {
                                            Text(call.number)
                                                .font(.system(size: 13))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer(minLength: 8)
                                    Text(call.date, format: .relative(presentation: .named))
                                        .font(.system(size: 14))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .frame(minHeight: 52)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PressScaleStyle(scale: 0.98))
                            .accessibilityLabel("Call \(name)")

                            StarButton(pinned: phone.isPinned(call.number)) {
                                phone.togglePin(name: name, number: call.number, contactID: nil)
                            }
                        }
                        .padding(.horizontal, 12)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
        }
    }
}

// MARK: - Contacts

private struct ContactsPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let phone = model.phone
        switch phone.access {
        case .notDetermined:
            PaneNotice(
                symbol: "person.crop.circle.badge.questionmark",
                title: "Show your contacts?",
                detail: "Cabin Dash reads names and numbers only, and they stay on this iPhone.",
                retry: nil
            )
            .overlay(alignment: .bottom) {
                PillButton(title: "Allow access to Contacts", symbol: "person.crop.circle", filled: true) {
                    phone.requestAccess()
                }
                .padding(.bottom, 12)
            }
        case .denied, .restricted:
            PaneNotice(
                symbol: "person.crop.circle.badge.xmark",
                title: "Contacts are switched off for Cabin Dash",
                detail: "Turn them on in Settings > Apps > Cabin Dash > Contacts. Favourites, Recents and the Keypad still work."
            )
            .overlay(alignment: .bottom) {
                PillButton(title: "Open Settings", symbol: "gear", filled: true) {
                    model.openSystemSettings()
                }
                .padding(.bottom, 12)
            }
        case .limited, .full:
            if model.typingLocked {
                // Scrolling a long list and searching it is not something to do while driving.
                PaneNotice(
                    symbol: "car.fill",
                    title: "Contacts are hidden while driving",
                    detail: "Use Favourites or Recents, or switch on Passenger mode in Settings."
                )
            } else {
                ContactList(limited: phone.access == .limited)
            }
        }
    }
}

private struct ContactList: View {
    let limited: Bool
    @Environment(AppModel.self) private var model
    @State private var sharingMore = false

    var body: some View {
        @Bindable var phone = model.phone
        let sections = phone.sections
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search contacts", text: $phone.query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 16))
                    if !phone.query.isEmpty {
                        Button {
                            phone.query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(Color.primary.opacity(0.10), in: Capsule())

                if limited {
                    PillButton(title: "Share more", symbol: "person.badge.plus") {
                        if #available(iOS 18.0, *) {
                            sharingMore = true
                        } else {
                            model.openSystemSettings()
                        }
                    }
                }
            }

            if sections.isEmpty {
                PaneNotice(
                    symbol: phone.loadingContacts ? "hourglass" : "person.crop.circle",
                    title: phone.loadingContacts ? "Reading contacts\u{2026}" : (phone.query.isEmpty ? "No contacts with a phone number" : "No matches"),
                    detail: limited && phone.query.isEmpty ? "Cabin Dash sees only the contacts you chose to share." : nil
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4, pinnedViews: [.sectionHeaders]) {
                        ForEach(sections, id: \.letter) { section in
                            Section {
                                ForEach(section.entries) { contact in
                                    Button {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        phone.openContact = contact
                                    } label: {
                                        HStack(spacing: 12) {
                                            Initials(text: contact.initials, size: 38)
                                            Text(contact.displayName)
                                                .font(.system(size: 17, weight: .medium))
                                                .lineLimit(1)
                                            Spacer(minLength: 8)
                                            if contact.numbers.contains(where: { phone.isPinned($0.value) }) {
                                                Image(systemName: "star.fill")
                                                    .foregroundStyle(Theme.accent)
                                                    .accessibilityLabel("Favourite")
                                            }
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundStyle(.tertiary)
                                        }
                                        .padding(.horizontal, 12)
                                        .frame(minHeight: 50)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(PressScaleStyle(scale: 0.98))
                                }
                            } header: {
                                Text(section.letter)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.ultraThinMaterial)
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.immediately)
            }
        }
        .modifier(ShareMoreContacts(isPresented: $sharingMore) {
            phone.loadContacts()
        })
    }
}

/// iOS 18's picker for sharing more contacts with an app that has limited access. Earlier iOS has no such picker.
private struct ShareMoreContacts: ViewModifier {
    @Binding var isPresented: Bool
    let onChange: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.contactAccessPicker(isPresented: $isPresented) { _ in
                onChange()
            }
        } else {
            content
        }
    }
}

/// One person: their numbers, each with Call and a star to pin it to Favourites.
private struct ContactCard: View {
    let contact: ContactEntry
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let phone = model.phone
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                Initials(text: contact.initials, size: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.displayName)
                        .font(.system(size: 24, weight: .bold))
                        .lineLimit(2)
                    if !contact.organization.isEmpty, contact.displayName != contact.organization {
                        Text(contact.organization)
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Button("Done") { dismiss() }
                    .font(.system(size: 17, weight: .semibold))
                    .frame(minHeight: 44)
            }

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(contact.numbers, id: \.self) { number in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(number.label)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Text(number.value)
                                    .font(.system(size: 19, weight: .semibold))
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            StarButton(pinned: phone.isPinned(number.value)) {
                                phone.togglePin(name: contact.displayName, number: number.value, contactID: contact.id)
                            }
                            Button {
                                dismiss()
                                phone.call(number.value, name: contact.displayName)
                            } label: {
                                Label("Call", systemImage: "phone.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(onAccent)
                                    .padding(.horizontal, 18)
                                    .frame(minHeight: 48)
                                    .background(Theme.accent, in: Capsule())
                            }
                            .buttonStyle(PressScaleStyle(scale: 0.95))
                            .accessibilityLabel("Call \(contact.displayName), \(number.label)")
                        }
                        .padding(12)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        }
        .padding(20)
        .presentationDetents([.large])
    }
}

// MARK: - Keypad

private struct KeypadPane: View {
    @Environment(AppModel.self) private var model

    private static let keys: [[String]] = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["*", "0", "#"]]

    var body: some View {
        let phone = model.phone
        if model.typingLocked {
            PaneNotice(
                symbol: "car.fill",
                title: "The keypad is off while driving",
                detail: "Call a favourite or a recent number instead, or switch on Passenger mode in Settings."
            )
        } else {
            HStack(spacing: 28) {
                VStack(spacing: 16) {
                    Spacer(minLength: 0)
                    Text(phone.keypad.digits.isEmpty ? "Enter a number" : phone.keypad.digits)
                        .font(.system(size: phone.keypad.digits.isEmpty ? 22 : 34, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(phone.keypad.digits.isEmpty ? HierarchicalShapeStyle.tertiary : HierarchicalShapeStyle.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity)
                    if let name = ContactDirectory.name(for: phone.keypad.digits, in: phone.contacts) {
                        Text(name)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 20) {
                        Button {
                            phone.callKeypad()
                        } label: {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(onAccent)
                                .frame(width: 72, height: 72)
                                .background(Theme.accent, in: Circle())
                        }
                        .buttonStyle(PressScaleStyle(scale: 0.92))
                        .disabled(!phone.keypad.canCall)
                        .opacity(phone.keypad.canCall ? 1 : 0.4)
                        .accessibilityLabel("Call")

                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            phone.keypad.backspace()
                        } label: {
                            Image(systemName: "delete.left.fill")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 60, height: 60)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PressScaleStyle(scale: 0.9))
                        .disabled(phone.keypad.digits.isEmpty)
                        .opacity(phone.keypad.digits.isEmpty ? 0.3 : 1)
                        .accessibilityLabel("Delete")
                        .simultaneousGesture(LongPressGesture(minimumDuration: 0.6).onEnded { _ in phone.keypad.clear() })
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)

                GeometryReader { proxy in
                    let rows = CGFloat(Self.keys.count)
                    let spacing: CGFloat = 10
                    let side = min(76, (proxy.size.height - spacing * (rows - 1)) / rows)
                    VStack(spacing: spacing) {
                        ForEach(Self.keys, id: \.self) { row in
                            HStack(spacing: spacing * 1.6) {
                                ForEach(row, id: \.self) { key in
                                    KeyButton(key: key, side: side) {
                                        phone.keypad.press(key)
                                    } longPress: {
                                        // Hold 0 for +, as on the Phone app.
                                        if key == "0", phone.keypad.digits.isEmpty { phone.keypad.press("+") }
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct KeyButton: View {
    let key: String
    let side: CGFloat
    let action: () -> Void
    let longPress: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            VStack(spacing: 0) {
                Text(key)
                    .font(.system(size: side * 0.42, weight: .medium))
                if key == "0" {
                    Text("+")
                        .font(.system(size: side * 0.16, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: side, height: side)
            .background(Color.primary.opacity(0.12), in: Circle())
            .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.9))
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in longPress() })
        .accessibilityLabel(key)
    }
}

// MARK: - Shared

/// A round badge with a person's initials, in place of a photo (Cabin Dash does not read contact photos).
private struct Initials: View {
    let text: String
    let size: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color.primary.opacity(0.22), in: Circle())
            .accessibilityHidden(true)
    }
}

private struct StarButton: View {
    let pinned: Bool
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: pinned ? "star.fill" : "star")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(pinned ? Theme.accent : Color.primary.opacity(0.7))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.9))
        .accessibilityLabel(pinned ? "Remove from Favourites" : "Add to Favourites")
    }
}
