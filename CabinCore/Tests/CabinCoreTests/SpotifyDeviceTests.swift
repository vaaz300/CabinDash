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

    @Test func theLineNamesThisIPhoneWhenNothingElseIsPicked() {
        // With no pick, Play goes to this iPhone, so that is what the line says.
        #expect(SpotifyDevices.lineText(playingOn: nil, chosenName: nil) == "This iPhone")
        #expect(SpotifyDevices.lineText(playingOn: "", chosenName: "") == "This iPhone")
    }

    @Test func theNoticeSaysPlayingWhenSomethingMoves() {
        #expect(SpotifyDevices.movedNotice(deviceName: "iPhone", somethingIsPlaying: true) == "Playing on iPhone")
    }

    @Test func theNoticeAdmitsNothingIsPlayingYet() {
        #expect(SpotifyDevices.movedNotice(deviceName: "iPhone", somethingIsPlaying: false)
                == "Ready on iPhone. Pick something to play.")
    }
}

/// Where a tap on Play sends the music. With no other pick it is this iPhone, with no extra step: Spotify's own list says
/// whether the phone is ready, and when it is not the Spotify app has to be started on it first.
@Suite struct SpotifyPlayRouteTests {
    private func device(_ id: String, type: String, restricted: Bool = false, active: Bool = false) -> SpotifyDevice {
        SpotifyDevice(id: id, name: "Device \(id)", type: type, isActive: active, isRestricted: restricted)
    }

    @Test func aListThatCouldNotBeReadLeavesItToSpotify() {
        #expect(SpotifyDevices.route(devices: nil, chosenID: nil, phoneIsAwake: true) == .spotifyDecides)
        #expect(SpotifyDevices.route(devices: nil, chosenID: "tv", phoneIsAwake: true) == .spotifyDecides)
    }

    @Test func aListedPhoneIsUsedWithoutAnyPick() {
        let phone = device("p", type: "Smartphone")
        #expect(SpotifyDevices.route(devices: [phone], chosenID: nil, phoneIsAwake: true) == .device(phone))
    }

    @Test func aTVThatIsActiveDoesNotWinOverThePhone() {
        // The earlier complaint: the TV box was picked for the person. Being active is not a pick.
        let tv = device("tv", type: "TV", active: true)
        let phone = device("p", type: "Smartphone")
        #expect(SpotifyDevices.route(devices: [tv, phone], chosenID: nil, phoneIsAwake: true) == .device(phone))
    }

    @Test func aDeviceThePersonPickedBeatsThePhone() {
        let tv = device("tv", type: "TV")
        let phone = device("p", type: "Smartphone")
        #expect(SpotifyDevices.route(devices: [phone, tv], chosenID: "tv", phoneIsAwake: true) == .device(tv))
    }

    @Test func aPickThatIsNoLongerListedFallsBackToThePhone() {
        let phone = device("p", type: "Smartphone")
        #expect(SpotifyDevices.route(devices: [phone], chosenID: "tv", phoneIsAwake: true) == .device(phone))
    }

    @Test func aPickThatTakesNoCommandsFallsBackToThePhone() {
        let tv = device("tv", type: "TV", restricted: true)
        let phone = device("p", type: "Smartphone")
        #expect(SpotifyDevices.route(devices: [tv, phone], chosenID: "tv", phoneIsAwake: true) == .device(phone))
    }

    @Test func noPhoneListedMeansStartSpotifyOnThisIPhone() {
        // Spotify lists a phone only while its app is running. Never fall back to the TV the person did not pick.
        let tv = device("tv", type: "TV", active: true)
        #expect(SpotifyDevices.route(devices: [tv], chosenID: nil, phoneIsAwake: true) == .wakeThisPhone)
        #expect(SpotifyDevices.route(devices: [], chosenID: nil, phoneIsAwake: true) == .wakeThisPhone)
    }

    @Test func aRestrictedPhoneIsNotUsable() {
        #expect(SpotifyDevices.route(devices: [device("p", type: "Smartphone", restricted: true)], chosenID: nil, phoneIsAwake: true) == .wakeThisPhone)
    }

    @Test func ofSeveralPhonesTheFirstInSpotifysOrderIsUsed() {
        let first = device("p1", type: "Smartphone")
        let second = device("p2", type: "Smartphone")
        #expect(SpotifyDevices.route(devices: [second, first], chosenID: nil, phoneIsAwake: true) == .device(second))
    }

    @Test func aPickedPhoneThatIsGoneStartsSpotifyAgain() {
        #expect(SpotifyDevices.route(devices: [], chosenID: "p", phoneIsAwake: true) == .wakeThisPhone)
    }

    // Spotify's own SDK documents that the Spotify app on an iPhone stops listening for commands soon after it leaves the
    // screen and stops playing. A phone that is listed but idle and not connected cannot be trusted to answer the Web API.

    @Test func aListedPhoneThatIsIdleAndNotConnectedNeedsSpotifyStarted() {
        let phone = device("p", type: "Smartphone", active: false)
        #expect(SpotifyDevices.route(devices: [phone], chosenID: nil, phoneIsAwake: false) == .wakeThisPhone)
    }

    @Test func aPhoneSpotifyCallsActiveIsNoProofThatItIsAwake() {
        // Spotify keeps calling a sleeping phone active. Trusting that cost four silent seconds before the app was started.
        let phone = device("p", type: "Smartphone", active: true)
        #expect(SpotifyDevices.route(devices: [phone], chosenID: nil, phoneIsAwake: false) == .wakeThisPhone)
        #expect(SpotifyDevices.route(devices: [phone], chosenID: "p", phoneIsAwake: false) == .wakeThisPhone)
    }

