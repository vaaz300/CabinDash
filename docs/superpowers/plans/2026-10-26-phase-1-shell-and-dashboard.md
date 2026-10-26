# Phase 1: Shell and Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the icon-grid launcher with a fixed-dock shell (Home, Map, Music, Drive, optional Apps, plus a Settings gear), a live Dashboard, cross-screen music and route strips, and Settings as a screen.

**Architecture:** Navigation becomes a pure `Router` over a `Feature` enum in CabinCore, tested in CI. `AppModel` holds a `Router` instead of an optional screen. The rail draws `Dock.features` instead of recent apps. The old tile grid survives only as the optional "Other apps" screen, off by default. Phone, Messages and Contacts are not in this plan (Phases 3 and 4), so the dock has no entries for them yet.

**Tech Stack:** Swift 5 language mode, SwiftUI, iOS 17+, SwiftPM package `CabinCore` with Swift Testing, XcodeGen, GitHub Actions on macOS. No new packages.

**Spec:** `docs/superpowers/specs/2026-10-26-self-contained-cabin-dash-design.md` (approved with all six defaults on 2026-10-26: D1 Other apps off by default, D2 driving lock on, D3 Spotify controls plus library, D4 skip Apple Music, D5 phone-sensed Vehicle first, D6 order shell, Music, Phone/Contacts, Messages, guidance, Vehicle). Only D1 matters in this phase.

## Global Constraints

* iOS 17.0 deployment target; iPhone only; **landscape only**; `SWIFT_VERSION` stays `"5.0"`.
* Free Apple Account sideload: **no entitlements, no new capabilities, no signing changes.** `Config/Signing.xcconfig` is not touched. No `DEVELOPMENT_TEAM`/`CODE_SIGN_*` in `project.yml`.
* **No new Info.plist keys in this phase.** No new third-party packages. No web views. No private APIs.
* Pure logic goes in `CabinCore` with Swift Testing `@Test`. Declared `@Test` count must never exceed what executes (`scripts/ci/check_tests.py` enforces it).
* App models are `@MainActor @Observable`. Inside `Task {}` in views use `self.model` (or a captured local), not the local `@Bindable`.
* No Swift compiler exists in this environment. Nothing is "passing" until the GitHub Actions run says so. Never claim a build or test result that has not been read from GitHub.
* Every commit message ends with these two lines:
  `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01BFMMCGikHkv4vMTFkLsjXY`
* Push with `git push origin HEAD:main` from `/home/claude/cabindash`. Docs-only pushes do not trigger the build; code pushes do.
* **Reading CI results:** `curl -sS "https://api.github.com/repos/vaaz300/CabinDash/actions/runs?per_page=5"` works without a token and gives each run's `head_sha`, `status` and `conclusion`. `.../actions/runs/<id>/jobs` lists step results. Failure logs need a login, so on a red step ask the user to paste the "App build" block.

## Review Focus

Failure modes the spec implies that no UI test can catch here. Each is pinned by a test where the logic is pure, otherwise by the phone checklist in Task 6.

1. **Old saved preferences** (no `showOtherApps` key, old `recent` ids such as `"maps"`) must load without losing settings. Pinned: Task 2 tests.
2. **Other apps switched off while the Apps screen is open** must land on Home, not a blank screen. Pinned: Task 1 router tests.
3. **Very short screens** (small phones, split display zoom) must not push dock buttons off the rail. Pinned: Task 1 `DockMetrics` clamp tests.
4. **Spotify not connected, signed out, or nothing playing** must never show a mini-bar or an empty Music widget that crashes on `nil`. Pinned: Task 1 strip tests (`musicActive: false`), Task 5 state handling, phone checklist.
5. **Location denied** must show "Location is off" on the Drive widget, not a confident 0 km/h. Pinned: Task 5 and phone checklist.

## File Structure

