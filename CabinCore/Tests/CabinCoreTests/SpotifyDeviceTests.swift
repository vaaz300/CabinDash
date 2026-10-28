import Foundation
import Testing
@testable import CabinCore

/// What the device picker needs to know about phones. Spotify lists a phone only while its Spotify app is running.
@Suite struct SpotifyDevicePhoneTests {
    private func device(_ id: String, type: String, restricted: Bool = false, active: Bool = false) -> SpotifyDevice {
        SpotifyDevice(id: id, name: "Device \(id)", type: type, isActive: active, isRestricted: restricted)
    }

    @Test func noDevicesMeansNoPhone() {
        #expect(!SpotifyDevices.hasPhone(in: []))
    }

    @Test func aTVBoxAloneIsNotAPhone() {
        // The case that matters: Spotify lists only a phone's app while it is running, so a list with just the TV box
        // means the phone's Spotify app has not been opened lately.
        #expect(!SpotifyDevices.hasPhone(in: [device("tv", type: "TV", active: true)]))
        #expect(!SpotifyDevices.hasPhone(in: [device("tv", type: "CastVideo"), device("s", type: "Speaker")]))
    }

    @Test func aSmartphoneIsAPhone() {
        #expect(SpotifyDevices.hasPhone(in: [device("tv", type: "TV", active: true), device("p", type: "Smartphone")]))
    }

    @Test func aRestrictedPhoneDoesNotCount() {
        #expect(!SpotifyDevices.hasPhone(in: [device("p", type: "Smartphone", restricted: true)]))
    }

    @Test func phonesComeFirstAndEachGroupKeepsSpotifysOrder() {
        let list = [
            device("tv", type: "TV", active: true), device("p1", type: "Smartphone"),
            device("sp", type: "Speaker"), device("p2", type: "Smartphone"),
        ]
        #expect(SpotifyDevices.phonesFirst(list).map(\.id) == ["p1", "p2", "tv", "sp"])
    }

    @Test func phonesFirstOfAnEmptyListIsEmpty() {
        #expect(SpotifyDevices.phonesFirst([]).isEmpty)
    }
}

/// Where playback goes after the person picks a device. Spotify only treats a device as active once it has something to play,
/// so a phone that was picked while nothing was playing is still "no active device" on the next tap. Cabin Dash then
/// plays on the device the person picked, and nowhere else.
@Suite struct SpotifyDeviceChoiceTests {
    @Test func aPlayWithNoActiveDeviceRetriesOnTheChosenOne() {
        #expect(SpotifyDevices.retryDeviceID(after: .noActiveDevice, chosenID: "phone") == "phone")
    }

    @Test func withNothingChosenThereIsNowhereToRetry() {
        #expect(SpotifyDevices.retryDeviceID(after: .noActiveDevice, chosenID: nil) == nil)
    }

    @Test func otherFailuresAreNeverRetriedElsewhere() {
        let others: [SpotifyFailure] = [
            .notSignedIn, .premiumRequired, .notAllowed, .rateLimited(retryAfter: 1), .http(500), .offline,
        ]
        for failure in others {
            #expect(SpotifyDevices.retryDeviceID(after: failure, chosenID: "phone") == nil)
        }
    }

    @Test func theLineNamesTheDeviceThatIsPlaying() {
        #expect(SpotifyDevices.lineText(playingOn: "Xiaomi TV Box", chosenName: "iPhone") == "Playing on Xiaomi TV Box")
    }

    @Test func theLineFallsBackToTheChosenDevice() {
        #expect(SpotifyDevices.lineText(playingOn: nil, chosenName: "iPhone") == "Ready on iPhone")
        #expect(SpotifyDevices.lineText(playingOn: "", chosenName: "iPhone") == "Ready on iPhone")
    }

    @Test func theLineOffersTheChoiceWhenThereIsNone() {
        #expect(SpotifyDevices.lineText(playingOn: nil, chosenName: nil) == "Choose device")
        #expect(SpotifyDevices.lineText(playingOn: "", chosenName: "") == "Choose device")
    }

    @Test func theNoticeSaysPlayingWhenSomethingMoves() {
        #expect(SpotifyDevices.movedNotice(deviceName: "iPhone", somethingIsPlaying: true) == "Playing on iPhone")
    }

    @Test func theNoticeAdmitsNothingIsPlayingYet() {
        #expect(SpotifyDevices.movedNotice(deviceName: "iPhone", somethingIsPlaying: false)
                == "Ready on iPhone. Pick something to play.")
    }
}

@Suite struct SpotifyLinkTests {
    private func addresses(_ uri: String?) -> [String] {
        SpotifyLink.openURLs(forURI: uri).map(\.absoluteString)
    }

    private let home = ["spotify://", "https://open.spotify.com"]

    @Test func theLabelIsSpotifysRequiredWording() {
        #expect(SpotifyLink.label == "Open Spotify")
    }

    @Test func trackLinkOpensTheTrack() {
        #expect(addresses("spotify:track:abc123") == ["spotify:track:abc123", "https://open.spotify.com/track/abc123"])
    }

    @Test func playlistLinkAndAlbumLink() {
        #expect(addresses("spotify:playlist:p1") == ["spotify:playlist:p1", "https://open.spotify.com/playlist/p1"])
        #expect(addresses("spotify:album:alb1") == ["spotify:album:alb1", "https://open.spotify.com/album/alb1"])
    }

    @Test func episodeShowAndArtistLinks() {
        #expect(addresses("spotify:episode:e1") == ["spotify:episode:e1", "https://open.spotify.com/episode/e1"])
        #expect(addresses("spotify:show:s1") == ["spotify:show:s1", "https://open.spotify.com/show/s1"])
        #expect(addresses("spotify:artist:ar1") == ["spotify:artist:ar1", "https://open.spotify.com/artist/ar1"])
    }

    @Test func unknownOrMissingURIOpensSpotifyItself() {
        #expect(addresses(nil) == home)
        #expect(addresses("") == home)
        #expect(addresses("not a uri") == home)
        #expect(addresses("spotify:user:someone") == home)
        #expect(addresses("spotify:track:") == home)
        #expect(addresses("spotify:track:a:b") == home)
        #expect(addresses("https://example.com/track/abc") == home)
    }

    @Test func aLocalFileURIOpensSpotifyItself() {
        #expect(addresses("spotify:local:::Demo:180") == home)
    }

    @Test func anIdWithOddCharactersOpensSpotifyItself() {
        #expect(addresses("spotify:track:ab/../cd") == home)
        #expect(addresses("spotify:track:ab cd") == home)
    }
}
