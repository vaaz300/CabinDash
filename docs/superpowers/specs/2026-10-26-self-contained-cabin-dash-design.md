# Cabin Dash as one self-contained driving app

Design for review. Date: 2026-10-26. Status: **proposed, not approved, no feature code written.**

This document changes the product direction. Cabin Dash stops being a launcher with a few built-in screens and becomes one app with its own screens for navigation, music, calls, messages, contacts, speed, trips and settings. It says, feature by feature, what can live inside Cabin Dash, what needs a permission or account, and what iOS blocks.

## 1. What you asked for, and what I'm assuming

**From your brief (your words, shortened):**

* "I do not want an app launcher that sends users to other apps. I want a self-contained, all-in-one driving interface."
* Built-in screens for navigation, music, calls, messages, contacts, vehicle information, speed, trip statistics and settings.
* Keep you inside Cabin Dash for as many tasks as iOS and supported third-party integrations allow.
* Native screens, not third-party app icons, as the main way in.
* MapKit for the map. Supported integrations only for music. Permitted system APIs for contacts and calling. Supported compose/share interfaces for messages.
* No website in a WebView standing in for an app. No private APIs to embed other apps.
* Success test: one coherent app with a persistent dock and its own screens, not a collection of shortcuts.
* Architecture first. No new app icons. Keep the existing project and the Windows-only workflow.

**What I'm assuming (tell me if any is wrong):**

* This is for you alone, on your own iPhone, mounted in the car. It is not for the App Store and not for other people.
* Landscape only, as built now.
* You use Spotify (Premium) and want it to stay your music source.
* You sideload with a **free Apple Account** through iLoader, so nothing here may need a paid developer membership. (Anything that would is marked, and I have not planned it.)
* Driving safety matters more than feature count. I propose a driving lock on typing (section 7).

## 2. How I checked, and what the labels mean

I checked the rules below against Apple's and Spotify's own pages in this session where I could. Some pages were not reachable from my environment. Each claim carries a label:

* **[V]** read on the official page this session.
* **[T]** read on a third-party copy of the official reference. Treat as likely, confirm later.
* **[M]** from my memory of the platform. Not checked. Please treat as a prediction.
* **[?]** I don't know. Needs a test on your phone.

Nothing in this document has been compiled or run. The last code I pushed (`c5b2c5c`) has not yet been confirmed as a green cloud build by you, and I have no way to read the build result myself. That comes before anything new (section 10, phase 0).

## 3. The feature matrix

One line per feature. Detail follows in section 4.

| Feature | Fully inside Cabin Dash | Needs a permission, account or API | iOS prevents |
|---|---|---|---|
| **Navigation** | MapKit map, place search, route, turn-by-turn, traffic, saved places, ETA | Location permission (have it). Optional: spoken prompts need no permission; running with the screen off needs a background mode | Offline maps. Google Maps' map inside the app. Speed limits and cameras |
| **Music** | Now Playing display, play/pause/skip/seek, playlists, search, queue, like (Spotify) | Spotify Premium, your own Spotify developer app, sign-in with more scopes | Playing Spotify audio in Cabin Dash. Reading what *other* apps play. Spotify "radio" |
| **Calls** | Dial pad, favourites, tap-to-call, "on a call" banner | Contacts permission for names | Placing a call without handing it to the system Phone. Answering, hanging up, muting. Reading the call history |
| **Messages** | Compose screen, quick replies, share ETA, share location | Contacts permission for recipients. A SIM or iMessage set up | Reading messages. Sending without you tapping Send. Message notifications and badges |
| **Contacts** | Searchable A–Z list, contact cards, call/message/navigate actions | Contacts permission (full or limited) | The contact "notes" field (Apple restricts it). Editing sync/accounts |
| **Vehicle info** | What the phone can sense: speed, heading, altitude, battery | An OBD-II Bluetooth LE adapter you buy (optional, later) | Any data from the car itself without that hardware |
| **Speed** | Large speedometer from GPS | Location permission (have it) | The car's own speedometer reading |
| **Trip statistics** | Distance, time, moving time, average and max speed, trip history | None | Nothing |
| **Settings** | All Cabin Dash options as an in-app screen | None | Changing iOS settings, Wi-Fi, Bluetooth, volume, Focus |

