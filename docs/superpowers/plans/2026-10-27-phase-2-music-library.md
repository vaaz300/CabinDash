# Phase 2: Music Library Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the Music screen into a small Spotify client inside Cabin Dash (Now Playing with shuffle, repeat and like; your playlists; Liked Songs; search; the queue; a device picker), and bring the driving lock forward so search cannot be typed while moving.

**Architecture:** Everything that can be pure goes in `CabinCore` with tests: Spotify request builders, response parsers, the scope check, the no-device rule and the driving lock. The app gets one new model (`SpotifyLibraryModel`) that calls Spotify through the existing `SpotifyModel` (which keeps the token, the polling and the control commands). `MusicScreen` becomes a container with a section bar over small panes. Spotify still plays the audio in its own app; Cabin Dash is the screen and remote.

**Tech Stack:** Swift 5 language mode, SwiftUI, iOS 17+, SwiftPM package `CabinCore` with Swift Testing, XcodeGen, GitHub Actions on macOS. No new packages.

**Spec:** `docs/superpowers/specs/2026-10-26-self-contained-cabin-dash-design.md`, section 4.2 and phase 2 (approved with defaults D1 to D6 on 2026-10-26). Two changes the user approved on 2026-10-27: (1) the driving lock moves from Phase 4 into this phase, because Phase 2 adds a search box; (2) Music becomes a full in-app section (browse and play without leaving Cabin Dash), within D3 (playlists, search, queue, like; no Browse tab, no artist pages).

## Global Constraints

