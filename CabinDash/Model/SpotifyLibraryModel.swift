import CabinCore
import Foundation
import Observation

/// Where a list is in loading, so a screen can show a spinner, the list, or the reason it failed.
enum LoadState<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(SpotifyFailure)

    var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }
}

/// The person's playlists and Liked Songs, and the playlist they have open. Each list loads the first time its pane
/// appears and is kept until they ask again, so redrawing a screen never asks Spotify again.
///
/// The loaders are plain functions that start a task this model owns. A pane that disappears half way through a load
/// therefore cannot cancel it and leave the list stuck on "loading".
@MainActor @Observable
final class SpotifyLibraryModel {
    /// Which part of the Music screen is showing. Kept here so it survives leaving the screen and coming back.
    var section: MusicSection = .nowPlaying

    private(set) var playlists: LoadState<[SpotifyPlaylist]> = .idle
    private(set) var liked: LoadState<[SpotifyTrack]> = .idle
    private(set) var likedTotal: Int?
    private(set) var openPlaylist: SpotifyPlaylist?
    private(set) var playlistTracks: LoadState<[SpotifyTrack]> = .idle
    /// The signed-in person's Spotify id, needed to tell which playlists are theirs.
    private(set) var profileID: String?
    /// True once the profile has been asked for, whether or not Spotify answered.
    private(set) var profileChecked = false

    /// What is typed in the Search section. Call `searchTextChanged()` after it changes.
    var searchText = ""
    private(set) var search: LoadState<SpotifySearchResults> = .idle
    private(set) var queue: LoadState<SpotifyQueue> = .idle
    private(set) var devices: LoadState<[SpotifyDevice]> = .idle
    /// Whether the device list is showing. The device chip and the "no device ready" banner both open it.
    var devicePickerPresented = false

    let spotify: SpotifyModel
    let toast: ToastCenter

    @ObservationIgnored private var likedNext: Int?
    @ObservationIgnored private var likedLoadingMore = false
    @ObservationIgnored private var likedGeneration = 0
    @ObservationIgnored private var playlistNext: Int?
    @ObservationIgnored private var playlistLoadingMore = false
    @ObservationIgnored private var playlistGeneration = 0
    /// Bumped by `reset()`. An answer that arrives after a reset belongs to the previous sign-in and is dropped.
    @ObservationIgnored private var epoch = 0

    /// A long library is read this many pages deep at most (50 playlists a page).
    private static let maxPlaylistPages = 6

    init(spotify: SpotifyModel, toast: ToastCenter) {
        self.spotify = spotify
        self.toast = toast
        spotify.phone.onProblem = { [weak self] text in self?.toast.show(text) }
    }

    // MARK: Network