## 4. Feature detail

### 4.1 Navigation

**Fully inside Cabin Dash.** MapKit map with position, heading and traffic. Place search and routes with `MKLocalSearch` and `MKDirections`. Turn-by-turn from the route steps, rerouting by asking again when off route. Saved places (Home, Work, favourites) in Cabin Dash's own store. All of this exists in the current build and has never been run on a phone.

**New in the plan.**

* *Spoken prompts*: `AVSpeechSynthesizer` with the audio session set to lower other audio while it speaks, so Spotify dips instead of stopping. [M] No permission needed.
* *Navigate to a contact*: a contact's postal address becomes a destination (geocoded with MapKit). [M]
* *Keep guiding with the screen off*: needs the `location` and `audio` background modes. Xcode just writes them into `UIBackgroundModes` in Info.plist [V]. Whether a free-account install accepts them I have not checked [M, probably yes because it is not an entitlement].

**Needs.** Location "While Using" permission (already requested).

**iOS prevents or doesn't offer.**

* Offline maps: MapKit has no offline API. [M]
* Google Maps tiles or navigation inside the app: needs Google's SDK with an API key and billing, and I won't put Google Maps in a web view. Cabin Dash keeps "Open in Google Maps" only as an optional hand-off button inside the Map screen.
* Speed limits, speed cameras, lane guidance: not exposed by MapKit as far as I know. [M]
* Apple Maps' own favourites and recents: not readable. Cabin Dash keeps its own.

### 4.2 Music

**Chosen integration: the Spotify Web API, as already built.** The alternatives, with reasons:

| Option | Verdict |
|---|---|
| **Spotify Web API** (current) | **Keep.** Pure HTTPS, works with the current code, no extra binary in the build. Controls the Spotify app, which keeps playing the audio. |
| Spotify iOS SDK ("App Remote") | Not now. Needs the Spotify app installed and running as a background service, and a physical device. [V] It adds a binary dependency to the cloud build, and I believe it bounces you into the Spotify app to connect. [M] Revisit only if polling lag annoys you. |
| Apple Music (MusicKit) | **Not possible on your setup.** Apple's forum answer from an Apple engineer says a *paid* Developer Program membership is required. [V] You also use Spotify. |
| On-device library (`MediaPlayer`) | Possible without a paid account [M] but only plays music stored on the phone. Not planned. |
| Reading what other apps play | Blocked. The only route is a private framework. Not used. |