| File | Responsibility |
|---|---|
| `CabinCore/Sources/CabinCore/Feature.swift` (new) | `Feature`, `Dock`, `Router`, `Strip`/`Strips`, `DockMetrics`: all navigation rules |
| `CabinCore/Sources/CabinCore/HomeLayout.swift` (slimmed) | Only the Other apps launcher: system links, shelf apps, Add Apps, paging |
| `CabinCore/Sources/CabinCore/Preferences.swift` (edit) | New `showOtherApps` flag |
| `CabinDash/Model/AppModel.swift` (edit) | Holds the `Router`; `go(_:)`; drops `screen`, `settingsPresented` |
| `CabinDash/Views/RootView.swift` (edit) | Draws `router.current`, the rail, strips, toasts |
| `CabinDash/Views/Shell/StatusRail.swift` (edit) | Compact status header, `Dock` buttons, Settings gear |
| `CabinDash/Views/Shell/FeatureIcon.swift` (new) | One icon per `Feature` (wraps `SymbolTile`) |
| `CabinDash/Views/Shell/Strips.swift` (new) | `StripStack`, `MiniPlayerStrip`, `RouteBannerStrip` |
| `CabinDash/Views/Shell/OtherAppsScreen.swift` (renamed from `HomeGrid.swift`) | The tile grid, now secondary |
| `CabinDash/Views/Dashboard/DashboardView.swift` (new) | Home screen with Map, Music and Drive widgets |
| `CabinDash/Views/Settings/SettingsScreen.swift` (renamed from `SettingsSheet.swift`) | Settings as a screen |

Tests: `CabinCore/Tests/CabinCoreTests/FeatureTests.swift` (new), `PreferencesTests.swift` (new), `HomeLayoutTests.swift` (rewritten).

---

### Task 0: Base build (gate, no code)

**Status: done, 2026-10-26.** GitHub's public API shows run #3 "iOS build" on `c5b2c5c` with every step green, including "Unit tests on the Mac", "Confirm the Mac tests really ran", the simulator build and tests, and "Launch the app on the simulator". "Unsigned IPA (manual)" run #2 on the same commit also succeeded. That proves the code compiles and the 164 declared tests ran. It does not prove anything works on a phone.

---

### Task 1: Navigation rules in CabinCore

**Files:**
- Create: `CabinCore/Sources/CabinCore/Feature.swift`
- Test: `CabinCore/Tests/CabinCoreTests/FeatureTests.swift`

**Interfaces:**
- Produces:
  - `public enum Feature: String, CaseIterable, Codable, Hashable, Sendable { case dashboard, map, music, drive, settings, apps }` with `public var title: String` ("Home", "Map", "Music", "Drive", "Settings", "Apps"), `public var symbol: String` ("house.fill", "map.fill", "music.note", "speedometer", "gearshape.fill", "square.grid.2x2.fill"), `public var tone: HomeTone` (.graphite, .green, .red, .orange, .graphite, .blue). `HomeTone` already exists in `HomeLayout.swift`.
  - `public enum Dock { static func features(showOtherApps: Bool) -> [Feature]; static let footer: Feature; static func isAvailable(_ feature: Feature, showOtherApps: Bool) -> Bool }`
  - `public struct Router: Equatable, Sendable { public private(set) var current: Feature; public init(current: Feature = .dashboard); public mutating func go(_ feature: Feature, showOtherApps: Bool); public mutating func reconcile(showOtherApps: Bool) }`
  - `public enum Strip: Hashable, Sendable { case route, music }` and `public enum Strips { static func visible(on feature: Feature, musicActive: Bool, routeGuiding: Bool) -> [Strip] }`
  - `public enum DockMetrics { static let minIcon = 30.0; static let maxIcon = 52.0; static let gapRatio = 0.2; static func iconSize(availableHeight: Double, itemCount: Int) -> Double; static func gap(forIconSize size: Double) -> Double }`

