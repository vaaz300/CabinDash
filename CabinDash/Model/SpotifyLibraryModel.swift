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

    /// A long library is read this many pages deep at most (50 playlists a page).
    private static let maxPlaylistPages = 6

    init(spotify: SpotifyModel, toast: ToastCenter) {
        self.spotify = spotify
        self.toast = toast
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

    // MARK: Profile

    func loadProfileIfNeeded() async {
        guard profileID == nil else { return }
        // A profile that cannot be read is not worth a banner: the playlists still work, they just cannot tell which are the person's own.
        if case .success(let profile) = await fetch(SpotifyEndpoint.profile(), report: false, read: SpotifyLibrary.parseProfile) {
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
        playlists = await fetchAllPlaylists()
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
        if queue.isIdle { queue = .loading }
        // Spotify answers 204 with no body when there is nothing to queue, which is an empty queue, not an error.
        let outcome = await fetch(SpotifyEndpoint.queue()) { data in
            data.isEmpty ? SpotifyQueue() : SpotifyLibrary.parseQueue(data)
        }
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
        if devices.isIdle { devices = .loading }
        switch await fetch(SpotifyEndpoint.devices(), read: SpotifyLibrary.parseDevices) {
        case .success(let list):
            devices = .loaded(list)
        case .failure(let failure):
            devices = .failed(failure)
        }
    }

    /// Moves playback to `device` and keeps playing there.
    func transfer(to device: SpotifyDevice) async {
        if await spotify.transfer(to: device.id) {
            toast.show("Playing on \(device.name)")
            await reloadDevices()
        }
    }

    // MARK: Playing

    /// Starts something playing and, if Spotify accepts it, shows Now Playing.
    func play(_ target: SpotifyPlayTarget) async {
        if await spotify.play(target) { section = .nowPlaying }
    }

    /// Turns shuffle on, then plays. If shuffle could not be set first (no device was ready), it is set again once playing has started.
    func shufflePlay(_ target: SpotifyPlayTarget) async {
        let shuffled = await spotify.setShuffle(true)
        guard await spotify.play(target) else { return }
        if !shuffled { await spotify.setShuffle(true) }
        section = .nowPlaying
    }
}
