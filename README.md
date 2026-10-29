# Cabin Dash

A self-contained driving screen for the iPhone, styled after CarPlay. It draws its own screens on the phone's display, so it works in a car with no CarPlay and no Wi-Fi hotspot. Put the phone in a mount, plug it in, and open it. Landscape only.

A frosted dock runs down the left edge and stays put on every screen: the time, connection and battery, then **Home, Map, Music, Drive**, and a gear for **Settings**.

- **Home.** Three live widgets: a map that follows you (with the next turn while you navigate), what Spotify is playing with previous, play/pause and next, and your speed with the trip so far. Tap a widget to open its full screen.
- **Map.** A full-screen Apple Maps view with traffic. Search a place or tap Home or Work, see the route, and follow it with turn-by-turn cards. **Open in Google Maps** (or Waze or Apple Maps, your choice in Settings) hands the trip to that app for the real navigation.
- **Music.** A small Spotify client: what is playing with previous, play/pause, next, seek, shuffle and repeat, Spotify's like button, your playlists and Liked Songs, search, the queue, and a device picker. Spotify's app on the phone plays the sound; Cabin Dash plays and steers it through Spotify's iOS SDK, and opens it for a moment when it is asleep. Search is switched off while the car is moving (Passenger mode in Settings lifts that). Needs a Spotify Premium account and a one-time setup: `docs/SPOTIFY-SETUP.md`. Spotify's rules and where Cabin Dash falls short of them: `docs/SPOTIFY-RULES.md`.
- **Drive.** Live speed dial, heading, trip distance, trip time and average speed from the iPhone's GPS.
- **Settings.** Units, directions app, Spotify, theme and wallpaper, saved places.
- **Other apps (optional, off by default).** Turn on **Show Other apps in the dock** in Settings and an Apps button appears. It lists the apps found on your iPhone, with each app's App Store icon; tapping one leaves Cabin Dash and opens it. iOS does not allow another app's screen inside Cabin Dash.

The track that is playing and the next turn also show as thin bars at the top right of every screen that does not already show them.

**Not built yet:** Phone, Messages and Contacts as screens of their own (the Phone and Messages tiles on the Other apps screen hand off to the iPhone's own apps), spoken turn-by-turn directions, and car data. Spotify has no Browse tab or artist pages here. The design and the order they will be built in are in `docs/superpowers/specs/2026-10-26-self-contained-cabin-dash-design.md`; Phase 1 (the shell and Home) and Phase 2 (Music) are built; Phase 2's plan is `docs/superpowers/plans/2026-10-27-phase-2-music-library.md`.

This guide is written for **Windows, with no Mac**. A free GitHub Actions "cloud Mac" does the building.

## Versions

Cabin Dash is in beta. Every IPA built by the **Unsigned IPA (manual)** workflow is a beta numbered from that workflow's
run: run 1 was **Beta 0.1**, run 21 was **Beta 2.1**, and the next run (22) makes **Beta 2.2**. The build number is the
run number, and a run that fails still uses its number.

* **Where to see it:** Settings > About ("Beta 2.2 (build 22)"), the IPA's file name (`CabinDash-beta-2.2.ipa`, in the
  artifact **cabindash-beta-2.2**), and the run's summary on GitHub. Builds made in Xcode or on the simulator say
  "Development build".
* **Kept for good:** every IPA from Beta 2.2 on is also published under **Code > Releases**: a pre-release tagged
  `beta-2.2` (a full release is tagged `v1.0`) with the `.ipa` attached and what changed as its notes. Artifacts expire
  after 7 days; releases stay until you delete them. This repository is public, so its releases are too, like the code;
  the IPA is unsigned and holds no secrets (the Spotify Client ID is a public identifier).
* **What changed in each:** [CHANGELOG.md](CHANGELOG.md), from Beta 0.1 on. Its "Next beta" section is what the next IPA
  will contain and becomes that release's notes; after the run it is renamed after the beta it became. Betas 0.1 to 2.1 were numbered afterwards
  from their runs; inside the app they say "1.0 (1)".