- [ ] **Step 1: Write the failing tests** in `FeatureTests.swift` (`import Testing`, `@testable import CabinCore`), three suites:

  `FeatureTests`
  * `everyFeatureHasADistinctTitleAndSymbol`: titles and symbols are non-empty and each set's count equals `Feature.allCases.count`.
  * `dockHoldsHomeMapMusicDrive`: `Dock.features(showOtherApps: false) == [.dashboard, .map, .music, .drive]`.
  * `appsJoinsTheDockLastWhenOtherAppsIsOn`: `Dock.features(showOtherApps: true) == [.dashboard, .map, .music, .drive, .apps]`.
  * `settingsIsTheFooterAndNeverInTheStack`: `Dock.footer == .settings` and neither `Dock.features` result contains `.settings`.
  * `appsNeedsTheSwitch`: `Dock.isAvailable(.apps, showOtherApps: false) == false`, `true` with the switch; `.map` is available either way.
  * `routerStartsOnTheDashboard`: `Router().current == .dashboard`.
  * `routerMovesToAvailableFeatures`: `go(.music, showOtherApps: false)` makes `current == .music`.
  * `routerIgnoresAppsWhileOtherAppsIsOff`: from `Router(current: .map)`, `go(.apps, showOtherApps: false)` leaves `current == .map`.
  * `routerLeavesAppsWhenTheSwitchGoesOff`: `Router(current: .apps)` after `reconcile(showOtherApps: false)` has `current == .dashboard`; after `reconcile(showOtherApps: true)` stays `.apps`.
  * `reconcileLeavesOtherFeaturesAlone`: `Router(current: .drive)` stays `.drive` after `reconcile(showOtherApps: false)`.

  `StripTests` (`Strips.visible(on:musicActive:routeGuiding:)`)
  * `noStripsOnTheDashboard`: `.dashboard` with both flags true returns `[]`.
  * `routeBannerHidesOnTheMapOnly`: with `routeGuiding: true, musicActive: false`, `.map` returns `[]` and `.music`, `.drive`, `.settings`, `.apps` each return `[.route]`.
  * `musicStripHidesOnMusicOnly`: with `musicActive: true, routeGuiding: false`, `.music` returns `[]` and `.map`, `.drive`, `.settings`, `.apps` each return `[.music]`.
  * `routeComesBeforeMusic`: `.drive` with both true returns `[.route, .music]`.
  * `nothingShowsWhenNothingIsActive`: every `Feature` returns `[]` when both flags are false.

  `DockMetricsTests`
  * `sizeFillsTheHeight`: `abs(iconSize(availableHeight: 410, itemCount: 7) - 50) < 0.001` (410 / (7 + 0.2 × 6) = 50).
  * `sizeClampsToTheMaximum`: `iconSize(availableHeight: 1000, itemCount: 5) == 52`.
  * `sizeClampsToTheMinimumOnShortScreens`: `iconSize(availableHeight: 120, itemCount: 7) == 30` and `iconSize(availableHeight: -5, itemCount: 5) == 30`.
  * `noItemsGivesTheMaximum`: `iconSize(availableHeight: 300, itemCount: 0) == 52`.
  * `gapIsAFifthOfTheIcon`: `abs(gap(forIconSize: 40) - 8) < 0.001`.

- [ ] **Step 2: Cannot run locally** (no Swift toolchain). State that in the commit body. The expected CI failure before Step 3 is "cannot find 'Feature' in scope".

- [ ] **Step 3: Implement `Feature.swift`** with the signatures above. Rules to encode: `Dock.features` is `[.dashboard, .map, .music, .drive]` plus `.apps` only when the switch is on; `Dock.isAvailable` is false only for `.apps` without the switch; `Router.go` ignores unavailable features; `reconcile` moves `.apps` to `.dashboard` when unavailable and does nothing otherwise; `Strips.visible` hides `.route` on `.map` and `.dashboard`, hides `.music` on `.music` and `.dashboard`, returns `.route` before `.music`; `DockMetrics.iconSize` is `availableHeight / (n + gapRatio × (n − 1))` clamped to `[minIcon, maxIcon]`, `maxIcon` when `itemCount <= 0`, `minIcon` when `availableHeight <= 0`.

- [ ] **Step 4: Local check:** `python3 /home/claude/cabindash/scripts/swift_sanity.py` reports no bracket problems; `grep -c '@Test' CabinCore/Tests/CabinCoreTests/FeatureTests.swift` prints 20.

- [ ] **Step 5: Commit** `Add the Feature router, dock rules, strip rules and dock sizing to CabinCore`.

---

### Task 2: The Other apps switch in Preferences

**Files:**
- Modify: `CabinCore/Sources/CabinCore/Preferences.swift` (struct `Preferences`, its `init`, `CodingKeys`, `init(from:)`)
- Test: `CabinCore/Tests/CabinCoreTests/PreferencesTests.swift` (new)