    /// Sends one request and reads the answer. A failure is also reported to the Spotify model, so the screen can say so.
    func fetch<Value>(
        _ request: SpotifyRequest, report: Bool = true, read: (Data) -> Value?
    ) async -> Result<Value, SpotifyFailure> {
        var failure = SpotifyFailure.offline
        do {
            let reply = try await spotify.perform(request)
            if reply.isSuccess {
                if let value = read(reply.data) { return .success(value) }
                failure = .http(reply.status)
            } else {
                failure = reply.failure
            }
        } catch {
            failure = (error as? SpotifyFailure) ?? .offline
            // A request that was cancelled is not a connection problem, so it is not shown as one.
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                return .failure(failure)
            }
        }
        if report { spotify.report(failure) }
        return .failure(failure)
    }

    // MARK: Signing out

    /// Forgets everything read from Spotify. Called when the person disconnects (or Spotify signs them out), so whoever
    /// connects next never sees the last account's playlists, likes or profile.
    func reset() {
        epoch += 1
        spotify.log.clear()
        playlistGeneration += 1
        likedGeneration += 1
        section = .nowPlaying
        playlists = .idle
        liked = .idle
        likedTotal = nil
        likedNext = nil
        likedLoadingMore = false
        openPlaylist = nil
        playlistTracks = .idle
        playlistNext = nil
        playlistLoadingMore = false
        profileID = nil
        profileChecked = false
        searchText = ""
        search = .idle
        queue = .idle
        devices = .idle
        devicePickerPresented = false
        likes = [:]
        likeVersion = [:]
        liking = []
    }

    // MARK: Profile

    func loadProfileIfNeeded() async {
        guard profileID == nil else { return }
        let epoch = self.epoch
        // A profile that cannot be read is not worth a banner: the playlists still work, they just cannot tell which are the person's own.
        let outcome = await fetch(SpotifyEndpoint.profile(), report: false, read: SpotifyLibrary.parseProfile)
        guard epoch == self.epoch else { return }
        if case .success(let profile) = outcome {
            profileID = profile.id
        }
        profileChecked = true
    }

    // MARK: Playlists

    func loadPlaylists(force: Bool = false) {
        guard !playlists.isLoading, force || playlists.isIdle else { return }
        playlists = .loading
        Task { await self.runLoadPlaylists() }
    }

    private func runLoadPlaylists() async {
        let epoch = self.epoch
        let result = await fetchAllPlaylists()
        guard epoch == self.epoch else { return }
        playlists = result
        await loadProfileIfNeeded()
    }

    private func fetchAllPlaylists() async -> LoadState<[SpotifyPlaylist]> {
        var all: [SpotifyPlaylist] = []
        var offset = 0
        for _ in 0..<Self.maxPlaylistPages {
            switch await fetch(SpotifyEndpoint.playlists(offset: offset), read: SpotifyLibrary.parsePlaylists) {
            case .success(let page):
                all += page.items
                guard let next = page.nextOffset else { return .loaded(all) }
                offset = next
            case .failure(let failure):
                return all.isEmpty ? .failed(failure) : .loaded(all)
            }
        }
        return .loaded(all)
    }

    /// Opens a playlist. Its tracks load only when Spotify lets us list them.
    func open(_ playlist: SpotifyPlaylist) {
        playlistGeneration += 1
        let generation = playlistGeneration
        openPlaylist = playlist
        playlistTracks = .idle
        playlistNext = nil
        playlistLoadingMore = false
        Task { await self.runOpen(playlist, generation: generation) }
    }

    func closePlaylist() {
        playlistGeneration += 1
        openPlaylist = nil
        playlistTracks = .idle
        playlistNext = nil
        playlistLoadingMore = false
    }

    func retryPlaylistTracks() {
        guard let playlist = openPlaylist else { return }
        open(playlist)
    }

    private func runOpen(_ playlist: SpotifyPlaylist, generation: Int) async {
        await loadProfileIfNeeded()
        guard generation == playlistGeneration, playlist.canListItems(profileID: profileID) else { return }
        playlistTracks = .loading
        let outcome = await fetch(
            SpotifyEndpoint.playlistItems(id: playlist.spotifyID, offset: 0), read: SpotifyLibrary.parsePlaylistItems
        )
        guard generation == playlistGeneration else { return }
        switch outcome {
        case .success(let page):
            playlistTracks = .loaded(page.items)
            playlistNext = page.nextOffset
        case .failure(let failure):
            playlistTracks = .failed(failure)
        }
    }

    /// Called when the last row of the open playlist appears.
    func loadMorePlaylistTracks() {
        guard let playlist = openPlaylist, case .loaded = playlistTracks,
              let offset = playlistNext, !playlistLoadingMore else { return }
        playlistLoadingMore = true
        let generation = playlistGeneration
        Task {
            let outcome = await self.fetch(
                SpotifyEndpoint.playlistItems(id: playlist.spotifyID, offset: offset), read: SpotifyLibrary.parsePlaylistItems
            )
            guard generation == self.playlistGeneration else { return }
            self.playlistLoadingMore = false
            switch outcome {
            case .success(let page):
                if case .loaded(let latest) = self.playlistTracks {
                    self.playlistTracks = .loaded(latest + page.items)
                    self.playlistNext = page.nextOffset
                }
            case .failure:
                self.toast.show("Couldn't load more songs")
            }
        }
    }

    // MARK: Liked Songs

    func loadLiked(reset: Bool = false) {
        guard !liked.isLoading, reset || liked.isIdle else { return }
        likedGeneration += 1
        likedNext = nil
        likedLoadingMore = false
        liked = .loading
        let generation = likedGeneration
        Task { await self.runLoadLiked(generation: generation) }
    }

    private func runLoadLiked(generation: Int) async {
        let outcome = await fetch(SpotifyEndpoint.savedTracks(offset: 0), read: SpotifyLibrary.parseSavedTracks)
        guard generation == likedGeneration else { return }
        switch outcome {
        case .success(let page):
            liked = .loaded(page.items)
            likedNext = page.nextOffset
            likedTotal = page.total
        case .failure(let failure):
            liked = .failed(failure)
        }
    }

    /// Called when the last row of Liked Songs appears.
    func loadMoreLiked() {
        guard case .loaded = liked, let offset = likedNext, !likedLoadingMore else { return }
        likedLoadingMore = true
        let generation = likedGeneration
        Task {
            let outcome = await self.fetch(SpotifyEndpoint.savedTracks(offset: offset), read: SpotifyLibrary.parseSavedTracks)
            guard generation == self.likedGeneration else { return }
            self.likedLoadingMore = false
            switch outcome {
            case .success(let page):
                if case .loaded(let latest) = self.liked {
                    self.liked = .loaded(latest + page.items)
                    self.likedNext = page.nextOffset
                }
            case .failure:
                self.toast.show("Couldn't load more songs")
            }
        }
    }

    // MARK: Search

    private var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Call whenever the text changes. Waits for a pause in typing, then searches for what is in the box by then.
    func searchTextChanged() {
        if searchQuery.isEmpty {
            search = .idle
            return
        }
        Task { await self.runSearch() }
    }

    /// Waits 400 ms, then searches for the text as it is now. If more was typed meanwhile, a newer call handles it,
    /// and an answer to an older text is dropped.
    func runSearch() async {
        let query = searchQuery
        guard !query.isEmpty else {
            search = .idle
            return
        }
        try? await Task.sleep(for: .milliseconds(400))
        guard query == searchQuery else { return }
        // Keep the old results on screen while the new ones load, rather than flashing a spinner on every pause.
        if case .loaded = search {} else { search = .loading }
        let outcome = await fetch(SpotifyEndpoint.search(query), read: SpotifyLibrary.parseSearch)
        guard query == searchQuery else { return }
        switch outcome {
        case .success(let results):
            search = .loaded(results)
        case .failure(let failure):
            search = .failed(failure)
        }
    }

    // MARK: Queue

    /// Reads the queue. Shows a spinner only the first time; later reads replace the list quietly.
    func loadQueue() {
        Task { await self.runLoadQueue() }
    }

    private func runLoadQueue() async {
        let epoch = self.epoch
        if queue.isIdle { queue = .loading }
        // Spotify answers 204 with no body when there is nothing to queue, which is an empty queue, not an error.
        let outcome = await fetch(SpotifyEndpoint.queue()) { data in
            data.isEmpty ? SpotifyQueue() : SpotifyLibrary.parseQueue(data)
        }
        guard epoch == self.epoch else { return }
        switch outcome {
        case .success(let value):
            queue = .loaded(value)
        case .failure(let failure):
            queue = .failed(failure)
        }
    }

    func addToQueue(_ track: SpotifyTrack) {
        Task {
            if await self.spotify.addToQueue(uri: track.uri) {
                self.toast.show("Added to queue")
                self.loadQueue()
            }
        }
    }

    // MARK: Devices

    /// Reads the devices, showing a spinner only the first time.
    func loadDevices() {
        Task { await self.reloadDevices() }
    }

    func reloadDevices() async {
        let epoch = self.epoch
        if devices.isIdle { devices = .loading }
        let outcome = await fetch(SpotifyEndpoint.devices(), read: SpotifyLibrary.parseDevices)
        guard epoch == self.epoch else { return }
        switch outcome {
        case .success(let list):
            devices = .loaded(list)
        case .failure(let failure):
            devices = .failed(failure)
        }
    }

    /// Moves playback to `device` and keeps playing there. With nothing playing there is nothing to move: the device is then
    /// only ready, and the next song the person picks goes to it.
    func transfer(to device: SpotifyDevice) async {
        // This iPhone is played through the Spotify app, never handed playback by the web service.
        if device.type == "Smartphone" {
            startSpotifyHere()
            return
        }
        if await spotify.transfer(to: device) {
            toast.show(SpotifyDevices.movedNotice(deviceName: device.name, somethingIsPlaying: spotify.nowPlaying != nil))
            await reloadDevices()
        }
    }

    // MARK: Likes

    /// Whether Spotify has this song in Liked Songs, for the songs seen this session. Nil while that is not known.
    /// Nothing is saved on this iPhone: Spotify is the only place a like lives.
    private(set) var likes: [String: Bool] = [:]
    @ObservationIgnored private var likeVersion: [String: Int] = [:]
    @ObservationIgnored private var liking: Set<String> = []

    /// Only songs can be liked: not podcast episodes, local files or ads.
    static func canLike(_ uri: String?) -> Bool {
        uri?.hasPrefix("spotify:track:") == true
    }

    func isLiked(_ uri: String) -> Bool? {
        likes[uri]
    }

    /// Asks Spotify whether this song is liked. Run whenever the song changes, so a like made in the Spotify app shows up too.
    /// A failure is not worth a banner: the heart just stays unknown, and tapping it asks again.
    func refreshLiked(for uri: String) {
        guard Self.canLike(uri), !liking.contains(uri) else { return }
        let version = likeVersion[uri, default: 0]
        let epoch = self.epoch
        Task {
            let outcome = await self.fetch(
                SpotifyEndpoint.contains(uris: [uri]), report: false, read: SpotifyLibrary.parseContains
            )
            // A like or unlike made while this was in flight is newer than the answer, and so is a sign-out.
            guard epoch == self.epoch, version == self.likeVersion[uri, default: 0] else { return }
            if case .success(let answers) = outcome, let liked = answers.first {
                self.likes[uri] = liked
            }
        }
    }

    /// Likes or unlikes the song at once, then tells Spotify. If Spotify says no, the heart goes back and the reason is shown.
    func toggleLiked(_ uri: String) {
        guard Self.canLike(uri), !liking.contains(uri) else { return }
        guard let before = likes[uri] else {
            refreshLiked(for: uri)
            return
        }
        let target = !before
        liking.insert(uri)
        likeVersion[uri, default: 0] += 1
        likes[uri] = target
        let epoch = self.epoch
        Task {
            let request = target ? SpotifyEndpoint.save(uris: [uri]) : SpotifyEndpoint.remove(uris: [uri])
            let outcome = await self.fetch(request) { _ in true }
            guard epoch == self.epoch else { return }
            self.liking.remove(uri)
            switch outcome {
            case .success:
                self.toast.show(target ? "Added to Liked Songs" : "Removed from Liked Songs")
                self.invalidateLiked()
            case .failure:
                self.likes[uri] = before
                self.toast.show("Couldn't update Liked Songs")
            }
        }
    }

    /// Forgets the loaded Liked Songs list, so it is read again the next time it is shown.
    private func invalidateLiked() {
        likedGeneration += 1
        likedNext = nil
        likedLoadingMore = false
        likedTotal = nil
        liked = .idle
    }

    // MARK: Playing

    /// Starts something playing and shows Now Playing.
    func play(_ target: SpotifyPlayTarget) async {
        await start(target, shuffled: false)
    }

    /// Turns shuffle on and plays.
    func shufflePlay(_ target: SpotifyPlayTarget) async {
        await start(target, shuffled: true)
    }

    /// On this iPhone (the default) the Spotify app is asked to play, through `SpotifyModel.playOnPhone`. On a TV or speaker
    /// the person picked, Spotify's web service sends the command.
    private func start(_ target: SpotifyPlayTarget, shuffled: Bool) async {
        guard spotify.phase == .signedIn else { return }
        section = .nowPlaying
        spotify.log.add("Play \(shuffled ? "(shuffled) " : "")\(Self.describeTarget(target))")
        if let chosenID = spotify.chosenDeviceID {
            await playOnChosenDevice(chosenID, target: target, shuffled: shuffled)
        } else {
            await playOnThisPhone(target, shuffled: shuffled)
        }
    }

    /// Works out where in its list the tapped song is, so the Spotify app can play the playlist or Liked Songs from it.
    private func playOnThisPhone(_ target: SpotifyPlayTarget, shuffled: Bool) async {
        var index: Int?
        var likedCollection: String?
        switch target {
        case .context(let uri, let song?):
            // A song tapped inside the open playlist. An album song from Search has its place looked up by the Spotify app.
            if openPlaylist?.uri == uri {
                index = playlistTracks.value?.firstIndex(where: { $0.uri == song })
            }
        case .uris(let uris) where uris.count > 1:
            // A song tapped in Liked Songs: the list starts at it.
            if let first = uris.first, let position = liked.value?.firstIndex(where: { $0.uri == first }) {
                await loadProfileIfNeeded()
                index = position
                likedCollection = profileID.map(SpotifyPhone.likedCollectionURI(userID:))
            }
        default:
            break
        }
        guard let plan = SpotifyPhone.plan(for: target, shuffled: shuffled, index: index, likedCollection: likedCollection) else { return }
        spotify.playOnPhone(plan)
        // Keeps this phone's name from Spotify's device list current, for the "Playing on" line.
        _ = await readDevices()
    }

    private static func describeTarget(_ target: SpotifyPlayTarget) -> String {
        switch target {
        case .context(let uri, let startAt):
            return startAt.map { "\(uri) from \($0)" } ?? uri
        case .uris(let uris):
            return "\(uris.count) song\(uris.count == 1 ? "" : "s"), first \(uris.first ?? "none")"
        }
    }

    /// The devices Spotify lists right now, or nil when it could not be asked. Also refreshes the list the picker shows and
    /// tells the Spotify model this phone's name.
    private func readDevices() async -> [SpotifyDevice]? {
        switch await fetch(SpotifyEndpoint.devices(), report: false, read: SpotifyLibrary.parseDevices) {
        case .success(let list):
            devices = .loaded(list)
            if let phone = list.first(where: { $0.type == "Smartphone" && !$0.isRestricted }) {
                spotify.setPhoneName(phone.name)
            }
            return list
        case .failure:
            return nil
        }
    }

    // MARK: A TV or speaker the person picked

    private func playOnChosenDevice(_ chosenID: String, target: SpotifyPlayTarget, shuffled: Bool) async {
        let epoch = self.epoch
        let list = await readDevices()
        guard epoch == self.epoch else { return }
        guard let list else {
            // The list could not be read: Spotify's active device, or the picked one.
            await playOnWhatSpotifyChooses(target, shuffled: shuffled)
            return
        }
        guard let device = list.first(where: { $0.id == chosenID && !$0.isRestricted }) else {
            spotify.log.add("The picked device is no longer listed; playing on this iPhone")
            toast.show("\(spotify.chosenDeviceName ?? "That device") is off. Playing on this iPhone.")
            spotify.forgetChosenDevice()
            await playOnThisPhone(target, shuffled: shuffled)
            return
        }
        await play(target, shuffled: shuffled, on: device)
    }

    /// The web service sends the command, and the player is watched for a few seconds, because a device can accept a command
    /// and then play nothing.
    private func play(_ target: SpotifyPlayTarget, shuffled: Bool, on device: SpotifyDevice) async {
        let epoch = self.epoch
        // A device Spotify already counts as active takes shuffle at once, so the first song is already shuffled.
        var shuffleSet = false
        if shuffled, device.isActive { shuffleSet = await spotify.setShuffle(true) }
        if let failure = await spotify.play(target, on: device) {
            spotify.log.add("\(device.name) refused: \(failure.message)")
            spotify.showPlayFailure(failure)
            return
        }
        spotify.log.add("\(device.name) accepted the request")
        guard epoch == self.epoch else { return }
        if shuffled, !shuffleSet { await spotify.setShuffle(true) }
        for second in 0...5 {
            if second > 0 { try? await Task.sleep(for: .seconds(1)) }
            await spotify.refresh()
            guard epoch == self.epoch, spotify.phase == .signedIn else { return }
            if SpotifyDevices.startedOn(device, playingOn: spotify.nowPlaying?.deviceName) {
                spotify.log.add("Playing on \(device.name)")
                return
            }
        }
        spotify.log.add("Not playing on \(device.name)")
        toast.show("Spotify took the request but nothing is playing on \(device.name).")
    }

    /// Used when the device list could not be read: Spotify's active device, or the one the person picked.
    private func playOnWhatSpotifyChooses(_ target: SpotifyPlayTarget, shuffled: Bool) async {
        let shuffleSet = shuffled ? await spotify.setShuffle(true) : true
        guard await spotify.play(target) else { return }
        if !shuffleSet { await spotify.setShuffle(true) }
        let epoch = self.epoch
        try? await Task.sleep(for: .seconds(3))
        await spotify.refresh()
        guard epoch == self.epoch, spotify.phase == .signedIn, spotify.hasAnswered, spotify.nowPlaying == nil else { return }
        toast.show("Spotify took the request but nothing is playing.")
    }

    // MARK: This iPhone

    /// The "This iPhone" row in the device list: starts Spotify on this iPhone with its last song, and goes back to playing
    /// here by default.
    func startSpotifyHere() {
        guard !spotify.clientID.isEmpty else { return }
        spotify.startSpotifyHere()
    }
}