* **A full release:** when you are happy, run **Actions > Unsigned IPA (manual) > Run workflow** and type the release's
  version (for example 1.0) into **release_version**. That build says "1.0 (build N)". Leave the box empty for a beta.
* **How:** `scripts/ci/app_version.py` turns the run number into the version and tag, and `scripts/ci/release_notes.py`
  takes the notes from the changelog (both tested with the other script tests); the workflow passes the version to Xcode
  and publishes the release with GitHub's `gh` tool; `AppVersion` in CabinCore words it for Settings (unit tests).

## Where things stand

| | Status |
|---|---|
| Swift code compiles | **Read the latest "iOS build" run in the Actions tab.** Green means the app and its tests compiled on GitHub's macOS runner (Xcode 26.5). This file cannot say it for you, because it can be out of date the moment a new push lands. |
| Unit tests | 378 `@Test` functions are declared in `CabinCore/Tests`. The build's test-count step fails the run if fewer than the declared number executed. |
| App starts | The launch step checks the app is still running 12 seconds after launch on a simulator. |
| Helper scripts used by the build | Tested on sample data, and they run on every build. |
| URL-scheme list matches the app catalogue | Checked by script on every build (37 apps, 30 schemes). |
| App installed on an iPhone | **Yes.** Phase 1 was installed with iLoader and your screenshots show it running: the dock, Home with its three widgets and a route card, the Map screen following a route, and the Other apps screen. **Not yet seen on a phone:** the Settings, Music and Drive screens, the bars on top, the Location-off state, the new app icon, and any of it while driving. |
| Look matches CarPlay | Seen on a phone in your screenshots. It is being adjusted from your feedback (so far the clock, the route card, the speed dial and the Phone tile). Send another screenshot and it will be adjusted again. |
| Spotify, Map and Home widgets | The Map and Home widgets were seen working on a phone with a planned route, but not while driving. **Spotify sign-in and the Home music widget were confirmed on your phone (27 Oct 2026).** The Phase 2 Music screens (Playlists, Liked, Search, Queue, devices, the heart, the driving lock) compile and their parsing and rules have unit tests, but none of them has talked to Spotify yet. After installing the new build, tap **Connect Spotify again** once (`docs/SPOTIFY-SETUP.md`). |

Nothing in this repository claims a build or test passed unless the cloud build says so. A green simulator build does not mean the app works on a real iPhone: signing, real GPS, and detection of your real apps are still untested.

## Part 1. Put the project on GitHub

You do not need a Mac, Xcode, or the command line.

1. Create a free account at github.com, if you do not have one.
2. **Decide public or private before you upload.** This changes what the cloud build costs; read "Before the first run: cost" below. For this project there are no secrets in the files, so public is safe. Anyone could read the source code.
3. Unzip `CabinDash-iOS.zip` (right-click > **Extract All**). Open the folder it makes. You should see `project.yml`, `README.md`, and folders named `CabinCore`, `CabinDash`, `Config`, `docs`, `scripts`, and `.github`. **That folder's contents are what you upload.**

**Option A (recommended): GitHub Desktop.** Free, from desktop.github.com.

1. Install it and sign in.
2. **File > Add local repository** and choose the folder from step 3. It says it is not a repository yet; click **create a repository**, keep the defaults, **Create repository**.
3. Type a summary such as `First upload` and click **Commit to main**.
4. Click **Publish repository**. Choose the name, and tick or untick **Keep this code private**.

**Option B: the website only.**

1. github.com > **New repository**. Name it (say `cabin-dash`), choose Public or Private, tick nothing else, **Create repository**.
2. Click **uploading an existing file**.
3. Open the unzipped folder, press Ctrl+A to select **everything inside it**, and drag it into the browser window. Dragging the folder itself puts everything one level too deep and the build will stop with a message saying so.
4. Scroll down, click **Commit changes**.