* iOS 17.0 deployment target; iPhone only; **landscape only**; `SWIFT_VERSION` stays `"5.0"`.
* Free Apple Account sideload: **no entitlements, no new capabilities, no signing changes.** `Config/Signing.xcconfig` untouched. No `DEVELOPMENT_TEAM`/`CODE_SIGN_*` in `project.yml`.
* **No new Info.plist keys, no new packages, no web views, no private APIs.** `Config/`, `project.yml` and `.github/` are not edited in this phase.
* Spotify (verified 27 Oct 2026 against Spotify's pages): Web API only, PKCE, no client secret. Dev-mode search `limit` max **10**. `GET /playlists/{id}/items` works only for playlists the user **owns or collaborates on**; other playlists return metadata only. Playlist objects use `items` where they used `tracks`; playlist item objects use `item` where they used `track` (parse both). Save/remove/check use `PUT|DELETE /v1/me/library?uris=` and `GET /v1/me/library/contains?uris=`, **max 40 URIs**, comma-separated Spotify URIs. `GET /v1/me/tracks`, `GET /v1/me/playlists` and all `/v1/me/player/*` are unchanged. Removed, so not used: browse/categories, new releases, artist top tracks, batch lookups, `GET /users/{id}`.
* **No voice control of Spotify** (Spotify Developer Policy). The Like action must go to Spotify, and Cabin Dash must not keep its own copy of likes beyond what is on screen.
* Pure logic goes in `CabinCore` with Swift Testing `@Test`. Declared `@Test` count must never exceed what executes (`scripts/ci/check_tests.py`). App models are `@MainActor @Observable`. In `Task {}` inside views use `self.model` or a captured local, not the local `@Bindable`.
* No Swift compiler exists here. Nothing is "passing" until GitHub Actions says so. Never claim a build or test result that was not read from GitHub.
* Every commit message ends with:
  `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01BFMMCGikHkv4vMTFkLsjXY`
* Push with `git push origin HEAD:main` from `/home/claude/cabindash`. Docs-only pushes do not build. A later push cancels a run still in progress.
* **Reading CI** (public API, no token): `https://api.github.com/repos/vaaz300/cabindash/actions/runs?per_page=5` for status by `head_sha`; `.../runs/<id>/jobs` for each step's conclusion while the run is still going. Step **"Unit tests on the Mac (swift test)"** finishes about 4 minutes in and is the TDD gate; the whole run takes 6 to 11 minutes. Logs and annotations of failures need a login: on a red step with no readable cause, ask the user to paste the "App build" block. A poll helper lives at `.superpowers/sdd/<plan-basename>/ci.py` (git-ignored); recreate it if missing.
* **TDD cadence for CabinCore tasks:** commit the tests (RED), push, wait for the "Unit tests on the Mac" step to show `failure` (a compile error naming a missing symbol counts), implement, commit (GREEN), push, wait for that step to show `success`. App-layer tasks have no unit test; their gate is the full run (compile) plus the phone checklist in Task 11.

## Review Focus

Failure modes the spec implies that the happy path hides, most likely first. Each is pinned in the task named.

1. **The old saved token has no scopes.** After this build the user's existing sign-in lacks the library scopes and must land on a clear "connect again" state, not a loop and not a stream of 403s. Task 1.
2. **Spotify sends gaps.** A playlist with no picture, `null` entries in search or playlist items (deleted tracks), podcast episodes in a queue, local files, a playlist with no count. None may crash or blank a list. Task 4.
3. **Playlists you do not own** (Spotify's own, followed ones) cannot list tracks. The pane must offer Play with a one-line reason, not an error. Task 4 (`canListItems`) and Task 7.
4. **No active device.** A tap on a track must not silently do nothing: start on the only device Spotify lists, otherwise say so and open the device picker. Never pick one of several devices on the user's behalf. Task 5 and Task 8.
5. **Typing while moving, and GPS loss.** The lock engages at 8 km/h or more, stays engaged through a GPS dropout and through a stop at lights (releases only after 10 s below 4 km/h), and Passenger mode overrides it. Task 6.

## File Structure

| File | Responsibility |
|---|---|
| `CabinCore/.../SpotifyAuth.swift` (modify) | Seven scopes; `SpotifyToken.scope`; `SpotifyAuth.missingScopes`. |
| `CabinCore/.../SpotifyRequests.swift` (new) | `SpotifyRequest`, `SpotifyEndpoint`, `SpotifyPlayTarget`, `SpotifyRepeat`. |
| `CabinCore/.../Spotify.swift` (modify) | `NowPlaying` gains shuffle, repeat, URIs, disallowed actions. `noActiveDevice` message. |
| `CabinCore/.../SpotifyLibrary.swift` (new) | Models, `SpotifyPage`, parsers, `SpotifyDevices.autoTarget`, `SpotifyLink`. |
| `CabinCore/.../DrivingLock.swift` (new) | `DrivingLock`. `Preferences.passengerMode` (modify `Preferences.swift`). |
| `CabinCore/.../MusicSection.swift` (new) | The five Music sections. |
| `CabinDash/Model/SpotifyModel.swift` (modify) | `needsReconnect` phase, request-based network, shuffle, repeat, `play` with the no-device rule. |
| `CabinDash/Model/SpotifyLibraryModel.swift` (new) | Loads and holds playlists, liked songs, search, queue, devices, likes. |
| `CabinDash/Model/AppModel.swift` (modify) | Holds `library`; motion and `typingLocked`; `openSpotify(uri:)`. |
| `CabinDash/Views/Music/` | `MusicScreen` (container), `NowPlayingScreen` renamed `NowPlayingPane`, `PlaylistsPane`, `LikedPane`, `SearchPane`, `QueuePane`, `DeviceSheet`, `TrackRow`, `SpotifyAttribution`. |
| `scripts/add_spotify_icon.py` (new) | Installs Spotify's official icon, supplied by the user, into the asset catalog. |
| `docs/` | `SPOTIFY-SETUP.md`, new `SPOTIFY-RULES.md`, `README.md`, `AUDIT.md`. |

---

### Task 1: Scopes and the reconnect state

**Files:** Modify `CabinCore/Sources/CabinCore/SpotifyAuth.swift`, `CabinCore/Tests/CabinCoreTests/SpotifyAuthTests.swift`, `CabinDash/Model/SpotifyModel.swift`, `CabinDash/Views/Music/NowPlayingScreen.swift`, `CabinDash/Views/Settings/SettingsScreen.swift`.

**Interfaces:**
- Produces: `SpotifyAuth.scopes: [String]` (the old three, then `playlist-read-private`, `playlist-read-collaborative`, `user-library-read`, `user-library-modify`); `SpotifyAuth.missingScopes(granted: String?) -> [String]` (nil or empty grants everything missing); `SpotifyToken.scope: String?` (init parameter `scope: String? = nil`, last); `SpotifyToken.parse(_:now:previousRefresh:previousScope: String? = nil)`; `SpotifyToken.hasAllRequiredScopes: Bool`. `SpotifyModel.Phase.needsReconnect`.

- [ ] **Step 1: Tests (RED).** In `SpotifyAuthTests`: change `authorizeURLCarriesEverySpotifyNeeds` to expect `scope=user-read-playback-state%20user-modify-playback-state%20user-read-currently-playing%20playlist-read-private%20playlist-read-collaborative%20user-library-read%20user-library-modify`. Add `requiredScopesCoverLibraryAndPlaylists`, `tokenAnswerCarriesItsScope` (answer with `"scope":"a b"` gives `scope == "a b"`), `refreshWithoutScopeKeepsThePreviousScope` (`previousScope: "a b"`), `oldSavedTokenWithoutScopeNeedsReconnect` (decode `{"accessToken":"a","refreshToken":"r","expiresAt":0}`; `scope == nil`; `hasAllRequiredScopes == false`; `missingScopes(granted: nil) == SpotifyAuth.scopes`), `tokenWithEveryScopeIsFine`, `missingScopesNamesTheOnesLeftOut` (granted lacking `user-library-modify` returns exactly that one), `scopeComparisonIgnoresOrderAndExtraSpaces`.
- [ ] **Step 2: Push RED; confirm the Mac-test step fails.**
- [ ] **Step 3: Implement** the interfaces above in `SpotifyAuth.swift` (scope strings compared as a set split on whitespace). Commit GREEN, push, confirm the step passes.
- [ ] **Step 4: App wiring (no test).** `SpotifyModel.init`: a saved token that lacks scopes gives `phase = .needsReconnect`; `signIn()` accepts `.signedOut` and `.needsReconnect`; `exchange`/`performRefresh` store the answer's scope (`previousScope` on refresh); `statusText` for `.needsReconnect` is "Needs new permissions"; `signOut` unchanged. The Music state panel and Settings show, for `.needsReconnect`, the title "Connect Spotify again" with the line "Cabin Dash now browses your playlists and likes songs, which needs a few more permissions. You only do this once." and the same Connect button. Update every exhaustive `switch` on `Phase`.
- [ ] **Step 5: Commit and push.** Gate: the full run compiles.

### Task 2: Request builders, and `SpotifyModel` sends through them

**Files:** Create `CabinCore/Sources/CabinCore/SpotifyRequests.swift`, `CabinCore/Tests/CabinCoreTests/SpotifyRequestTests.swift`. Modify `CabinDash/Model/SpotifyModel.swift`.

**Interfaces:**
- Produces: `SpotifyRequest { method: String; path: String; query: [URLQueryItem]; body: Data? }` with `func url() -> URL?` (`https://api.spotify.com` + path + query escaped with `FormEncoding`). `SpotifyRepeat: String { off, context, track }` with `next` (off, context, track, off), `init(spotifyValue: String?)` (unknown gives `.off`), `title`, `symbol`. `SpotifyPlayTarget { case context(uri: String, startAtURI: String?); case uris([String]) }` with `static func window(_ uris: [String], startingAt index: Int, limit: Int = 100) -> SpotifyPlayTarget` (`.uris` of at most `limit` entries starting at `index`; an index outside the list is clamped; an empty list gives `.uris([])`). `SpotifyEndpoint` static functions, all returning `SpotifyRequest`: `player()`, `resume(deviceID:)`, `pause()`, `play(_:deviceID:)`, `next()`, `previous()`, `seek(milliseconds:)`, `shuffle(_:)`, `setRepeat(_:)`, `queue()`, `addToQueue(uri:)`, `devices()`, `transfer(to:play:)`, `profile()`, `playlists(offset:)`, `playlistItems(id:offset:)`, `savedTracks(offset:)`, `search(_:)`, `save(uris:)`, `remove(uris:)`, `contains(uris:)`.

- [ ] **Step 1: Tests (RED).** One test per endpoint asserting `method`, `path`, `query` and `body`: `player()` is `GET /v1/me/player?additional_types=track,episode`; `play(.context(uri:"spotify:playlist:p1", startAtURI:"spotify:track:t9"))` is `PUT /v1/me/player/play` with body exactly `{"context_uri":"spotify:playlist:p1","offset":{"uri":"spotify:track:t9"}}`; `play(.uris(["a","b"]), deviceID:"d1")` has query `device_id=d1` and body `{"uris":["a","b"]}`; `play(.context(uri:"x", startAtURI:nil))` has no `offset`; `transfer(to:"d1", play:true)` is `PUT /v1/me/player` body `{"device_ids":["d1"],"play":true}`; `shuffle(true)` query `state=true`; `setRepeat(.context)` query `state=context`; `addToQueue(uri:)` is `POST` with `uri=`; `playlists(offset:100)` has `limit=50&offset=100`; `playlistItems(id:"abc", offset:0)` path `/v1/playlists/abc/items`; `search("daft punk")` has `type=track,album,playlist`, `limit=10`, and `q` escaped (`daft%20punk` in `url()`); `save(uris:)` is `PUT /v1/me/library` and `remove` is `DELETE`, `contains` is `GET /v1/me/library/contains`, each with `uris` joined by commas (`%2C` in `url()`); `window` cases (start in the middle, start past the end, more than 100 entries, empty); `SpotifyRepeat.next` cycle and `init(spotifyValue:)` for `"track"`, `"context"`, `"off"`, `nil`, `"bogus"`. Bodies are encoded with `.sortedKeys` and `.withoutEscapingSlashes`.
- [ ] **Step 2: Push RED; confirm failure. Step 3: Implement** in `SpotifyRequests.swift`; commit GREEN; push; confirm success.
- [ ] **Step 4: App refactor (no test).** In `SpotifyModel` replace the private `send(method,path,query)` by `func perform(_ request: SpotifyRequest) async throws -> SpotifyReply`, where `struct SpotifyReply { data, status, retryAfter; var isSuccess: Bool; var failure: SpotifyFailure }` is internal. Keep the 401-then-refresh retry, the empty-body rule for non-GET, and `pausedUntil`. `refresh`, `togglePlayPause`, `skipNext`, `skipPrevious`, `seek` use `SpotifyEndpoint`. Add `func report(_ error: Error)` (internal, wraps `handle`). Behaviour must not change; add nothing else.
- [ ] **Step 5: Commit and push.** Gate: the full run compiles and the existing Spotify tests still pass.

### Task 3: Playback state and the Now Playing controls

**Files:** Modify `CabinCore/Sources/CabinCore/Spotify.swift`, `CabinCore/Tests/CabinCoreTests/SpotifyTests.swift`, `CabinDash/Views/Music/NowPlayingScreen.swift`, `CabinDash/Model/SpotifyModel.swift`.

**Interfaces:**
- Consumes: `SpotifyRepeat` (Task 2).
- Produces: `NowPlaying` gains `uri: String?`, `albumURI: String?`, `contextURI: String?`, `shuffle: Bool`, `repeatMode: SpotifyRepeat`, `disallows: Set<String>` (init parameters appended after `deviceName`, all defaulted) and computed `canSkipNext`, `canSkipPrevious`, `canSeek`, `canShuffle`, `canRepeat` (false when Spotify lists `skipping_next`, `skipping_prev`, `seeking`, `toggling_shuffle`, or both `toggling_repeat_context` and `toggling_repeat_track` under `actions.disallows`). `SpotifyModel.toggleShuffle()`, `cycleRepeat()`. `SpotifyFailure.noActiveDevice.message` becomes "Spotify has no device ready to play. Choose one under Devices, or open Spotify once."

- [ ] **Step 1: Tests (RED).** `readsShuffleRepeatAndContext` (`shuffle_state:true`, `repeat_state:"context"`, `context.uri:"spotify:playlist:p1"`), `readsTheTrackAndAlbumURIs`, `readsDisallowedActions` (`actions.disallows` with `skipping_prev:true`, `resuming:true` gives `canSkipPrevious == false`, `canSkipNext == true`), `aFalseDisallowDoesNotDisable`, `missingFieldsDefaultSafely` (the existing track JSON gives `shuffle == false`, `repeatMode == .off`, empty `disallows`, all `can*` true), `episodeKeepsItsURI`. Keep `everyFailureHasAMessage` green.
- [ ] **Step 2: Push RED; confirm failure. Step 3: Implement** the parsing; commit GREEN; push; confirm success.
- [ ] **Step 4: App (no test).** `SpotifyModel.toggleShuffle()` sets the local `shuffle` optimistically and sends `SpotifyEndpoint.shuffle`; `cycleRepeat()` sends `setRepeat(current.next)`; both refresh after 400 ms like the other commands. `NowPlayingPane` gets a second row under the transport: shuffle (highlighted when on) and repeat (symbol `repeat` or `repeat.1`, highlighted when not off). Previous, next and the progress drag are disabled (dimmed, no action) when `can*` is false. Artwork corner radius becomes 8 (thumbnails 4) per Spotify's design guidelines.
- [ ] **Step 5: Commit and push.**

### Task 4: Library models and parsers

**Files:** Create `CabinCore/Sources/CabinCore/SpotifyLibrary.swift`, `CabinCore/Tests/CabinCoreTests/SpotifyLibraryTests.swift`.

**Interfaces:**
- Consumes: `SpotifyPlayTarget` (Task 2), `SpotifyPlayback.largestImage`.
- Produces (all `public`, `Equatable`, `Sendable`): `SpotifyTrack { uri, name, subtitle, albumName, albumURI: String?, artworkURL: URL?, duration: TimeInterval, isPlayable: Bool; id (= uri); playTarget: SpotifyPlayTarget }` where `playTarget` is `.context(uri: albumURI, startAtURI: uri)` when an album URI exists, else `.uris([uri])`. `SpotifyPlaylist { uri, name, artworkURL, ownerID, ownerName, trackCount: Int?, isCollaborative: Bool; id (= uri); func canListItems(profileID: String?) -> Bool }` (true when collaborative, or `ownerID == profileID` and the profile is known). `SpotifyAlbum { uri, name, artist, artworkURL }`. `SpotifyDevice { id, name, type, isActive, isRestricted }`. `SpotifyQueue { current: SpotifyTrack?, upNext: [SpotifyTrack] }`. `SpotifySearchResults { tracks, albums, playlists }`. `SpotifyProfile { id, name }`. `SpotifyPage<Item> { items: [Item]; nextOffset: Int?; total: Int? }`. `enum SpotifyLibrary` with `parsePlaylists(_:) -> SpotifyPage<SpotifyPlaylist>?`, `parsePlaylistItems(_:) -> SpotifyPage<SpotifyTrack>?`, `parseSavedTracks(_:) -> SpotifyPage<SpotifyTrack>?`, `parseSearch(_:) -> SpotifySearchResults?`, `parseQueue(_:) -> SpotifyQueue?`, `parseDevices(_:) -> [SpotifyDevice]?`, `parseContains(_:) -> [Bool]?`, `parseProfile(_:) -> SpotifyProfile?`. Each returns nil for empty or non-JSON data. `nextOffset` is `offset + limit` from the paging object when `next` is a non-empty string, else nil. Thumbnails use the smallest picture at least 120 px wide, else the largest (`SpotifyPlayback.thumbnail(in:)`, new).

- [ ] **Step 1: Tests (RED).** Fixtures as JSON strings. `playlistsReadNewItemsTotal` (`items.total: 12`), `playlistsReadOldTracksTotal` (`tracks.total: 7`), `playlistWithoutPicturesOrCountStillParses` (`images: null`, no total gives `artworkURL == nil`, `trackCount == nil`), `playlistsKeepTheNextOffset` (`next` set, `offset:0`, `limit:50` gives 50; `next: null` gives nil), `canListItemsForOwnCollaborativeAndNotOthers` (owner equals profile true; collaborative true; other owner false; unknown profile false), `playlistItemsReadItemKey` and `playlistItemsReadTrackKey`, `playlistItemsSkipNullAndMalformedEntries`, `localFilesAreNotPlayable`, `episodesUseTheShowAsSubtitle`, `savedTracksReadTheTrackKey`, `searchReadsThreeSections`, `searchSkipsNullPlaylists` (a `null` inside `playlists.items`), `searchWithAMissingSectionGivesEmptyArray`, `queueReadsCurrentAndUpNext`, `queueWithNothingPlayingHasNoCurrent`, `devicesReadsTypeAndActive` (a device with `id: null` is dropped), `containsReadsBooleans`, `profileReadsIdAndName`, `trackPlayTargetUsesTheAlbumAsContext`, `trackWithoutAnAlbumPlaysItselfAlone`, `thumbnailPrefersASmallEnoughPicture` (64, 300, 640 gives 300), `everyParserReturnsNilForEmptyData`.
- [ ] **Step 2: Push RED; confirm failure. Step 3: Implement;** commit GREEN; push; confirm success.

### Task 5: The no-device rule and links to Spotify

**Files:** Modify `CabinCore/Sources/CabinCore/SpotifyLibrary.swift`; create `CabinCore/Tests/CabinCoreTests/SpotifyDeviceTests.swift`.

**Interfaces:**
- Produces: `SpotifyDevices.autoTarget(_ devices: [SpotifyDevice]) -> SpotifyDevice?` (the device only when exactly one usable device exists, usable meaning not restricted; otherwise nil). `SpotifyLink.openURLs(forURI uri: String?) -> [URL]` (`spotify:track:X` gives `[spotify:track:X, https://open.spotify.com/track/X]`; works for track, album, playlist, episode, show, artist; nil or anything else gives `[spotify://, https://open.spotify.com]`). `SpotifyLink.label` is `"Open Spotify"` (Spotify's required wording).

- [ ] **Step 1: Tests (RED).** `noDevicesGivesNoTarget`, `oneDeviceIsTheTarget`, `twoDevicesGiveNoTarget` (never guesses), `aRestrictedDeviceDoesNotCount` (one restricted, one usable gives the usable one), `onlyRestrictedGivesNone`, `trackLinkOpensTheTrack`, `playlistLinkAndAlbumLink`, `unknownOrMissingURIOpensSpotifyItself`, `aLocalFileURIOpensSpotifyItself`.
- [ ] **Step 2: Push RED; confirm failure. Step 3: Implement;** commit GREEN; push; confirm success.

### Task 6: Driving lock and Passenger mode

**Files:** Create `CabinCore/Sources/CabinCore/DrivingLock.swift`, `CabinCore/Tests/CabinCoreTests/DrivingLockTests.swift`. Modify `CabinCore/Sources/CabinCore/Preferences.swift`, `CabinCore/Tests/CabinCoreTests/OtherAppsSwitchTests.swift` (old-save tests live there), `CabinDash/Model/AppModel.swift`, `CabinDash/Views/RootView.swift`, `CabinDash/Views/Settings/SettingsScreen.swift`.

**Interfaces:**
- Produces: `DrivingLock` (struct, `Equatable`, `Sendable`): `static let engageSpeed = 8.0 / 3.6` and `releaseSpeed = 4.0 / 3.6` (m/s), `releaseHold = 10.0` (seconds), `isMoving: Bool` (starts false), `mutating func update(speed: Double?, at time: Double)`, `func isTypingLocked(passengerMode: Bool) -> Bool`. Rules: `speed == nil` (no usable GPS) changes nothing. A speed at or above `engageSpeed` sets `isMoving` and clears the slow timer. While moving, a speed below `releaseSpeed` starts a slow timer; `isMoving` clears only when the speed has stayed below `releaseSpeed` for `releaseHold` seconds; any faster reading restarts the timer. From rest, speeds between the two thresholds do not engage. `Preferences.passengerMode: Bool` (default false; tolerant decode; added to `CodingKeys` and `init`).

- [ ] **Step 1: Tests (RED).** `startsUnlocked`, `engagesAtEightKmh` (exactly `engageSpeed` engages), `doesNotEngageBelowEightFromRest`, `staysEngagedBetweenFourAndEight`, `staysEngagedThroughAShortStop` (3 m/s then 0 m/s for 9 s stays; at 10 s releases), `aMovingReadingResetsTheStopTimer`, `unknownSpeedKeepsEngaged`, `unknownSpeedKeepsReleased`, `passengerModeNeverLocks` (`isTypingLocked(passengerMode: true)` is false while moving), `lockedOnlyWhenMovingAndNotPassenger`. In the preferences tests: `oldSavesDefaultPassengerModeOff` (JSON without the key) and `passengerModeSurvivesSavingAndLoading`.
- [ ] **Step 2: Push RED; confirm failure. Step 3: Implement;** commit GREEN; push; confirm success.
- [ ] **Step 4: App (no test).** `AppModel`: `@ObservationIgnored private var lock = DrivingLock()`, `private(set) var isMoving = false` (assigned only when it changes, so views do not redraw every fix), `func noteMotion(speed: Double?, at time: Double)`, `var typingLocked: Bool { isMoving && !prefs.passengerMode }`. `RootView` calls `model.noteMotion(speed: location.hasFix ? location.speed : nil, at: Date().timeIntervalSinceReferenceDate)` inside the existing `.onChange(of: location.fixCount)`. Settings, Driving section: `Toggle("Passenger mode", isOn: $model.prefs.passengerMode)` with footer "Cabin Dash turns off typing, such as music search, while you are moving faster than about 8 km/h. Turn this on if someone else is using the screen."
- [ ] **Step 5: Commit and push.**

### Task 7: Library model, the Music container, Playlists and Liked Songs

**Files:** Create `CabinCore/Sources/CabinCore/MusicSection.swift`, `CabinCore/Tests/CabinCoreTests/MusicSectionTests.swift`, `CabinDash/Model/SpotifyLibraryModel.swift`, `CabinDash/Views/Music/MusicScreen.swift`, `PlaylistsPane.swift`, `LikedPane.swift`, `TrackRow.swift`. Modify `CabinDash/Model/AppModel.swift`, `CabinDash/Views/RootView.swift`, `CabinDash/Views/Music/NowPlayingScreen.swift` (struct renamed `NowPlayingPane`, outer padding moved to `MusicScreen`).

**Interfaces:**
- Consumes: parsers and `SpotifyPlayTarget` (Tasks 2, 4), `SpotifyLink.openURLs` (Task 5), `SpotifyModel.perform`, `.report`.
- Produces: `MusicSection: String, CaseIterable, Hashable, Sendable { nowPlaying, playlists, liked, search, queue }` with `title` ("Now Playing", "Playlists", "Liked", "Search", "Queue") and `symbol` (`play.circle.fill`, `music.note.list`, `heart.fill`, `magnifyingglass`, `list.bullet`). `SpotifyLibraryModel(spotify: SpotifyModel, toast: ToastCenter)`: `section: MusicSection`; `LoadState<Value>` (`idle`, `loading`, `loaded(Value)`, `failed(SpotifyFailure)`); `playlists`, `liked`, `profileID`; `loadPlaylists()`, `loadProfileIfNeeded()`, `loadLiked(reset:)`, `loadMoreLiked()`, `open(_ playlist:)`, `play(_ target: SpotifyPlayTarget)` (calls `spotify.play`, switches `section` to `.nowPlaying` on success). `SpotifyModel.play(_ target: SpotifyPlayTarget) async` (plain send of `SpotifyEndpoint.play`, then refresh; Task 8 adds the no-device recovery). `SpotifyAttribution` view (the word "Spotify" plus an "Open Spotify" link) replacing `OpenSpotifyButton`, and `AppModel.openSpotify(uri: String?)` (tries `SpotifyLink.openURLs(forURI:)` in order through the existing private `open(_:failure:)`). `AppModel.library`. RootView's `.music` case shows `MusicScreen`.

- [ ] **Step 1: Tests (RED)** for `MusicSection` only: `fiveSectionsInOrder` (`[.nowPlaying, .playlists, .liked, .search, .queue]`), `titlesAndSymbolsAreDistinctAndNotEmpty`. Push, confirm failure; implement; commit GREEN; push; confirm success.
- [ ] **Step 2: Model and container (no test).** `SpotifyLibraryModel` loads lazily: the first time a pane appears it loads (`.idle` to `.loading`), shows `failed` with the failure's message and a Try again button, and never loads again on every redraw. A failure goes through `spotify.report`. `MusicScreen`: a top row with the section pills (scrolls if narrow), a trailing device chip ("Playing on iPhone", opens the sheet from Task 8, wired there) and `SpotifyAttribution`; a failure banner for `spotify.problem`; the pane below. `.signedOut`, `.needsReconnect`, `.notConfigured` and `.signingIn` still show the existing state panel instead of the sections.
- [ ] **Step 3: Panes (no test).** `PlaylistsPane`: a vertical list of cover, name, owner, count; tap opens the playlist page. The playlist page has Play and Shuffle buttons (Play sends `.context(uri: playlist.uri, startAtURI: nil)`; Shuffle turns shuffle on first), then the track list when `canListItems` is true (tap plays `.context(uri: playlist.uri, startAtURI: track.uri)`; loads the next page when the last row appears), else the line "Spotify only lets Cabin Dash list tracks in playlists you own. You can still play it." `LikedPane`: the saved tracks, paged; tap plays `SpotifyPlayTarget.window(uris, startingAt: index)`. If the first page fails, the pane says Liked Songs could not be loaded with the reason and hides itself from nothing else. `TrackRow`: 40 pt thumbnail with 4 pt corners, title, subtitle, duration, dimmed when `isPlayable` is false.
- [ ] **Step 4: Commit and push.** Gate: the full run compiles.

### Task 8: Search, Queue, Devices and the no-device recovery

**Files:** Create `CabinDash/Views/Music/SearchPane.swift`, `QueuePane.swift`, `DeviceSheet.swift`. Modify `CabinDash/Model/SpotifyLibraryModel.swift`, `CabinDash/Model/SpotifyModel.swift`, `CabinDash/Views/Music/MusicScreen.swift`.

**Interfaces:**
- Consumes: `SpotifyDevices.autoTarget` (Task 5), `AppModel.typingLocked` (Task 6).
- Produces: `SpotifyModel.play` gains the recovery: on `.noActiveDevice` it fetches `devices()`, and if `autoTarget` returns a device it sends `play(_:deviceID:)` again, otherwise it sets `problem = .noActiveDevice`. `SpotifyLibraryModel`: `searchText`, `search: LoadState<SpotifySearchResults>`, `runSearch()` (waits 400 ms, ignores a result that is no longer the current text), `queue: LoadState<SpotifyQueue>`, `loadQueue()`, `devices: LoadState<[SpotifyDevice]>`, `loadDevices()`, `transfer(to: SpotifyDevice)`, `addToQueue(_ track: SpotifyTrack)` (toast "Added to queue").

- [ ] **Step 1: Search (no test).** `SearchPane`: a text field and results in three groups of at most 10 (Tracks, Albums, Playlists). While `typingLocked` the field is disabled and the pane says "Search is off while you're moving. Passenger mode in Settings turns this lock off." Track tap plays `track.playTarget`; album tap plays `.context(uri: album.uri, startAtURI: nil)`; playlist tap opens the playlist page; each track row has a plus button that adds it to the queue. Empty and failed states have one line each.
- [ ] **Step 2: Queue and Devices (no test).** `QueuePane`: the current track, then "Up next" (read-only; Spotify offers no way to jump); refreshes when the pane appears and after any play command. `DeviceSheet`: lists devices with the active one ticked; tap transfers playback (`transfer(to:play: true)`); an empty list says "Open the Spotify app once, then pull to refresh." The device chip and the no-device banner both open it.
- [ ] **Step 3: Commit and push.** Gate: the full run compiles.

### Task 9: Like the current track

**Files:** Modify `CabinDash/Model/SpotifyLibraryModel.swift`, `CabinDash/Views/Music/NowPlayingScreen.swift`.

**Interfaces:**
- Consumes: `SpotifyEndpoint.contains/save/remove` (Task 2), `NowPlaying.uri` (Task 3).
- Produces: `SpotifyLibraryModel.isLiked(_ uri: String) -> Bool?` (nil while unknown), `refreshLiked(for uri: String)`, `toggleLiked(_ uri: String)` (optimistic, reverts and reports on failure). Likes are kept in memory only, for the tracks seen this session.

- [ ] **Step 1: Implement (no test).** `NowPlayingPane` calls `refreshLiked` when the track URI changes and shows a heart (`heart` / `heart.fill`) beside the transport; it is hidden when the URI is nil or an episode. Tapping toggles through Spotify and nothing is saved by Cabin Dash.
- [ ] **Step 2: Commit and push.**

### Task 10: Attribution, rules and docs

**Files:** Create `scripts/add_spotify_icon.py`, `docs/SPOTIFY-RULES.md`. Modify `CabinDash/Views/Music/SpotifyAttribution.swift`, `scripts/ci/tests/test_ci_scripts.py`, `docs/SPOTIFY-SETUP.md`, `README.md`, `docs/AUDIT.md`, `docs/IOS-LIMITS.md`.

**Interfaces:**
- Produces: `SpotifyAttribution` shows Spotify's icon when the asset `SpotifyIcon` exists in the catalog (`UIImage(named:)`), otherwise keeps the plain word "Spotify" (no look-alike mark); the "Open Spotify" link uses the current track's URI when known. `scripts/add_spotify_icon.py <png>`: copies a PNG at least 21 px square into `CabinDash/Assets.xcassets/SpotifyIcon.imageset/` and writes its `Contents.json`; refuses a missing or non-PNG file.

- [ ] **Step 1: Script tests (RED).** In `test_ci_scripts.py`: `AddSpotifyIconTests` with `installsAPngAndWritesContents` (the imageset holds the PNG and a `Contents.json` naming it) and `rejectsANonPngFile`. Run `python3 -m unittest` locally (Python exists here): confirm they fail, implement, confirm they pass.
- [ ] **Step 2: View (no test).** Add the icon branch to `SpotifyAttribution`. Remove the claim "Cabin Dash can't browse Spotify's library" from every file (`grep -rn "browse Spotify"`).
- [ ] **Step 3: Docs.** `SPOTIFY-RULES.md`: what Cabin Dash follows from Spotify's design guidelines (attribution, "Open Spotify" wording, artwork unaltered and corner radii, like goes to Spotify) and where it knowingly does not, stated plainly: the progress bar can seek (the guidelines want it informational), lists can show more than 20 items, and the official logo is not bundled because it cannot be downloaded from the build environment (run `add_spotify_icon.py` with the icon from Spotify's guidelines page). `SPOTIFY-SETUP.md`: the one-time reconnect and the new permissions. `README.md` status table and Music paragraph, `IOS-LIMITS.md` (audio plays in the Spotify app; no device means no playback), `AUDIT.md` (a "Phase 2" section: what was checked, found and not verified).
- [ ] **Step 4: Commit and push.**

### Task 11: Final checks and handoff

- [ ] **Step 1:** Poll until the final push's run finishes. Read every step. All steps must be `success`; read the "Unit tests on the Mac" count against `scripts/ci/check_tests.py`.
- [ ] **Step 2:** Run the repo's own checks locally: `python3 scripts/ci/check_repo.py`, `python3 scripts/swift_sanity.py`, `python3 -m unittest discover scripts/ci/tests`, `python3 scripts/check_schemes.py`.
- [ ] **Step 3:** Final whole-branch review (executing-plans) against this plan, the spec and the Spotify rules above. Fix Critical and Important findings with tests.
- [ ] **Step 4:** Hand over to the user: what is new, the phone checklist below, what was not verified, and the guideline deviations. Building the IPA (Actions, Unsigned IPA (manual)) and installing it are the user's steps.

**Phone checklist (for the user):** (1) First launch shows "Connect Spotify again"; connect once and accept the new permissions. (2) Now Playing: shuffle, repeat and the heart respond; previous and next dim when Spotify disallows them. (3) Playlists lists yours; open one you made and tap a track; open a Spotify-made one and see the Play-only note. (4) Liked loads, or says why not. (5) Search a song while parked, play it, add one to the queue, see it under Queue. (6) Driving lock: it can only be fully tested in a moving car. As a passenger, with Passenger mode off, go above about 8 km/h and confirm Search turns off; stop for 10 seconds and confirm it comes back; turn Passenger mode on and confirm Search works while moving. (7) Quit Spotify, then tap a track: Cabin Dash starts it on your iPhone, or opens Devices. (8) The Home map, Music widget and mini-player still work.