**Spotify rules as of February 2026** [V, from Spotify's migration guide]:

* The Spotify account that owns the developer app must be Premium. If it lapses, the app stops working.
* A development-mode app allows 5 named users, which is plenty for you.
* Search returns at most 10 results per request (default 5).
* Saving/removing library items moved to `PUT/DELETE /me/library` and `GET /me/library/contains`, using Spotify URIs.
* `GET /me/playlists` stays. `GET /playlists/{id}/items` works **only for playlists you own or collaborate on**. So I can list your playlists and *play* any of them, but I can't list the tracks inside a playlist someone else made.
* The migration guide says nothing about the player endpoints, so I expect them unchanged. [M]

**Fully inside Cabin Dash (planned):**

* Now Playing: artwork, title, artist, album, progress, previous/play/pause/next, seek (built).
* Shuffle and repeat (`PUT /me/player/shuffle`, `/repeat`). [T]
* Up Next queue (`GET /me/player/queue`). [T]
* Your playlists list, tap to play (`PUT /me/player/play` with a `context_uri`). [T]
* Search for tracks, albums, playlists, tap to play. [V for the 10-result limit; T for the rest]
* Like/unlike the current track via the new `/me/library` endpoints. [V]
* A device picker ("Play on: this iPhone") using `GET /me/player/devices` and `PUT /me/player`. [T]
* Liked Songs list: **[?]** the migration guide removes the *save/remove* endpoints for `/me/tracks` and doesn't mention the list call. I will test it on the phone rather than promise it.

**Needs.**

* Spotify Premium (you have it).
* Your own Spotify developer app and the `SPOTIFY_CLIENT_ID` variable (done, per `docs/SPOTIFY-SETUP.md`).
* **New scopes** (`playlist-read-private`, `user-library-read`, `user-library-modify`, plus the existing three). Spotify scopes are fixed at sign-in, so you will have to **sign in to Spotify again once** after that build. [M]

**iOS and Spotify prevent.**

* Spotify audio cannot play inside Cabin Dash. The Spotify app has to be installed and running somewhere. If it isn't running, the device list can be empty and "Play" fails with a no-active-device error. [M, and Spotify community threads show empty device lists] Cabin Dash will show a clear "Open Spotify once" state with a button. That is the one place music still needs the other app.
* The "radio" button in your reference screenshot has no supported equivalent. [M]
* Volume: no Cabin Dash volume slider via Spotify. [M] Use the phone's buttons or the car.

**Two Spotify policy points you need to decide on (section 9, D3).** From the Spotify Developer Policy as my fetch tool summarised it (read the policy yourself before relying on this):

* *Voice control of Spotify is prohibited* (III). So no Cabin Dash speech feature will control Spotify. Siri is a separate system feature and is not affected.
* *No products that mimic or replicate a core Spotify experience without written permission* (III.11). A full browser/player UI is closer to that line than a remote control is. Development mode is described by Spotify as a sandbox for personal, non-commercial projects, so enforcement against a one-user app looks unlikely, but the text applies.
* *Attribution*: Spotify content must be attributed to Spotify with the Spotify marks, and metadata/artwork must link back to Spotify (II.4). The current Now Playing screen does neither properly, and `docs/SPOTIFY-SETUP.md` says "does not use the Spotify logo". The Music screen will get an attribution line and a link-back to the item in Spotify. Logo details are in Spotify's branding guidelines, which I haven't read.

### 4.3 Calls

**What iOS gives.** There is no public API to place a call from inside your own app. The only supported route is a `tel:` link, which hands the call to the system Phone. [M] iOS then asks you to confirm the call. [M] CallKit is for apps that *are* phone apps (VoIP), not for controlling the cellular call. [M]

**There is one useful, supported hook.** Any app can create a `CXCallObserver` to be told about call activity on the system. [V] Fields such as "connected", "ended" and "on hold" I know from memory [M]. This lets Cabin Dash show **"On a call · 03:12"** on every screen and pause its own spoken prompts. It does not give phone numbers, names or call history. [M]

**Fully inside Cabin Dash.**

* Phone screen with three tabs: **Favourites**, **Contacts**, **Keypad**.
* Favourites: Cabin Dash's own list of people you pin (not your Phone-app favourites, which aren't readable). [M]
* Keypad with dialling, then hand-off.
* "On a call" banner (above).
* Recents: only calls **placed from Cabin Dash**, logged by Cabin Dash itself. It cannot see other calls' numbers.

**Needs.** Contacts permission to show names (section 4.5). Keypad dialling needs none.

**iOS prevents.** Placing the call without the system Phone taking over. Answering, declining, ending, muting or speaker control. Reading the real call log or voicemail. Incoming-call screen replacement (the system shows its own).

### 4.4 Messages

**Fully inside Cabin Dash.** A Messages screen that presents Apple's own compose sheet (`MFMessageComposeViewController`) on top of Cabin Dash. You stay in the app visually. The sheet is system UI, you press Send, and the app is told "sent / cancelled / failed". [V from Apple's sample] Cabin Dash must check `canSendText()` first, because without it the composer is nil and the app would crash. [V]

Built on that:

* **Quick replies**: "On my way", "Running 10 minutes late", "Call you when I park".
* **Share ETA**: pre-fills "I'll be there at 18:42" from the active route, to a Favourite or any contact. This is the feature that makes Map, Contacts and Messages feel like one app.
* **Share location**: a Maps link to where you are.
* Email through the matching mail composer. [M]

**Needs.** Contacts permission for names. An iPhone that can send SMS or iMessage. [V for SMS]

**iOS prevents.** Reading any message, thread or notification. [M] Sending without your tap. [V] Unread badges. A "reply" to an incoming message from inside Cabin Dash. Cabin Dash will not pretend otherwise: the Messages screen is for **sending**, and says so.

### 4.5 Contacts

**Fully inside Cabin Dash.** An A–Z searchable list, a contact card, and three actions per person: **Call**, **Message**, **Navigate** (if they have an address). Pin to Favourites.

**Needs.** `NSContactsUsageDescription` in Info.plist (the app **crashes** without it) [V]. Since iOS 18 you can grant *full* or *limited* access [V]. Cabin Dash must work in both: with limited access it shows what you shared and offers Apple's `ContactAccessButton` / `contactAccessPicker` to share more [V]. If you deny access, the Contacts tab shows a one-line explanation and a button to Settings.

**iOS prevents.** The contact **notes** field needs a special entitlement from Apple, so Cabin Dash won't read it. [V]

### 4.6 Vehicle information

**The honest position.** iOS exposes no data from your car. Fuel level, RPM, coolant temperature and fault codes do not reach the phone unless you add hardware.

