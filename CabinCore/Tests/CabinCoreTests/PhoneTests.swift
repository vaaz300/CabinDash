import Foundation
import Testing
@testable import CabinCore

@Suite struct PhoneNumberTests {
    @Test func keepsDigitsAndALeadingPlus() {
        #expect(PhoneNumber.dialable("+353 (87) 123-4567") == "+353871234567")
        #expect(PhoneNumber.dialable("087 123 4567") == "0871234567")
        #expect(PhoneNumber.dialable("087.123.4567") == "0871234567")
    }

    @Test func dropsATelPrefix() {
        #expect(PhoneNumber.dialable("tel:0871234567") == "0871234567")
        #expect(PhoneNumber.dialable("TEL:+44 20 7946 0000") == "+442079460000")
    }

    @Test func aPlusCountsOnlyAtTheStart() {
        #expect(PhoneNumber.dialable("00353+87") == "0035387")
        #expect(PhoneNumber.dialable(" +1 555") == "+1555")
    }

    @Test func keepsStarAndHashForServiceCodes() {
        #expect(PhoneNumber.dialable("*21#") == "*21#")
    }

    @Test func nothingToDialGivesNil() {
        #expect(PhoneNumber.dialable("") == nil)
        #expect(PhoneNumber.dialable("+") == nil)
        #expect(PhoneNumber.dialable("abc") == nil)
        #expect(PhoneNumber.dialable("*#") == nil)
    }

    @Test func telURLUsesTheCleanedNumber() {
        #expect(PhoneNumber.telURL("+353 87 123")?.absoluteString == "tel:+35387123")
        #expect(PhoneNumber.telURL("087-123")?.absoluteString == "tel:087123")
    }

    @Test func telURLEscapesTheHash() {
        #expect(PhoneNumber.telURL("*21#")?.absoluteString == "tel:*21%23")
    }

    @Test func telURLIsNilWhenThereIsNothingToDial() {
        #expect(PhoneNumber.telURL("hello") == nil)
    }

    @Test func sameNumberIgnoresFormatting() {
        #expect(PhoneNumber.same("087 123 4567", "087-123-4567"))
        #expect(!PhoneNumber.same("087 123 4567", "087 123 4568"))
        #expect(!PhoneNumber.same("", ""))
    }
}

@Suite struct KeypadTests {
    @Test func pressingKeysBuildsTheNumber() {
        var pad = Keypad()
        for key in ["0", "8", "7", "*", "#"] { pad.press(key) }
        #expect(pad.digits == "087*#")
    }

    @Test func plusOnlyAsTheFirstKey() {
        var pad = Keypad()
        pad.press("+")
        pad.press("3")
        pad.press("+")
        #expect(pad.digits == "+3")
    }

    @Test func ignoresAnythingThatIsNotAKey() {
        var pad = Keypad()
        pad.press("a")
        pad.press("12")
        pad.press("")
        #expect(pad.digits == "")
    }

    @Test func stopsAtThirtyTwoKeys() {
        var pad = Keypad()
        for _ in 0..<40 { pad.press("5") }
        #expect(pad.digits.count == Keypad.maxLength)
        #expect(Keypad.maxLength == 32)
    }

    @Test func backspaceAndClear() {
        var pad = Keypad()
        pad.backspace()
        #expect(pad.digits == "")
        pad.press("1")
        pad.press("2")
        pad.backspace()
        #expect(pad.digits == "1")
        pad.clear()
        #expect(pad.digits == "")
    }

    @Test func canCallOnlyWithSomethingToDial() {
        var pad = Keypad()
        #expect(!pad.canCall)
        pad.press("+")
        #expect(!pad.canCall)
        pad.press("1")
        #expect(pad.canCall)
    }
}

@Suite struct ContactDirectoryTests {
    private func person(_ id: String, _ given: String, _ family: String = "", org: String = "", numbers: [String] = ["0871234567"]) -> ContactEntry {
        ContactEntry(
            id: id, givenName: given, familyName: family, organization: org,
            numbers: numbers.map { ContactNumber(label: "mobile", value: $0) }
        )
    }

    @Test func displayNameFallsBackToOrganisationThenNumber() {
        #expect(person("1", "Aoife", "Byrne").displayName == "Aoife Byrne")
        #expect(person("2", "", "", org: "Garage").displayName == "Garage")
        #expect(person("3", "", "", numbers: ["087 1"]).displayName == "087 1")
        #expect(person("4", "", "", numbers: []).displayName == "No name")
    }

    @Test func sectionsAreAlphabeticalWithHashLast() {
        let entries = [person("1", "zoe"), person("2", "Ádám"), person("3", "Brian"), person("4", "", "", org: "112 Emergency"), person("5", "aoife")]
        let sections = ContactDirectory.sections(entries, query: "")
        #expect(sections.map(\.letter) == ["A", "B", "Z", "#"])
        #expect(sections[0].entries.map(\.id) == ["2", "5"])
    }

    @Test func peopleWithoutANumberAreLeftOut() {
        let sections = ContactDirectory.sections([person("1", "Ann", numbers: []), person("2", "Ben")], query: "")
        #expect(sections.flatMap(\.entries).map(\.id) == ["2"])
    }

    @Test func searchMatchesNamesIgnoringCaseAndAccents() {
        let entries = [person("1", "Seán", "Ó Briain"), person("2", "Ciara", "Kelly")]
        #expect(ContactDirectory.sections(entries, query: "sean").flatMap(\.entries).map(\.id) == ["1"])
        #expect(ContactDirectory.sections(entries, query: "KEL").flatMap(\.entries).map(\.id) == ["2"])
    }