**Interfaces:**
- Produces: `public var showOtherApps: Bool` on `Preferences`, default `false`, initialiser parameter `showOtherApps: Bool = false` (added after `keepAwake`), decoded with `decodeIfPresent`.

- [ ] **Step 1: Write the failing tests** in `PreferencesTests.swift`:
  * `otherAppsIsOffByDefault`: `Preferences().showOtherApps == false`.
  * `savesWithoutTheKeyDecodeAsOff`: decoding `Data("{}".utf8)` gives `showOtherApps == false` and the default `units`.
  * `theSwitchSurvivesASaveAndLoad`: encode then decode `Preferences(showOtherApps: true)`; result equals the original.
  * `resettingAppsKeepsTheSwitch`: `var p = Preferences(showOtherApps: true); p.resetApps()` leaves `p.showOtherApps == true`.
  * `oldScreenIdsInRecentsAreIgnoredByTheShelf`: with `apps = [Catalog.entry(id: "waze")].compactMap { $0 }`, `Shelf.recents(apps, ids: ["maps", "now-playing", "waze"]).map(\.id) == ["waze"]`.

- [ ] **Step 2: Implement.** Add the field, parameter, coding key and tolerant decode. `resetApps()` must not touch it.

- [ ] **Step 3: Local check:** `swift_sanity.py` clean; `grep -rhoE '^\s*@Test\b' CabinCore/Tests | wc -l` prints 189 (164 + 20 + 5).

- [ ] **Step 4: Commit** `Add the Other apps switch to saved preferences`.

- [ ] **Step 5: Checkpoint A: push** and poll GitHub until the new "iOS build" run finishes. Expected: every step green and "Confirm the Mac tests really ran" green. If a step is red, stop and fix before Task 3 (these two tasks only add files, so a red run here is a typo in them).

---

### Task 3: Switch the app to the feature shell

One task because removing `AppScreen` breaks every file that mentions it at once; the app must compile again before it is pushed.

**Files:**
- Modify: `CabinCore/Sources/CabinCore/HomeLayout.swift`, `CabinCore/Tests/CabinCoreTests/HomeLayoutTests.swift`
- Modify: `CabinDash/Model/AppModel.swift`, `CabinDash/Views/RootView.swift`, `CabinDash/Views/Shell/StatusRail.swift`, `CabinDash/Views/Maps/MapScreen.swift:189`
- Create: `CabinDash/Views/Shell/FeatureIcon.swift`, `CabinDash/Views/Dashboard/DashboardView.swift`
- Rename: `Views/Shell/HomeGrid.swift` → `Views/Shell/OtherAppsScreen.swift`; `Views/SettingsSheet.swift` → `Views/Settings/SettingsScreen.swift` (use `git mv`)

**Interfaces:**
- Consumes: Task 1 (`Feature`, `Dock`, `Router`, `DockMetrics`) and Task 2 (`prefs.showOtherApps`).
- Produces:
  - `HomeLayout`: `static let perPage = 8`, `static let systemLinks: [HomeItem]` (ids `"phone"` → `tel://`, `"messages"` → `sms://`), `static let replacedByFeatures: Set<String> = ["apple-maps"]`, `static let addApps`, `static func tile(for:)`, `static func items(shelf:) -> [HomeItem]` (system links, then shelf apps in shelf order minus `replacedByFeatures`, then Add Apps last), `static func pages(_:perPage:)` unchanged. `HomeItem.Kind` becomes `.url(URL)`, `.addApps`, `.app(AppEntry)`. Delete `AppScreen`, `isDockable`, `screen`, `pinned`, `dockDefaults`, `builtIn`, `dock(...)`.
  - `AppModel`: `private(set) var router = Router()`, `func go(_ feature: Feature)` (light haptic, then `router.go(feature, showOtherApps: prefs.showOtherApps)`), `func reconcileRouter()`. Removed: `screen`, `show(_:)`, `settingsPresented`. `open(_ item: HomeItem)` handles only `.url`, `.addApps`, `.app`. `iconTargets` is just `shelf`.
  - `struct FeatureIcon: View { let feature: Feature; let size: CGFloat }` wrapping `SymbolTile(symbol: feature.symbol, tone: feature.tone, size: size)`.
  - `struct OtherAppsScreen: View`, `struct SettingsScreen: View`, `struct DashboardView: View`, all environment-driven like the screens they replace.