* **Without hardware (can ship):** a *Vehicle* tab that shows what the phone itself knows: speed, heading, altitude, battery and charging state, connectivity. It is useful, but it is not "vehicle data" and the tab will not call it that.
* **With an OBD-II adapter (optional, later):** iPhones can only talk to **Bluetooth LE (4.0)** OBD adapters. Older classic-Bluetooth ELM327 clones are not discoverable. [V, from an OBD app vendor's help page] Wi-Fi adapters exist but make the phone join the adapter's network. [M] A Bluetooth LE adapter would give RPM, coolant temperature and similar, depending on what your car reports (it varies by make and model). [M] It needs `NSBluetoothAlwaysUsageDescription` and, I believe, no paid entitlement. [M]
* I can write and unit-test the OBD message decoding in advance, because that is pure arithmetic. I **cannot** test the Bluetooth connection or your car's responses until you have an adapter in your hands, and I won't claim it works before then.

### 4.7 Speed

Fully inside, already built: GPS speed from Core Location, in km/h or mph. Limits: it is the phone's GPS speed, which can differ slightly from your car's dial and lags a moment at the start. The car's own speed is not available. [M]

### 4.8 Trip statistics

Fully inside, partly built (`TripTracker`): distance, elapsed and moving time, average and maximum speed. New: a saved **trip history** (stored on the phone as a small JSON file), a summary after each trip, and reset. No permission beyond Location. This is pure logic, so it gets unit tests in CI.

### 4.9 Settings

Fully inside. Settings stops being a sheet and becomes a screen in the app (units, theme, wallpaper, keep awake, driving lock, Spotify connection, favourites, saved places). What iOS blocks: changing Bluetooth, Wi-Fi, system volume, Do Not Disturb or Driving Focus. The only way out is a button that opens Cabin Dash's own page in the iOS Settings app. [M]

## 5. Approaches considered

**A. Keep the launcher grid, add more built-in screens.** Smallest change. Rejected: it keeps app icons as the front door, which is exactly what you ruled out.

**B. One shell with feature modules (recommended).** A persistent dock and rail around a set of features, each a self-contained folder with its own screen(s), model and service. A small router moves between them and lets them hand work to each other (a contact's address opens the Map; the route's ETA fills a message). A Dashboard replaces the icon grid as the home screen.

**C. Embed other apps' content (web views, private frameworks).** Rejected outright: you excluded it and it would break the free-account sideload and Apple's rules.

## 6. Architecture (approach B)

```
┌────────────────────────────────────────────────────────────────────────────┐
│ SHELL (always on screen)                                                   │
│  Dock: Home · Map · Music · Phone · Messages · Drive   + gear (Settings)   │
│  Status rail: clock · GPS · connection · battery                           │
│  Strips shown on every screen that does not own that information:          │
│     now-playing mini-bar · next-turn banner · "on a call" banner           │
│  Router: which feature is showing, sheets, and the driving lock            │
└────────────────────────────────────────────────────────────────────────────┘
┌────────────────────────────────────────────────────────────────────────────┐
│ FEATURES (each = its screens + its model + its service)                    │
│  Dashboard · Map · Music · Phone · Messages · Drive · Settings             │
└────────────────────────────────────────────────────────────────────────────┘
┌────────────────────────────────────────────────────────────────────────────┐
│ SERVICES (thin wrappers around iOS, no screens)                            │
│  Location · Device · Spotify · Contacts · CallState · Speech · (OBD later) │
└────────────────────────────────────────────────────────────────────────────┘
┌────────────────────────────────────────────────────────────────────────────┐
│ CABINCORE (pure Swift, no UIKit, unit-tested in CI)                        │
│  Features/router state · dock rules · PhoneNumber · QuickReply · TripLog   │
│  Spotify parsing · DrivingLock · RouteGuide · OBD decoding (later)         │
└────────────────────────────────────────────────────────────────────────────┘
```

**What makes it one app, concretely:**

1. **One dock, always there.** Six fixed features plus a gear. The dock is the only primary navigation. It holds no third-party apps.
2. **Cross-feature strips.** The music mini-bar, the next-turn banner and the call banner appear on every screen that isn't the owner of that information, so the car's three live things (music, route, call) are never hidden by whatever screen you're on.
3. **Features hand work to each other through the router, not through URLs.** Contact → Navigate opens the Map with that destination. Map → Share ETA opens Messages with the text filled in. Phone → Message, Dashboard widget → its full screen.
4. **One look.** The existing theme, rail and wallpaper stay. One settings store.
5. **Dashboard replaces the icon grid.** It follows your second reference screenshot: a live map panel with the next-turn card, a music widget with controls, and a speed/trip widget. (A calendar widget like Apple's would need Calendar permission via EventKit. Not planned unless you ask.)

**Where Cabin Dash still leaves the app, stated plainly:** the Phone app takes over a call after you tap Call; Spotify must be running for audio; the Spotify sign-in uses an in-app sheet that shows Spotify's login page. Optional: an "Open in Google Maps" button on the Map screen, and a Settings switch for an **Other apps** shelf (default off, section 9 D1).

### Code structure

```
CabinDash/
  Shell/        Dock, StatusRail, Strips (mini-bar, banners), Router, RootView
  Features/
    Dashboard/  DashboardView
    Map/        MapScreen, search, guidance   (moved from Views/Maps)
    Music/      NowPlaying, Library, Queue, Devices   (moved + extended)
    Phone/      Favourites, Keypad, ContactsList, ContactCard
    Messages/   MessagesScreen, ComposeSheet wrapper
    Drive/      Speed, Trips, Vehicle   (DriveView split up)
    Settings/   SettingsScreen
  Services/     Location, Device, Spotify, Contacts, CallState, Speech, Keychain
CabinCore/      pure logic + tests  (SwiftPM package, as now)
```

**Existing pieces and what happens to them:**

| Today | Becomes |
|---|---|
| `AppModel` (does everything) | A thin composition root that holds the services and the router. The app-list code moves out of the main path. |
| `AppScreen` (maps / nowPlaying / drive) | `Feature` (dashboard, map, music, phone, messages, drive, settings) |
| `HomeLayout` tile pages, `HomeGrid` | Retired as the home screen. The tests for it are replaced by tests for the new dock/router logic. |
| `Catalog` (37 apps), `PickerSheet`, icon fetching | Kept, but only behind the optional **Other apps** shelf and the Map's hand-off button. Not the front door. |
| `StatusRail` | Same rail, with fixed feature icons instead of "recent apps" |
| `MapScreen`, `RouteModel`, `RouteGuide` | Kept. Add spoken prompts, contact destinations, ETA sharing. |
| `NowPlayingScreen`, `SpotifyModel` | Kept. Add shuffle/repeat/like, queue, playlists, search, devices, attribution. |
| `DriveView`, `TripTracker` | Kept. Add trip history and the Vehicle tab. |
| `SettingsSheet` | Becomes a screen |

**What changes in project files** (all additive; nothing here needs a paid account):

* Info.plist: `NSContactsUsageDescription` (needed). Later: `NSBluetoothAlwaysUsageDescription` (only with OBD), `UIBackgroundModes` (only if you want guiding with the screen off).
* `LSApplicationQueriesSchemes` stays for the optional Other-apps shelf.
* `PrivacyInfo.xcprivacy` reviewed for the new APIs.
* No entitlements file, no new capabilities, no signing changes. `Config/Signing.xcconfig` is untouched.
* No new third-party packages.

## 7. Driving safety

The messages and contacts features are the risky ones in a moving car. My proposal:

* A **driving lock** in CabinCore (a tested rule): above about 8 km/h, with some hysteresis so it doesn't flicker, typing is disabled. The Messages screen then offers only the pre-written quick replies and Share ETA; the Contacts list shows Favourites only; search fields are inactive.
* A Settings switch, "Passenger mode", turns the lock off.
* This is a design default for you to accept or change. It is not legal advice. As far as I recall, holding a phone while driving is an offence in Ireland and a mounted phone is treated differently, but check the Road Safety Authority's current rules yourself. [M]

## 8. What I can and cannot verify from Windows

* **The cloud build proves:** the code compiles, the pure-logic unit tests pass, the app launches in a simulator and I can see one screenshot.
* **It cannot prove:** that Spotify answers, that Contacts permission behaves, that the call hand-off works, that messages compose, that GPS-driven navigation behaves in a car, or that the layout looks right on your phone. Those are tested by you, on the phone, with a short checklist I give you at the end of each phase.
* Every phase is a small push followed by a cloud build. I won't call a phase done on a green build alone, and I won't report a pass I haven't seen.
* Rules for the work that stay in force: signing stays out of the source; no Apple passwords or certificates in the repo; no skipped compilation; no invented results; limitations stated.

**Known risks:**

* *Dock fit.* Six feature icons, a gear and the status block have to fit in the height of an iPhone held sideways (roughly 350 points after the safe areas). It is tight. The sizes are already computed from the available height, but I haven't seen it on a screen. If it is too cramped, Drive and Messages are the first candidates to move into the Dashboard.
* *Spotify with no active device.* If the Spotify app isn't running, playback commands can fail. The screen will say so and offer one button. This is Spotify's design, not something Cabin Dash can remove.
* *Free-account limits are unchanged.* The installed app still expires after 7 days and has to be reinstalled. [V, Apple's membership page: provisioning profiles expire after 7 days.] Nothing here makes that better or worse.
* *Unrun code.* Every feature above is written without a compiler or a phone in front of me. Expect a round or two of fixes per phase.

## 9. Decisions I need from you

Defaults are in bold. Replying "approved" takes all defaults.

* **D1. Other apps shelf.** **Default: keep the catalog, but off by default behind a Settings switch; the dock holds only Cabin Dash features.** Alternative: delete the launcher code completely.
* **D2. Driving lock.** **Default: on, with a Passenger mode switch.** Alternative: no lock.
* **D3. How far to take Spotify.** **Default: remote control plus your playlists, search, queue and like, with proper Spotify attribution.** Safer alternative: Now Playing, controls and queue only, with no browsing. The browsing version is closer to Spotify's "don't replicate a core experience" clause (4.2), though a one-user development app is the case the sandbox was made for.
* **D4. Apple Music.** **Default: skip.** It needs a paid membership.
* **D5. Vehicle screen.** **Default: ship the phone-sensed version now; do OBD only if you buy a Bluetooth LE adapter.**
* **D6. Order of work.** **Default: shell and dashboard first, then Music library, then Phone and Contacts, then Messages, then spoken guidance, then Vehicle.** Tell me if you'd rather start with calls and contacts.

## 10. Phases

Each phase ends with a push, a cloud build, and a short checklist for your phone.

* **Phase 0. Confirm the base.** You tell me whether the `c5b2c5c` cloud build is green, or send the "App build" block if not. I fix compile errors first. Nothing new starts on an unconfirmed base.
* **Phase 1. Shell and Dashboard.** `Feature` enum, router, fixed dock, Dashboard with live widgets, Settings as a screen, launcher demoted per D1, mini-bar and route banner. CabinCore: dock and router logic with tests.
* **Phase 2. Music library.** Scopes, shuffle/repeat/like, queue, playlists, search, devices, attribution. Parsing in CabinCore with tests. You sign in to Spotify again.
* **Phase 3. Phone and Contacts.** Permission flow (full/limited/denied), list, card, favourites, keypad, call banner. Phone-number cleanup and sorting in CabinCore with tests.
* **Phase 4. Messages.** Compose wrapper, quick replies, Share ETA and location, driving lock. Message text builders and the lock rule in CabinCore with tests.
* **Phase 5. Guidance polish.** Spoken prompts, background mode (if you want it), contact destinations.
* **Phase 6. Drive and Vehicle.** Trip history, phone-sensed Vehicle tab. OBD decoding tests, only if D5 says so.

The docs (`README.md`, `docs/IOS-LIMITS.md`, `docs/AUDIT.md`, `docs/SPOTIFY-SETUP.md`) are updated in the phase that changes what they describe.

## 11. What I'm deliberately not doing

* No web view standing in for an app, and no scraping.
* No private frameworks (for example to read other apps' now-playing).
* No claim that Cabin Dash can read messages, answer calls or read the car.
* No new app icons or catalog entries.
* No Spotify audio streaming and no voice control of Spotify.
* No paid-account features (MusicKit, CarPlay, push, App Groups).

## 12. Sources

* Spotify, [February 2026 Web API Dev Mode Changes: Migration Guide](https://developer.spotify.com/documentation/web-api/tutorials/february-2026-migration-guide) [V]
* Spotify, [Update on Developer Access and Platform Security](https://developer.spotify.com/blog/2026-02-06-update-on-developer-access-and-platform-security) [V]
* Spotify, [iOS SDK overview](https://developer.spotify.com/documentation/ios) [V]
* Spotify, [Developer Policy](https://developer.spotify.com/policy) [V via summary: read it yourself]
* Spotify player endpoint list, third-party copy: [player-api.md](https://glama.ai/mcp/servers/@iceener/spotify-streamable-mcp-server/blob/5b97d51684714ef8ead181508b9b1b262fa51e4b/_spec/spotify-api/player-api.md) [T]
* Apple, [Accessing the contact store](https://developer.apple.com/documentation/contacts/accessing-the-contact-store.md) [V]
* Apple, [CXCallObserver](https://developer.apple.com/documentation/callkit/cxcallobserver.md) [V]
* Apple, [Configuring background execution modes](https://developer.apple.com/documentation/xcode/configuring-background-execution-modes.md) [V]
* Apple, [MessageComposer sample](https://developer.apple.com/library/archive/samplecode/MessageComposer/Listings/MessageComposerViewController_m.html) [V]
* Apple Developer Forums, [MusicKit sample program with free developer account](https://developer.apple.com/forums/thread/706861) [V]
* Apple, [Choosing a Membership](https://developer.apple.com/support/compare-memberships) [V for Personal Team limits; its per-capability table was not on that page]
* CarScanner, [Configuring Bluetooth 4.0 (LE) connection on iPhone/iPad](https://www.carscanner.info/?p=69) [V, vendor help page]