    @Test func searchMatchesNumbersFromThreeDigits() {
        let entries = [person("1", "Ann", numbers: ["087 555 0001"]), person("2", "Ben", numbers: ["086 999 0002"])]
        #expect(ContactDirectory.sections(entries, query: "555").flatMap(\.entries).map(\.id) == ["1"])
        #expect(ContactDirectory.sections(entries, query: "08").flatMap(\.entries).isEmpty)
    }

    @Test func nameForANumberFindsTheContact() {
        let entries = [person("1", "Ann", numbers: ["087 555 0001"])]
        #expect(ContactDirectory.name(for: "0875550001", in: entries) == "Ann")
        #expect(ContactDirectory.name(for: "0870000000", in: entries) == nil)
    }
}

@Suite struct PhoneBookTests {
    @Test func pinningAddsAFavouriteOnce() {
        var book = PhoneBook()
        #expect(book.pin(name: "Ann", number: "087 555 0001", contactID: "c1"))
        #expect(book.pin(name: "Ann", number: "087-555-0001", contactID: "c1"))
        #expect(book.favourites.count == 1)
        #expect(book.isPinned("0875550001"))
    }

    @Test func favouritesStopAtTwelve() {
        var book = PhoneBook()
        for index in 0..<12 { #expect(book.pin(name: "P\(index)", number: "08700000\(10 + index)", contactID: nil)) }
        #expect(!book.pin(name: "One more", number: "0861111111", contactID: nil))
        #expect(book.favourites.count == PhoneBook.maxFavourites)
    }

    @Test func pinningNothingDialableIsRefused() {
        var book = PhoneBook()
        #expect(!book.pin(name: "Nobody", number: "abc", contactID: nil))
        #expect(book.favourites.isEmpty)
    }

    @Test func unpinRemovesByNumber() {
        var book = PhoneBook()
        _ = book.pin(name: "Ann", number: "087 555 0001", contactID: nil)
        book.unpin("0875550001")
        #expect(book.favourites.isEmpty)
    }

    @Test func callsAreNewestFirstAndCapped() {
        var book = PhoneBook()
        let start = Date(timeIntervalSince1970: 1_000_000)
        for index in 0..<25 {
            book.noteCall(name: nil, number: "0870000\(100 + index)", at: start.addingTimeInterval(Double(index)))
        }
        #expect(book.calls.count == PhoneBook.maxCalls)
        #expect(PhoneBook.maxCalls == 20)
        #expect(book.calls.first?.number == "0870000124")
    }

    @Test func callingTheSameNumberAgainMovesItToTheTop() {
        var book = PhoneBook()
        let start = Date(timeIntervalSince1970: 1_000_000)
        book.noteCall(name: "Ann", number: "087 555 0001", at: start)
        book.noteCall(name: nil, number: "0861111111", at: start.addingTimeInterval(1))
        book.noteCall(name: "Ann", number: "0875550001", at: start.addingTimeInterval(2))
        #expect(book.calls.map(\.number) == ["0875550001", "0861111111"])
        #expect(book.calls.first?.date == start.addingTimeInterval(2))
    }

    @Test func decodesOldOrPartialSaves() throws {
        let book = try JSONDecoder().decode(PhoneBook.self, from: Data("{}".utf8))
        #expect(book == PhoneBook())
        let round = try JSONDecoder().decode(PhoneBook.self, from: JSONEncoder().encode({ () -> PhoneBook in
            var b = PhoneBook()
            _ = b.pin(name: "Ann", number: "0875550001", contactID: "c1")
            b.noteCall(name: "Ann", number: "0875550001", at: Date(timeIntervalSince1970: 5))
            return b
        }()))
        #expect(round.favourites.first?.name == "Ann")
        #expect(round.calls.first?.name == "Ann")
    }
}

@Suite struct CallStatusTests {
    private func call(out: Bool = true, connected: Bool = false, ended: Bool = false, held: Bool = false) -> CallSnapshot {
        CallSnapshot(isOutgoing: out, hasConnected: connected, hasEnded: ended, isOnHold: held)
    }

    @Test func noCallsIsNone() {
        #expect(CallStatus.from([]) == .none)
        #expect(CallStatus.from([call(connected: true, ended: true)]) == .none)
    }

    @Test func outgoingBeforeAnswerIsDialling() {
        #expect(CallStatus.from([call()]) == .dialing)
    }

    @Test func incomingBeforeAnswerIsRinging() {
        #expect(CallStatus.from([call(out: false)]) == .ringing)
    }

    @Test func connectedIsActiveAndBeatsTheRest() {
        #expect(CallStatus.from([call(connected: true)]) == .active)
        #expect(CallStatus.from([call(out: false), call(connected: true, held: true), call(connected: true)]) == .active)
    }

    @Test func onlyHeldCallsIsOnHold() {
        #expect(CallStatus.from([call(connected: true, held: true)]) == .onHold)
    }

    @Test func titles() {
        #expect(CallStatus.active.title == "On a call")
        #expect(CallStatus.onHold.title == "On hold")
        #expect(CallStatus.dialing.title == "Calling\u{2026}")
        #expect(CallStatus.ringing.title == "Incoming call")
        #expect(CallStatus.none.isLive == false)
        #expect(CallStatus.ringing.isLive)
    }

    @Test func durationClock() {
        #expect(CallFormat.duration(5) == "0:05")
        #expect(CallFormat.duration(192) == "3:12")
        #expect(CallFormat.duration(3723) == "1:02:03")
        #expect(CallFormat.duration(-4) == "0:00")
    }
}