- [ ] **Step 1: Rewrite `HomeLayoutTests.swift` first** (it will fail to compile against the old `HomeLayout`, which is the failing state):
  * `systemLinksComeFirstThenAddApps`: `items(shelf: []).map(\.id) == ["phone", "messages", "add-apps"]`.
  * `shelfAppsFollowTheSystemLinksInShelfOrder`: with shelf ids `["waze", "spotify"]` the ids are `["phone", "messages", "waze", "spotify", "add-apps"]`.
  * `appleMapsAppGetsNoTile`: `["apple-maps", "waze"]` yields `waze` and not `apple-maps`.
  * `addAppsIsAlwaysLast`, `noTileAppearsTwice`: as the current tests, over `Catalog.all`.
  * `phoneAndMessagesAreSystemLinks`: schemes `tel` and `sms`, read from `HomeLayout.systemLinks`.
  * `pagesHoldEightTiles`, `exactlyFullPageMakesOnePage`: keep the current bodies, building items with `kind: .addApps`.
  Delete the dock, `builtIn`, `screenIdsMatchTileIds` and artwork tests; their subjects no longer exist.

- [ ] **Step 2: Slim `HomeLayout.swift`** to the interface above.

- [ ] **Step 3: Edit `AppModel.swift`** per Interfaces. `navigate(to place:)`'s "Settings" toast action calls `self?.go(.settings)`. `MapScreen.swift:189` becomes `model.go(.settings)`.

- [ ] **Step 4: Rail.** In `StatusRail.swift`: header height 84 with 10 pt top padding, no footer Home button. `count = Dock.features(...).count + 1` (the gear). `available = proxy.size.height − headerHeight − 24`. `size = DockMetrics.iconSize(availableHeight: available, itemCount: count)`, `gap = DockMetrics.gap(forIconSize: size)`. Stack `Dock.features(showOtherApps: model.prefs.showOtherApps)` as `FeatureButton`s, a `Spacer`, then the gear (`Dock.footer`). The selected feature gets the existing white capsule. Tapping calls `model.go(feature)`. Accessibility label is `feature.title`. Delete `HomeButton` and the recent-apps logic. Keep `StatusHeader` and `BatteryGlyph` as they are.

- [ ] **Step 5: Root.** In `RootView.swift`, render `screenView(model.router.current)` (switch over every `Feature`: `.dashboard` → `DashboardView()`, `.map` → `MapScreen()`, `.music` → `NowPlayingScreen()`, `.drive` → `DriveView(landscape: true)` with the existing left padding, `.settings` → `SettingsScreen()`, `.apps` → `OtherAppsScreen()` with `railReserve` leading and `edge` trailing padding). Remove the settings sheet and the kept-alive grid. Replace the `model.screen` change handler with `model.router.current` (`spotify.setFast(current == .music)`), and add `.onChange(of: model.prefs.showOtherApps) { model.reconcileRouter() }`.

- [ ] **Step 6: Screens.** `OtherAppsScreen` is `HomeGrid` renamed, using the new `HomeLayout.items`. `SettingsScreen` is the sheet's `Form` without the `NavigationStack`'s Done button, with `scrollContentBackground(.hidden)` over a material, `railReserve`/`edge` padding, and these changes: a new section "Other apps" with `Toggle("Show Other apps in the dock", isOn: $model.prefs.showOtherApps)` and footer "Adds an Apps button that lists apps installed on this iPhone. Opening one leaves Cabin Dash."; the existing "Apps" section (detect, add, refresh, reset) appears only when `showOtherApps` is true; the About footer reads "Cabin Dash is not CarPlay. It's a self-contained driving app that runs on the iPhone's own screen, so it works in any car. Music is controlled through Spotify, which keeps playing in its own app." `PickerSheet` is still presented as a sheet from the Apps section.
  `DashboardView` for now is a plain row of three large tiles (Map, Music, Drive: `FeatureIcon` plus title, each calling `model.go`). Task 5 replaces its body.

