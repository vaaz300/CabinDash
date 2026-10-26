import Foundation
import Testing
@testable import CabinCore

@Suite struct PreferencesTests {
    @Test func otherAppsIsOffByDefault() {
        #expect(Preferences().showOtherApps == false)
    }

    @Test func savesWithoutTheKeyDecodeAsOff() throws {
        let decoded = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
        #expect(decoded.showOtherApps == false)
        #expect(decoded.units == Preferences().units)
    }

    @Test func theSwitchSurvivesASaveAndLoad() throws {
        let original = Preferences(showOtherApps: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Preferences.self, from: data)
        #expect(decoded == original)
        #expect(decoded.showOtherApps)
    }

    @Test func resettingAppsKeepsTheSwitch() {
        var preferences = Preferences(showOtherApps: true)
        preferences.resetApps()
        #expect(preferences.showOtherApps)
    }

    /// Pins existing behaviour on purpose (it passes before any change): the old dock stored screen ids such as
    /// "maps" in `recent`, and saves from that version must keep loading without those ids showing up as apps.
    @Test func oldScreenIdsInRecentsAreIgnoredByTheShelf() {
        let apps = ["waze"].compactMap { Catalog.entry(id: $0) }
        #expect(apps.count == 1)
        #expect(Shelf.recents(apps, ids: ["maps", "now-playing", "waze"]).map(\.id) == ["waze"])
    }
}
