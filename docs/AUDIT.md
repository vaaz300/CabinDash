# Audit before the first cloud build

> **Written for the first version.** The CarPlay-style rebuild (home grid, rail, Maps, Now Playing, Spotify) came after this audit, and the feature shell replaced its icon grid after that; see the two sections at the end.

This is what was checked in the existing project before any build was set up, what was changed, and what was left alone on purpose.

**The important sentence (as written before the first build):** every Swift file was read by hand, and no definite compile error was found. That was not evidence the app compiles, because no Swift compiler had ever run on this code.

**What the first cloud runs showed (25 Oct 2026):**

* **Run 1 failed in the "Check the generated project" step.** The cause was two false alarms in my own checker: XcodeGen puts the deployment target on the project rather than the target, and the scheme check only looked in one place. Fixed in commit `2311127`. My test data had made the same wrong assumption, which is why the tests had passed.
* **Run 2 passed every step:** project generation and check, the Mac tests, the simulator build, the simulator tests and their test-count check, and the launch check.
* **Not yet looked at:** the compiler warnings, the exact number of tests executed, and the launch screenshot. They are on the run's summary page and in its downloadable artifact.

## What was in scope

| Area | Covered |
|---|---|
| Swift sources | all 30 files (about 3,500 lines): the 8 `CabinCore` sources plus its `Package.swift`, the 17 app files in `CabinDash/`, and the 4 test files |
| Project definition | `project.yml` (XcodeGen), the generated `Config/Info.plist`, `Config/Signing.xcconfig` |
| Permissions and privacy | location text, background modes, `PrivacyInfo.xcprivacy`, entitlements |
| Resources | `Assets.xcassets` (app icon, accent colour, launch colour) |
| URL schemes | the app catalogue, `LSApplicationQueriesSchemes`, and the app-opening code |
| Tests and scripts | `CabinCore/Tests`, `scripts/` |

## Changes made

The brief asked for the smallest changes that give a working build, so the list is short. None of the first four is a confirmed compile error. Each removes a spot where I could not rule one out by reading.

| File | Change | Why |
|---|---|---|
| `CabinDash/Model/ToastCenter.swift` | added `import Observation` | `@Observable` comes from the Observation module. SwiftUI probably re-exports it, but an explicit import cannot hurt. |
| `CabinDash/Views/RootView.swift` | the two `.task { }` closures now use `self.model` and `self.location` | Inside the view, `model` is also a local `@Bindable` variable. `.task` closures are `@Sendable`, and a local variable should not be captured by one. The environment value should. |
| `CabinDash/Views/SettingsSheet.swift` (now `Views/Settings/SettingsScreen.swift`) | `Task { await self.model.refreshIcons() }` | Same reason, same pattern. |
| `CabinCore/Tests/CabinCoreTests/DriveTests.swift` | two calls to the mutating `trip.ingest(...)` moved out of `#expect(...)` into a `let` first | A mutating call on a `var` inside the `#expect` macro is a place Swift Testing can refuse to compile. |
| `project.yml`, `Config/Signing.xcconfig`, `.gitignore` | signing values moved out of `project.yml` into an xcconfig; personal values go in a git-ignored `Config/Signing.local.xcconfig` | "Keep signing configuration out of the source code." The bundle id is `$(CABIN_BUNDLE_ID)`, and `DEVELOPMENT_TEAM` is empty in the repository. |

Fixed earlier, before this brief (already in the project you have): missing `import Observation` in three model files, task-closure actor isolation (moved into `AppModel.startUp(location:)`), a `self`-before-init in `IconStore`, a `MainActor.assumeIsolated` result, a translucent app icon (Apple rejects icons with transparency), a bug in the scheme-checking script, the dock stretching in landscape, and saved apps failing to decode when a field was missing.