- [ ] **Step 7: Verify nothing stale is left.** From the repo root:
  `grep -rnE "AppScreen|settingsPresented|model\.screen|model\.show\(|HomeLayout\.(dock|builtIn|pinned)|SettingsSheet|HomeGrid" CabinDash CabinCore/Sources CabinCore/Tests`
  Expected: no output. Then `python3 scripts/swift_sanity.py`, `python3 scripts/check_schemes.py`, `python3 scripts/ci/check_repo.py` and `python3 scripts/ci/tests/test_ci_scripts.py` all exit 0.

- [ ] **Step 8: Commit** `Replace the icon grid with the feature shell: fixed dock, Settings screen, optional Other apps`.

- [ ] **Step 9: Checkpoint B: push**, then poll GitHub. Expected: the whole "iOS build" run is green, including the launch check. The run's `launch.png` artifact is not readable from here. On red: fix before Task 4.

---

### Task 4: Music and route strips

**Files:**
- Create: `CabinDash/Views/Shell/Strips.swift`
- Modify: `CabinDash/Views/RootView.swift`

**Interfaces:**
- Consumes: `Strips.visible` (Task 1); `SpotifyModel.nowPlaying`, `.phase`, `.togglePlayPause()`; `RouteModel.phase`, `.currentStep`, `.metersToNext`, `.remainingSeconds`; `RouteFormat.maneuverSymbol(_:)`, `.maneuverDistance(meters:units:)`, `.travelTime(seconds:)`.
- Produces: `struct StripStack: View` (reads `AppModel`; shows the strips for `router.current`), `struct MiniPlayerStrip: View`, `struct RouteBannerStrip: View`.

- [ ] **Step 1:** `StripStack` computes `Strips.visible(on: model.router.current, musicActive: spotify.phase == .signedIn && spotify.nowPlaying != nil, routeGuiding: model.route.phase == .guiding)` and stacks the results in order, 8 pt apart, each at most 380 pt wide. `RootView` overlays it top-trailing, clear of the rail (`railReserve` leading, `edge` trailing and top), with a 0.2 s opacity transition.
- [ ] **Step 2:** `MiniPlayerStrip`: 36 pt artwork (`AsyncImage`), title and artist on two lines, one play/pause button calling `Task { await spotify.togglePlayPause() }` through a captured local. Tapping the rest calls `model.go(.music)`.
- [ ] **Step 3:** `RouteBannerStrip`: manoeuvre symbol, distance to the next instruction, the instruction text, and the remaining travel time. Tapping calls `model.go(.map)`. If `currentStep` is nil it shows nothing.
- [ ] **Step 4:** Local check: `swift_sanity.py` clean; the grep from Task 3 Step 7 is still empty. Commit `Show the playing track and the next turn on every screen that does not own them`.

---

### Task 5: Dashboard widgets

**Files:**
- Modify: `CabinDash/Views/Dashboard/DashboardView.swift`

**Interfaces:**
- Consumes: `AppModel.route`, `.spotify`, `.prefs.units`; `LocationModel.speed`, `.trip`, `.access`, `.hasFix`; `DriveFormat.distance(meters:units:)`, `.duration(seconds:)`; `Units.speed(fromMetersPerSecond:)`.
- Produces: `DashboardView` laid out as a large Map widget (about 58% of the width) beside a column of the Music and Drive widgets, 12 pt apart. Each widget is a button that calls `model.go(.map)`, `.music` or `.drive`.

- [ ] **Step 1: Map widget.** A non-interactive MapKit map following the user (`Map(position:interactionModes:)` with an empty set, `.userLocation(followsHeading: false, fallback: .automatic)`, traffic on, controls hidden, same style call as `MapScreen`) clipped to a 24 pt rounded rectangle. Over it: while `route.phase == .guiding`, a card with the manoeuvre symbol, distance, instruction and remaining time; otherwise a "Where to?" capsule.
- [ ] **Step 2: Music widget.** With `phase == .signedIn` and a track: artwork, title, artist, previous/play-pause/next buttons. Every other case is a single line: `.notConfigured` "Spotify isn't set up", `.signedOut` "Connect Spotify", `.signingIn` "Connecting…", signed in with no track "Nothing playing". Never force-unwrap `nowPlaying`.
- [ ] **Step 3: Drive widget.** Speed as a large number with `units.speedLabel`, then trip distance and duration. If `location.access == .denied` show "Location is off" instead of a number; if there is no fix yet show "Finding GPS…".
- [ ] **Step 4:** Local check as in Task 4. Commit `Add the live Dashboard widgets`.