Check it worked: on the repository's front page you should see `project.yml` straight away, and `.github/workflows` should open to show three files. If `.github` is missing, use Option A. The repository's main branch must be called `main` (GitHub's default).

## Before the first run: cost

The cloud build uses a **macOS** machine from GitHub. These are the facts as I found them in GitHub's documentation; confirm on your own Billing page before running.

* **Public repository:** standard GitHub-hosted runners, including macOS, are free.
* **Private repository:** your plan's included minutes apply (2,000 a month on the Free plan, 3,000 on Pro). macOS minutes cost more than Linux ones: GitHub lists **US$0.062 per minute** for a standard macOS runner. macOS has also historically used up the free allowance ten times faster than Linux; I could not confirm today's multiplier, so assume it still applies. At that rate 2,000 free minutes would be roughly 200 macOS minutes a month.
* **How long is a run?** I have not measured it. For planning, assume 10 to 20 minutes for a run that downloads and compiles everything, which would be about US$0.62 to US$1.24 if billed.
* **Charges past the free allowance** can happen only if the account has a payment method and its spending limit allows it. If you have not added a card, GitHub has nothing to charge, as I understand it. If you have, set a budget: **Settings > Billing and licensing > Budgets and alerts > New budget**, choose **Actions**, set the amount, and tick **Stop usage when budget limit is reached**. Whether GitHub accepts a budget of zero I could not confirm; if it will not, set the smallest amount it allows. Menu names change, so search GitHub's docs for "Actions budget" if these have moved.
* **Artifacts** (the downloadable logs) count against storage: 500 MB on the Free plan. This build keeps them for 14 days.
* **Already built in to limit cost:** a time limit on every job (45 minutes), a new push cancels the run before it, changes that only touch `.md` files or `docs/` do not start a build, and the other two workflows start only when you press Run.
* **I am not recommending a paid "larger" runner.** The standard one is enough. Larger runners, as I understand it, are always billed per minute whatever your plan includes.

If the repository is private and you want to be careful, run the build by hand (Part 2) a few times and watch the Billing page after the first one.

## Part 2. Run the cloud build

* **Automatically:** every time you upload or push a change to `main`.
* **By hand:** repository > **Actions** > **iOS build** (left list) > **Run workflow** > **Run workflow**.

What it does, in order. Each line is its own row in the results, so you can see exactly where it stops:

1. Checks the folder layout, and refuses to go on if a signing key or certificate is in the repository.
2. Selects Xcode 26.5 and installs XcodeGen 2.45.4 on a macOS runner.
3. Checks the app catalogue and the URL-scheme list agree.
4. Generates `CabinDash.xcodeproj` from `project.yml`.
5. Checks the generated project really contains every source file, the icons, the privacy manifest, the `CabinCore` package, the location text and the URL schemes.
6. Runs the `CabinCore` unit tests on the Mac (`swift test`).
7. **Builds the app for the iOS Simulator, without any signing.**
8. Runs the unit tests again on the iOS Simulator.
9. Counts the tests that ran. A run where no tests executed, or fewer than the number declared with `@Test` in the source, is a **failure**, not a pass.
10. Launches the app on the simulator, waits 12 seconds, checks it is still running, and saves a screenshot.
11. Uploads everything as downloads, and writes a results table.

Nothing is skipped to make the run look green: a failed step turns the whole run red, and steps that cannot run because an earlier one failed are marked `skipped`, not `success`.

## Part 3. Read the result

Open the run (Actions > click the run at the top of the list).

* **Red cross or green tick** next to the run name. Green means every row below was `success`.
* **Annotations** at the top list errors, each with a file and line number when Xcode gave one.
* **The summary** (scroll down on the same page) shows, in this order: tool versions, what the generated project check found, the test counts, a block called **App build** with the compiler's errors, and a **results table** with one row per step.
* **Artifacts** at the bottom: `ios-build-results-<number>`. Download and unzip it. It holds the full logs (`xcodebuild-build.log` is the one to open for compile errors), `…-errors.txt` files with just the errors, the `.xcresult` bundles (Xcode-only; you cannot open these on Windows, so use the logs), and `launch.png`, a screenshot of the app running on the simulator.
* To see a single step's full output, click the job name (**Build and test (iOS Simulator)**) on the left and expand the step.

If it is red, copy the **App build** block (or the failing step's output) and give it to Claude along with the name of the step. That is all Claude needs to propose a fix.

## Part 4. Change something with Claude, then build again

1. Describe the change or paste the errors to Claude. Claude edits the files and gives you back either the changed files or a new ZIP.
2. Copy the changed files over the ones in your unzipped folder (replace when asked).
3. **GitHub Desktop:** it lists the changed files. Write a summary, **Commit to main**, **Push origin**. The build starts by itself.
   **Browser only:** open the file on GitHub, click the pencil, paste the new text, **Commit changes**; or drag the changed files into **Add file > Upload files**.
4. Open **Actions** and watch the new run (a minute or so to start).

Changes to only `.md` files or `docs/` do not start a build; use **Run workflow** if you want one.

## Part 5. From a simulator build to your iPhone

A green simulator build shows that the code compiles and the tests pass. It does not show the app can be installed, signed, or that GPS and app detection work on a real phone. The choices are laid out in **`docs/DEVICE-INSTALL.md`**:

* **Free, no Mac:** run the manual **Unsigned IPA** workflow, then sign it on your PC with a sideloading tool (iLoader worked for this project; Sideloadly and AltStore are others) using a free Apple ID. It stops opening after about 7 days.
* **About US$99 a year, no Mac, no cable:** the paid Apple Developer Program plus TestFlight. The **Device build to TestFlight** workflow is switched off until you add your own secrets in GitHub's settings.

No Apple password, private key or certificate ever goes in the repository. The build stops if it finds one.

## First-run problems

| What you see | Likely cause | What to do |
|---|---|---|
| No "iOS build" in the Actions tab | `.github` was not uploaded, or the branch is not called `main` | Check `.github/workflows` exists on the repository page; use GitHub Desktop (Option A) |
| First step red: "project.yml is inside the folder…" | The folder was uploaded instead of its contents | Upload what is *inside* the folder |
| "Xcode 26.5 is not on this runner" | GitHub changed what the runner image holds | The log lists the versions present. Edit `xcode-version` in `.github/actions/setup-ios-toolchain/action.yml` |
| Warning "XcodeGen is not the pinned version" | The pinned release could not be downloaded; Homebrew's was used | Not fatal. The generated project is still checked afterwards |
| "Generated project" row red | XcodeGen left something out | Give Claude the table from the summary page |
| "App build" has errors | The first real compile errors | Give Claude the **App build** block |
| Simulator tests: "No tests were executed" | The `CabinCore` scheme did not include the test target | The Mac test row still covers the same tests; tell Claude, it is a small fix |
| Launch row red, but the screenshot shows the app running | The launch check misread the process list (its format has not been confirmed) | Tell Claude; the check will be fixed, not ignored |
| Launch row red, screenshot blank or an error | The app crashed on start | Open `crash-reports/` in the artifact, if present, and give Claude the contents |

## Tool versions (pinned in one place)

| Tool | Version | Where to change it |
|---|---|---|
| Runner image | `macos-26` | `runs-on` in each workflow |
| Xcode | 26.5 | `.github/actions/setup-ios-toolchain/action.yml` |
| XcodeGen | 2.45.4 | same file |
| GitHub actions used | `actions/checkout@v4`, `actions/upload-artifact@v4` | in the workflows (major versions, not commit hashes) |
| iPhone minimum | iOS 17.0 | `project.yml` (unchanged) |
| Swift language mode | 5 | `project.yml` (unchanged) |

Xcode 26.5 was picked because recent Xcode versions are the ones Apple accepts for App Store and TestFlight uploads, so one toolchain serves the simulator build now and the signed build later. Those details come from GitHub's runner-image listing and Apple's published rules as I read them; neither was tested here.

## How the app works

**Finding your apps (Other apps screen only).** iOS does not let an app list what is installed. The only allowed trick is to ask, app by app, "can you open `spotify://`?" Cabin Dash does that for the 37 apps in `Catalog.swift`, and 30 of them have a known link. Those appear on their own. **It cannot find an app that is not in the catalogue**; those can be added by hand. The full list of what iOS permits and how the app copes is in **`docs/IOS-LIMITS.md`**.

- Seven catalogue apps have no known link (HERE WeGo, A Better Routeplanner, PlugShare, ChargePoint, Electrify America, EasyPark, CARROT Weather). Add them with the **+** button. When tapped they open their website or App Store page.
- Six links are best guesses and may not match: SiriusXM, iHeartRadio, TuneIn, SpotHero, ChatGPT and Claude. If one is wrong, that app is not detected until you add it by hand.
- Any app whose link you know can be added: in the add screen, type `myapp://`.
- Remove an app with a long press. You can undo it.

**Icons.** iOS will not hand over another app's icon, so Cabin Dash gets each app's artwork from the App Store (Apple's public iTunes lookup service). A result is only used if its name matches the app, so a wrong id never shows another app's icon. With no internet a coloured letter is shown instead. While Other apps is off (the default), no icon lookups are made at all. With it on, Cabin Dash sends Apple the App Store ids or names of the apps on your shelf (and of every supported app when you open the add screen). Nothing else is sent, and your location never leaves the phone.

**Opening apps.** Tapping tries the app's own link first, then its website, then its App Store page. If all three fail, a message says so.

**The dock.** The same buttons on every screen: Home, Map, Music and Drive from the top, Settings at the bottom, and Apps after Drive if you turned on Other apps. The buttons shrink to fit short screens, but never below 30 points. The selected screen has a small bar under its button. The header shows the time, Wi-Fi or cellular, a GPS dot and the battery; iOS gives apps no signal-strength reading, so there are no signal bars. The navigation rules (what the dock shows, where a tap goes, which bars appear where) are plain code in `CabinCore/Sources/CabinCore/Feature.swift` and are unit tested.

**Other apps.** Off by default (Settings > Other apps). The screen lists Messages, which opens the iPhone's own app, then the apps found on your iPhone, then Add Apps. There is no Phone tile: iOS has no link that opens the Phone app, and a bare `tel://` link only shows iOS's Call prompt with no number in it (seen on a phone). Phone comes back as a screen of its own. iOS shows no unread badges to other apps, so there are none. If you switch Other apps off while that screen is open, you land on Home.

**Home.** The map widget is a real MapKit map that follows you and cannot be dragged; while a route is planned or followed it draws the same route line and destination flag as the Map screen (both use one shared definition), and while it is followed it shows the next instruction, the distance to it and the time left. The music widget shows what Spotify is playing, or one line saying what is missing (Spotify isn't set up, Connect Spotify, Nothing playing). The drive widget is the same speed dial as the Drive screen with your trip underneath, or says "Location is off" or "Finding GPS" when there is no location. The route card sits at the top of the map widget so Apple's "Maps" attribution in the bottom-left corner stays visible.

**Map.** The map and the directions come from Apple Maps (MapKit), because iOS cannot put Google Maps inside another app. Turn-by-turn here is simple: it shows the next instruction and counts down the straight-line distance to it, and it moves on when you pass it. It does not speak, does not reroute by itself (there is a Reroute button), and stops updating when the screen is off or the app is in the background. For real navigation use **Open in Google Maps**, which starts the trip in the Google Maps app (set "Directions with" to Google Maps in Settings).

**Music.** See `docs/SPOTIFY-SETUP.md`. The section bar along the top switches between Now Playing, Playlists, Liked, Search and Queue; the device chip beside it opens the list of Spotify devices. Tapping Play sends the music to this iPhone with no other step. Music on this iPhone is played, shown and steered through the Spotify app itself (Spotify's iOS SDK): straight away while Cabin Dash is connected to it, and otherwise through a brief hop into the Spotify app that returns to Cabin Dash by itself. A song tapped in a playlist, Liked Songs or a Search result plays its playlist, Liked Songs or album from that song. Spotify's web service is used for browsing and for a TV or speaker you pick. A device you pick in the list is used instead until you go back to **This iPhone**. Cabin Dash never picks any other device for you. Typing in Search is locked while the car is faster than about 8 km/h and stays locked until it has been below 4 km/h for 10 seconds; Passenger mode (Settings > Driving) turns the lock off. Likes go straight to Spotify and nothing is saved on the phone.

**Speed and trip.** From Core Location, only while the app is on screen. Standing still, poor readings and sudden jumps are ignored. The screen stays on while the app is open (switch off in Settings) and always while a route is being followed, so keep the phone plugged in. Turning off "Precise Location" for the app currently breaks speed and distance without a message; see `docs/IOS-LIMITS.md`.

## Changing the app list

1. Edit `CabinCore/Sources/CabinCore/Catalog.swift`.
2. Run `python3 scripts/check_schemes.py --write` (needs Python on your PC) to copy the links into `project.yml` and `Config/Info.plist`. Or ask Claude to do it. The cloud build fails if the two lists differ.

## If you ever get a Mac

```sh
brew install xcodegen
xcodegen generate
open CabinDash.xcodeproj
```

Then pick your iPhone and press Run. Put your Team ID and a bundle id of your own in a new file `Config/Signing.local.xcconfig` (it is git-ignored):

```
DEVELOPMENT_TEAM = ABCDE12345
CABIN_BUNDLE_ID = com.yourname.cabindash
```

## Files

```
.github/workflows/ios-build.yml          Simulator build and tests (the main one)
.github/workflows/ios-unsigned-ipa.yml   Manual. Unsigned .ipa for sideloading, versioned as a beta from its run (CHANGELOG.md)
.github/workflows/ios-device-build.yml   Manual and OFF. Signed TestFlight upload
.github/actions/setup-ios-toolchain/     Pins Xcode and XcodeGen for all three
project.yml            Xcode project recipe (XcodeGen)
Config/Signing.xcconfig  Signing defaults; nothing secret (personal values go in a git-ignored local file)
Config/Info.plist      Location text, app links, orientations, Spotify Client ID slot (XcodeGen rewrites it)
CabinCore/             Logic with no UI: the screens and dock rules (Feature.swift), catalogue, App Store matching, shelf and Other apps rules, trip maths, route guidance, Spotify sign-in and parsing, preferences, tests
CabinDash/             The app itself
  Model/               Shared state: AppModel (holds the Router), location, route, Spotify, toasts
  Views/Shell/         Dock (StatusRail), the bars on top (Strips), Other apps screen, wallpaper
  Views/Dashboard/     Home widgets
  Views/Map/           Map screen and place search
  Views/Music/         Music screen: Now Playing, Playlists, Liked, Search, Queue, device picker
  Views/Drive/         Drive screen and gauge
  Views/Settings/      Settings screen
scripts/ci/            Helpers the cloud build runs, and their tests
scripts/check_schemes.py, swift_sanity.py, make_icon.py   (make_icon.py draws the flat app icon, measured from design/icon-source.png)
scripts/add_spotify_icon.py   Adds Spotify's own images (icons, like icons) from its design page (docs/SPOTIFY-RULES.md)
design/                The artwork the app icon is made from
docs/AUDIT.md          What was checked and changed before the first build
docs/IOS-LIMITS.md     What iOS allows and how the app copes
docs/DEVICE-INSTALL.md Signing, secrets, and getting the app on a phone
docs/SPOTIFY-SETUP.md  Making the Spotify developer app and connecting it
docs/SPOTIFY-RULES.md  Spotify's rules, what Cabin Dash follows, and where it falls short
```

## Not CarPlay

Real CarPlay on the phone screen is not possible: Apple only lets CarPlay run on a car's display through certified hardware. Cabin Dash copies how it looks and works, and uses only public iOS features. It uses no Apple artwork or wallpapers: the ribbons and tiles are drawn in code, and app icons are fetched from the App Store at runtime.