    @Test func anIdlePhoneIsUsedWhenTheConnectionToSpotifyIsUp() {
        let phone = device("p", type: "Smartphone", active: false)
        #expect(SpotifyDevices.route(devices: [phone], chosenID: nil, phoneIsAwake: true) == .device(phone))
    }

    @Test func aPickedPhoneThatIsIdleAndNotConnectedNeedsSpotifyStarted() {
        let phone = device("p", type: "Smartphone", active: false)
        #expect(SpotifyDevices.route(devices: [phone], chosenID: "p", phoneIsAwake: false) == .wakeThisPhone)
    }

    @Test func aPickedTVIsNotAffectedByWhetherThePhoneIsAwake() {
        let tv = device("tv", type: "TV", active: false)
        let phone = device("p", type: "Smartphone")
        #expect(SpotifyDevices.route(devices: [phone, tv], chosenID: "tv", phoneIsAwake: false) == .device(tv))
    }

    @Test func anAwakePhoneIsUsedWhateverSpotifyCallsActive() {
        let idle = device("p", type: "Smartphone", active: false)
        #expect(SpotifyDevices.route(devices: [idle], chosenID: nil, phoneIsAwake: true) == .device(idle))
    }
}

/// Starting Spotify on the phone through its SDK plays one address, and that is left alone afterwards: a second play command
/// sent to the Spotify app once it is in the background restarts the song and the app stopped answering. What the SDK cannot
/// express is added through the connection to the Spotify app instead, which neither restarts nor replaces anything: the
/// next songs of a list go into the queue, and a shuffle is switched on.
@Suite struct SpotifyWakePlanTests {
    @Test func aPlaylistStartsFromItself() {
        let plan = SpotifyDevices.wakePlan(for: .context(uri: "spotify:playlist:p", startAtURI: nil), shuffled: false)
        #expect(plan == SpotifyDevices.WakePlan(uri: "spotify:playlist:p"))
    }

    @Test func anAlbumStartsFromItself() {
        let plan = SpotifyDevices.wakePlan(for: .context(uri: "spotify:album:a", startAtURI: nil), shuffled: false)
        #expect(plan == SpotifyDevices.WakePlan(uri: "spotify:album:a"))
    }

    @Test func aShuffledPlaylistStartsAndIsThenShuffledThroughTheConnection() {
        let plan = SpotifyDevices.wakePlan(for: .context(uri: "spotify:playlist:p", startAtURI: nil), shuffled: true)
        #expect(plan == SpotifyDevices.WakePlan(uri: "spotify:playlist:p", shuffleAfter: true))
    }

    @Test func aSongInAPlaylistStartsWithThatSongAlone() {
        let plan = SpotifyDevices.wakePlan(for: .context(uri: "spotify:playlist:p", startAtURI: "spotify:track:t"), shuffled: false)
        #expect(plan == SpotifyDevices.WakePlan(uri: "spotify:track:t"))
    }

    @Test func aSingleSongNeedsNothingMore() {
        let plan = SpotifyDevices.wakePlan(for: .uris(["spotify:track:t"]), shuffled: false)
        #expect(plan == SpotifyDevices.WakePlan(uri: "spotify:track:t"))
    }

    @Test func aListOfSongsStartsWithTheFirstAndQueuesTheNext() {
        let plan = SpotifyDevices.wakePlan(for: .uris(["spotify:track:a", "spotify:track:b", "spotify:track:c"]), shuffled: false)
        #expect(plan == SpotifyDevices.WakePlan(uri: "spotify:track:a", followUps: ["spotify:track:b", "spotify:track:c"]))
    }

    @Test func aLongListQueuesOnlyTheNextTwenty() {
        let uris = (0..<40).map { "spotify:track:\($0)" }
        let plan = SpotifyDevices.wakePlan(for: .uris(uris), shuffled: false)
        #expect(plan.uri == "spotify:track:0")
        #expect(plan.followUps.count == 20)
        #expect(plan.followUps.first == "spotify:track:1")
        #expect(plan.followUps.last == "spotify:track:20")
    }

    @Test func aShuffledListIsShuffledAfterwards() {
        let plan = SpotifyDevices.wakePlan(for: .uris(["spotify:track:a", "spotify:track:b"]), shuffled: true)
        #expect(plan == SpotifyDevices.WakePlan(uri: "spotify:track:a", followUps: ["spotify:track:b"], shuffleAfter: true))
    }

    @Test func nothingToPlayStartsSpotifyAndSendsNothing() {
        #expect(SpotifyDevices.wakePlan(for: .uris([]), shuffled: false) == SpotifyDevices.WakePlan(uri: ""))
    }
}

/// Spotify can accept a play command for a phone whose app is asleep and then never start it. Whether the music really
/// started is read from the player: it must be on the device the command was sent to.
@Suite struct SpotifyStartedTests {
    private let phone = SpotifyDevice(id: "p", name: "Evan's iPhone", type: "Smartphone")

    @Test func playingOnThePhoneMeansItStarted() {
        #expect(SpotifyDevices.startedOn(phone, playingOn: "Evan's iPhone"))
    }

    @Test func nothingPlayingMeansItDidNot() {
        #expect(!SpotifyDevices.startedOn(phone, playingOn: nil))
    }

    @Test func musicStillOnAnotherDeviceMeansItDidNot() {
        #expect(!SpotifyDevices.startedOn(phone, playingOn: "Xiaomi TV Box"))
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