---

### Task 6: Folders, docs, final checks and handoff

**Files:**
- Move (with `git mv`): `Views/Maps/*` → `Views/Map/`, `Views/Music/*` stays, `Views/DriveView.swift` and `Views/GaugeView.swift` → `Views/Drive/`. Folder moves only; no code changes.
- Modify: `README.md` ("How the app works", "Files", test count), `docs/IOS-LIMITS.md` (sections 6, 6a, 6b), `docs/AUDIT.md` (what changed and what is still unverified), `docs/SPOTIFY-SETUP.md` (step 7 says "tap the Now Playing tile": it is now the Music button in the dock).

- [ ] **Step 1:** Do the folder moves. Run `grep -rn "Views/Maps" . --include=*.md --include=*.yml --include=*.py` and fix any path that is now wrong.
- [ ] **Step 2:** Update the docs. State plainly: the launcher is optional and off; Phone and Messages are not built-in screens yet; nothing here has run on a phone. The README test count is the output of `grep -rhoE '^\s*@Test\b' CabinCore/Tests | wc -l`.
- [ ] **Step 3:** Run all local checks: `swift_sanity.py`, `check_schemes.py`, `ci/check_repo.py`, `ci/tests/test_ci_scripts.py`, and the stale-name grep from Task 3. All must be clean.
- [ ] **Step 4:** Commit `Tidy folders and update the docs for the feature shell`. **Checkpoint C: push** and poll until the "iOS build" run is complete. Report the real result.
- [ ] **Step 5:** On green, tell the user to run **Actions → Unsigned IPA (manual) → Run workflow**, install with iLoader, and walk this phone checklist. Each line is something a build cannot prove:
  1. Opens on Home (Dashboard). The dock shows Home, Map, Music, Drive and a gear, with nothing cut off.
  2. Each dock button opens its screen and the selected one is marked.
  3. Dashboard Map widget shows your position; tapping it opens Map. Plan a route and start guiding: the widget shows the next turn.
  4. Play something in Spotify: the Music widget shows it. Go to Drive: the mini-bar appears at the top right, and its button pauses.
  5. While guiding, open Music: the route banner appears; tapping it returns to Map.
  6. Deny Location in iOS Settings: the Drive widget says "Location is off".
  7. Settings opens as a screen. Turn on "Show Other apps in the dock": an Apps button appears. Open Apps, then turn the switch off from Settings and confirm you land on Home.
  8. Strips do not cover anything important on Map, Drive or Settings. If they do, say which screen.

---

## Self-review (run 2026-10-26)

* **Spec coverage, Phase 1 line:** `Feature` enum, router, fixed dock, Dashboard with live widgets, Settings as a screen, launcher demoted per D1, mini-bar and route banner, CabinCore dock/router tests: Tasks 1, 3, 4, 5. The spec's "call banner" is Phase 3 and is deliberately absent. The spec's folder layout is partly done (Task 6); the full `Features/` tree is reached as later phases add features.
* **Types:** `Feature`, `Dock`, `Router`, `Strips`, `DockMetrics` names and signatures match across Tasks 1, 3, 4 and 5. `showOtherApps` is the same name in Tasks 2, 3 and 6.
* **Counts:** 164 current tests, plus 20 (Task 1), plus 5 (Task 2) is 189. Task 3 removes the old `HomeLayoutTests` (15) and adds 8, so the final count is 182. Task 6 Step 2 recomputes it with the grep rather than trusting this arithmetic.
* **Unknowns:** `Map(position:interactionModes:)` is the one MapKit signature used here that is not already in the code base; I believe it exists (iOS 17) but have not checked it. If CI rejects it, fall back to an overlay that blocks touches over `Map(position:)`.