Not changed, deliberately: the design, the features, the deployment target (iOS 17.0), the dependency list (there are none outside Apple's frameworks), and `SWIFT_VERSION` (5.0, which reports most concurrency problems as warnings rather than errors, so a first build is more likely to get as far as the real findings).

## Checked and found consistent

* **Catalogue, URL schemes and Info.plist agree.** `python3 scripts/check_schemes.py` reported: 37 catalogue apps, 30 distinct schemes (iOS allows at most 50), and `Catalog.swift` and `project.yml` match. The CI run repeats this check, and it also compares the *generated* Info.plist.
* **Location permission.** `NSLocationWhenInUseUsageDescription` is present, with plain wording. There is no "Always" key and no background mode, which matches the code (updates stop when the app leaves the screen).
* **Privacy manifest.** `PrivacyInfo.xcprivacy` declares no tracking, no collected data, and one required-reason API: UserDefaults (reason `CA92.1`). A search of the sources for the other required-reason APIs (file timestamps, system uptime, disk space, keyboard mode) found none.
* **Entitlements.** None are needed and none exist: no push, no CarPlay entitlement, no app groups, no background modes.
* **Deployment target.** `project.yml` and `CabinCore/Package.swift` both say iOS 17 (the package also says macOS 14 so `swift test` can run on a Mac). The APIs in use (`@Observable`, the two-parameter `onChange`, `AccessibilityNotification`) need iOS 17.
* **Assets.** The 1024 px app icon has no transparency; `AccentColor` and `LaunchBackground` exist under the names `project.yml` refers to.
* **Tests.** 98 `@Test` functions (at the time of the audit; 184 now), all in `CabinCore` (Foundation only, so they can run without a simulator). There is no app-level test target; the app's logic lives in `CabinCore` for that reason.

## Open risks (documented, not "fixed")

These cannot be settled without a compiler or a phone. Changing code to avoid them would be guessing.

1. **~~Nothing has been compiled.~~ Compiled once, for the simulator only (see above).** Not yet known: how many warnings it produced, and whether it builds for a real device or passes Apple's upload checks. For reference, the places I thought most likely to fail were: SwiftUI view bodies the type checker finds too complex, concurrency isolation in `LocationModel`'s delegate, and Swift Testing macro expansions. When it happens, copy the "App build" block from the run's summary page to Claude.
2. **~~XcodeGen has never run~~ XcodeGen ran, and the generated project passed the check.** The workflow's *Check the generated project* step compares XcodeGen's output with the files on disk (sources, assets, privacy manifest, package link, URL schemes, location text), so a quiet omission turns into a red step.
3. **~~Does the `CabinCore` package scheme include the test target under `xcodebuild test`?~~ The simulator test step and its test-count check passed, so it appears to.** If it had not, the simulator test step fails with "No tests were executed" and the Mac `swift test` step still covers the same 98 tests.
4. **Six URL schemes are best guesses:** SiriusXM, iHeartRadio, TuneIn, SpotHero, ChatGPT and Claude (marked in `Catalog.swift`). A wrong guess means that app is not auto-detected and opens its web or App Store page instead.
5. **App Store ids in the catalogue were not re-verified.** The App Store lookup service cannot be reached from the build environment I used. At runtime the app checks every icon result against the app's name, so a wrong id cannot put the wrong *icon* on a tile. It can, though, make the *fallback* link (used when an app is not installed and has no website) open the wrong App Store page. Look at any app that opens something unexpected.
6. **Reduced-accuracy location is not handled.** If you turn off "Precise Location" for Cabin Dash, iOS gives approximate positions only. The trip tracker rejects readings coarser than 40 m, so speed and distance will not work, and nothing on screen says why. See `docs/IOS-LIMITS.md`.
7. **The layout was reviewed in code only.** No screenshot has been taken of it, and the app is now landscape only.
8. **Workflow actions are pinned to major versions (`@v4`), not to commit hashes.** I could not look up hashes from the build environment. Pinning to hashes is the stricter option if you ever make this repository more than personal. If GitHub starts warning that these versions are outdated, move them to the newer major versions after checking they exist.
9. **The CI helper scripts parse real Xcode output** (log lines, result bundles, the generated project file, simulator listings). They were tested only against hand-written examples of that output. If a format differs, a helper may report something odd; the underlying `xcodebuild` log is always uploaded unedited so nothing is hidden.

## CarPlay-style rebuild (written before it was compiled)

> **Since then:** GitHub's "iOS build" run for commit `c5b2c5c` (26 Oct 2026) passed every step for this code, including the Mac and simulator tests, the test-count check and the launch check. That shows it compiles and its tests pass. It does not show how it looks or behaves on a phone.

Added after the audit above: `HomeLayout`, `Spotify`, `SpotifyAuth` and `RouteGuide` in `CabinCore` (pure logic, 66 new tests), and in the app a `Shell` (ribbon wallpaper, home grid, status rail), `Maps` (map screen, search sheet), `Music` (Now Playing), plus `SpotifyModel`, `SpotifyAuthenticator`, `KeychainStore`, `RouteModel` and `DeviceStatus`. `AppsView`, `DockBar` and `WallpaperView` were removed. The app became landscape only, and `Info.plist` gained a `SpotifyClientID` entry fed from a build setting.

**Checked by hand, with no Swift compiler available** (swift.org, PyPI and npm were all unreachable from the build environment):

* The expected values in the new tests were worked out independently, several with Python (distances, the RFC 7636 PKCE example, base64url).
* New app code was reread for the usual first-build failures: missing imports, `@Sendable` closures capturing the local `@Bindable`, MapKit signatures (the `MapStyle.standard` one was checked against Apple's documentation), and actor isolation.
* The repository's own checks and their tests were run locally: `check_repo.py`, `check_schemes.py`, the CI helper tests.

**Not checked when this was written, and likely to show up on the first run (it compiled; the rest is still true):** compile errors in the new views and models, Swift Testing macro problems in the new tests, and anything about how it looks or behaves. The cloud build's "App build" block is the way to find out.

**Choices worth knowing about:** the Spotify Client ID is a build setting, not source, and is passed in from the `SPOTIFY_CLIENT_ID` repository variable by the unsigned-IPA workflow only. No Spotify secret is used (the sign-in is PKCE, which needs none). The screenshot the launch check saves is now `launch.png` (it was `launch-portrait.png`).

## Feature shell (Phase 1 of the self-contained rebuild)

The app stopped being an icon launcher. Navigation is now a `Router` over a `Feature` enum (`CabinCore/Sources/CabinCore/Feature.swift`), the left rail shows the same dock on every screen, and Settings is a screen instead of a sheet. Home is a Dashboard with Map, Music and Drive widgets. A thin bar for the playing track and one for the next turn follow the driver from screen to screen. The old icon grid survives only as the optional **Other apps** screen, which is off by default.

**Removed:** `AppScreen`, the pinned/built-in tile logic and the recent-apps rail in `HomeLayout`; `HomeGrid.swift` (now `OtherAppsScreen.swift`); `SettingsSheet.swift` (now `Settings/SettingsScreen.swift`). **Added:** `Feature.swift` (with `Dock`, `Router`, `Strips`, `DockMetrics`), `Preferences.showOtherApps`, `FeatureIcon`, `Strips.swift`, `DashboardView`. Folders were regrouped by feature: `Views/Map`, `Views/Drive`, `Views/Settings`, `Views/Dashboard`.

**Tests:** 184 declared (the dock, router, bar and sizing rules; the new preference and its decoding of old saved settings; the slimmer launcher). The SwiftUI views have no automated tests. Their pure rules do. Whether the views compile, and whether the app starts, is shown by the GitHub run for the commit, and only by that run.

**Not verified, and only checkable on a phone:** how the dock, Home widgets and top bars look and fit (especially on a small iPhone); whether the non-interactive map widget behaves; whether the music and route bars cover anything; Spotify and GPS behaviour. `Map(position:interactionModes:)` was used without checking Apple's documentation for it. If the build rejects it, the fallback is to draw the map under a layer that blocks touches.

**Found in the read-through before handing over, and fixed:** with Other apps off (the default) the app still asked Apple's App Store for the icons of the apps on your shelf at every launch. `HomeLayout.iconApps` now returns nothing while the switch is off, and two tests pin that. **Found and left alone at first (fixed in the re-check below):** the Map screen is rebuilt on every dock tap, so coming back to it mid-route left the camera not turning with your heading until you tapped Recenter.

**Found on the first phone screenshots (26 and 27 Oct 2026):** the clock was wider than the dock, the next-turn card covered Apple's "Maps" attribution, and the cellular icon showed full bars (all fixed in `d4b37a7`); then the **Phone tile opened iOS's Call prompt with no number in it** (the bare `tel://` link, which this document's earlier "not tried" note had flagged as a risk; the tile is removed and a test pins that), and the **Home map widget drew no route line** while the Map screen did (the widget built its own map holding only the location dot; both screens now draw the route through one shared `RouteMapContent`). Neither of the last two was visible to a compiler or the tests: the first is iOS behaviour, the second is view code, which has no automated tests. The shared definition is what keeps the two maps from drifting apart again.

**Choices worth knowing about:** every dock tap rebuilds the screen it goes to, so the Other apps screen goes back to its first page when you come back (route and music state are kept in the models and are not lost, and the Map frames itself for the current stage of the route). The Phone and Messages tiles are still only links to the iPhone's own apps.

## Phase 1 re-check (27 Oct 2026)

Before Phase 2, Phase 1 was checked again against the spec's Phase 1 line and the plan, instead of trusting the earlier "done".

**Checked, with the evidence:**

* **Every Phase 1 deliverable exists in code:** the `Feature` enum, `Router` and `Dock` (`Feature.swift`); the fixed dock (`StatusRail`); the Dashboard with Map, Music and Drive widgets (`DashboardView`); Settings as a screen (`SettingsScreen`); the Other apps launcher, off by default (`Preferences.showOtherApps`, `OtherAppsScreen`); the music and route bars (`Strips.swift`); and the dock, router, bar and sizing rules with tests (`FeatureTests`, `OtherAppsSwitchTests`, `HomeLayoutTests`). The spec's call banner is Phase 3, on purpose.
* **The plan's five "Review Focus" failure modes** each have a test or a code path: old saved settings, the Apps screen when the switch goes off, very short screens, Spotify not connected or nothing playing, and Location denied.
* **Global constraints held.** Nothing changed in `project.yml`, `Config/`, the privacy manifest, `Package.swift` or `.github` since the base commit `c5b2c5c`. There are no entitlements, web views or private-API calls, and the only in-app sign-in is Apple's `ASWebAuthenticationSession`. The app is still iOS 17 and landscape only.
* **No leftovers.** The plan's stale-name search prints nothing, the folder paths in the docs match, and no `TODO`, `print`, `try!` or `as!` was found in the app code. The only force-unwrap is `URL(string: "https://apps.apple.com")!` in `AppEntry.swift` (older than Phase 1), a fixed literal that cannot fail.
* **Local scripts and tests.** `swift_sanity.py`, `check_schemes.py`, `check_repo.py` and the 43 CI-helper tests pass, and 184 `@Test` functions are declared.
* **GitHub.** The "iOS build" run for `d99693d` passed all 22 steps: the Mac tests, the check that they really ran, the simulator build, the simulator tests, and the launch check.
* **Compiler warnings, for the first time.** Until now they were only in the job summary, which needs a login. Warnings in our own files are now GitHub annotations as well, and that run reported none. The annotation code was tested on hand-written log lines, not on a real warning, so read "none" with that in mind.

**Found and fixed in this re-check:** coming back to the Map mid-route now frames the camera for the current stage of the route (it used to stop following your heading); the Reset apps text no longer mentions recent apps, which are gone from the screen; an unused import was removed. The Phone tile and the missing route line on the Home map were found on your phone screenshots and fixed just before (see above).

**Also added:** the app icon is now your artwork (`design/icon-source.png`, fitted by `scripts/make_icon.py`), and `check_repo.py` fails a build early if the icon is not 1024 x 1024 or has transparency.

**Not verified, and only a phone can show:** the Settings, Music and Drive screens; the music and next-turn bars on every screen that is not their owner (your screenshots had no Spotify and no bar on screen); the Location-off message; switching Other apps off; the new icon; the Map camera fix; the speed dial; and battery use of the live Home map. The saved "recent apps" list is still written but never shown (dead data, left in place because removing it changes the saved-settings format).

**Not a Phase 1 problem, noted:** GitHub warns that the `checkout` and `upload-artifact` actions target Node.js 20 and are being forced onto Node 24. They run fine. Moving them to newer major versions is housekeeping for when those versions are confirmed.
