# What iOS allows, and what Cabin Dash does about it

Everything below was checked by reading the source. None of it has been run on a phone. Statements about how iOS behaves are from Apple's documented behaviour as I know it; I could not re-check Apple's documentation from the build environment, so treat them as the starting point for a test on your own iPhone, not as a guarantee.

## 1. Finding installed apps

**Cabin Dash cannot see which apps are on your iPhone. No app can.** iOS does not offer a list of installed apps to other apps. The only question an app may ask is "can something open this link?" (`canOpenURL`), and only for link types (URL schemes) the app declared in advance under `LSApplicationQueriesSchemes` in its Info.plist.

What Cabin Dash does with that:

* It asks about **30 link types**, one or more for each of the **37 apps** in its catalogue (`CabinCore/Sources/CabinCore/Catalog.swift`). `scripts/check_schemes.py` and the cloud build both check that this list and the Info.plist list are identical.
* iOS allows at most **50** declared link types per app, so the catalogue can grow by 20 more.
* It asks again every time the app comes back to the screen, so an app you install or delete is noticed on the next return.
* **Seven catalogue apps have no link type at all** (HERE WeGo, A Better Routeplanner, PlugShare, ChargePoint, Electrify America, EasyPark, CARROT Weather). They are never detected automatically. You add them by hand; they then open their website or App Store page, not the app.
* **Six link types are guesses** (SiriusXM, iHeartRadio, TuneIn, SpotHero, ChatGPT, Claude). If a guess is wrong, that app is simply not detected, and if you add it by hand its tile opens the website or App Store page instead.
* A link type only means "something on this phone handles it". Two apps can claim the same one. For Apple's own apps (`maps`, `music`, `podcasts`, `ibooks`) that is not a real concern; for third-party ones it is a small chance of the wrong app opening.
* **Any app that is not in the catalogue is not detected automatically.** That is a fixed limit of iOS, not something a later version can remove. The Add apps screen says so, and lets you add anything by name (App Store search), by website, or by typing an app's own link such as `myapp://`.

## 2. Opening an app, and when that fails

Tapping a tile runs `AppEntry.launchSequence`, in order, stopping at the first that iOS accepts:

1. the app's own link (`spotify://`), which opens the app if it is installed;
2. its website (`https://open.spotify.com/`), which opens the app instead when the app has registered that address with iOS ("universal link"), and Safari otherwise;
3. its App Store page, or an App Store search when there is no id.

If every step fails, a message at the bottom of the screen says "Couldn't open <app>". Because the tap path does not depend on detection, an app whose link type was guessed wrong still opens through step 2 or 3 when it is on the shelf.

Deleted since the last check: the app's link fails and the website or App Store page opens. An automatically detected tile disappears the next time you return to Cabin Dash; one you added by hand stays until you remove it.

Not handled: iOS may ask "Open in <app>?" for some links the first time. That is iOS's choice and cannot be turned off from the app.

## 3. Icons

**iOS does not let one app read another app's icon.** Cabin Dash gets each icon from the App Store's public lookup service instead, where every app has the same artwork. That has these consequences:

* **Only while Other apps is on.** The Dock, Home and Settings need no icons, so with Other apps off (the default) no lookups are made and nothing about your apps is sent to Apple.
* It needs internet. With no connection the tile shows a coloured letter (the app's initial on its category colour) until the next successful fetch.
* A hit is remembered for 30 days; a failed search is remembered for 1 day, so it is retried tomorrow.
* A result is accepted only when its name matches the app as a whole word (and, for Apple's own apps, the publisher matches too), so a wrong App Store id cannot put another app's icon on a tile.
* Name searches (apps without an id) are limited to 6 per pass, 1.2 seconds apart, to stay inside the service's rate limit. After a first launch, a few icons may arrive a minute or two later.
* The store is chosen from your iPhone's region and falls back to the US store.
* **Unverified here:** the App Store ids in the catalogue. They are checked for the icon at runtime, but not for the App Store page link (see `docs/AUDIT.md`).
* Websites you add by hand never get artwork; they show a globe.
* Settings has **Refresh icons** if something looks wrong.

## 4. Location, speed and the GPS

| Situation | What the code does |
|---|---|
| First launch | Asks for "While Using the App" permission once. No "Always" request. |
| **Permission denied or restricted** | No crash. The Drive screen shows a card explaining that location is off, with a button that opens iOS Settings. The home screen keeps working. |
| Location turned on later in Settings | Picked up the next time the app comes back to the screen. |
| Position readings with a negative accuracy, or older than 15 seconds | Ignored. |
| Poor accuracy (worse than 40 m) | The speed iOS reports is still shown, but the reading is not added to trip distance or trip time. |
| Speed unavailable from iOS | Worked out from the distance between two readings, only if they are under 10 seconds apart and accurate to 50 m. |
| Jumps (more than 70 m/s between readings), gaps of 15 s or more, and speeds under 1 m/s (about 3.6 km/h) | Not counted as driving. |
| Standing still (under 0.6 m/s) | Shows 0, which hides GPS jitter at traffic lights. |
| Tunnel or lost signal | After 5 seconds without a reading the speed drops to 0 and the Drive screen says "Finding GPS…"; the gap is not added to the trip. |
| Heading | Only updated above 1.5 m/s, because a stationary GPS has no real direction. The needle turns the short way across north. |
| Trip totals | Saved to the phone about every 15 seconds and when the app leaves the screen. Only the totals are stored (metres and seconds), never positions. |

**Known gaps (documented, not fixed):**

* **"Precise Location" switched off.** iOS then gives approximate positions only, which the tracker rejects. Speed and distance do not work and nothing on screen says why. A future version should read `accuracyAuthorization` and show a card, as it already does for denial. Until then: Settings > Privacy & Security > Location Services > Cabin Dash > Precise Location on.
* **Location tracking stops when Cabin Dash is not on screen.** It uses "While Using" access with no background mode. If you tap an app tile and Spotify takes over the screen, the trip distance does not count while you are in Spotify. That follows from the privacy choice (nothing is tracked in the background) and is the right default; a trip meter that runs in the background would need a different permission and review.
* Wi-Fi/cell positioning indoors, "mock locations" from developer tools, and Location Services being off for the whole phone have not been tested. Whether the last one is reported to the app as "denied" is untested.

## 5. Keep the screen on

`Keep screen on` (default on) sets iOS's idle timer to off while the app is on screen, which stops auto-lock and screen dimming. While a route is being followed on the Map screen the screen also stays on, whatever that setting says. It is applied when the app returns to the screen and when you change the setting. It only works while Cabin Dash is the app in front; after you leave, iOS goes back to normal. It drains the battery noticeably, so a charging cable is the practical way to use it in a car. Low Power Mode and Screen Time limits were not tested.

## 6. The layout

The app is **landscape only** (both directions; upside-down is not offered, which is normal for iPhones). A frosted dock runs down the left edge and is the same on every screen: the time, Wi-Fi or cellular, a GPS dot, the battery, then buttons for Home, Map, Music and Drive (and Apps, if Other apps is switched on in Settings), with Settings at the bottom. The buttons are sized to fit the screen height and never drop below 30 points; with Apps on, a small iPhone gets small buttons. The rest of the screen is the feature you are on. Content stays inside the safe area, so the Dynamic Island and rounded corners should not cover it. The Map screen is the one exception: the map itself runs under them.

The music and next-turn bars sit at the top right of every screen except the one that already shows that information. On the Map screen the music bar sits over the top of the map, and on a narrow phone it may overlap the place panel on the left. That has not been checked on a screen.

What it cannot copy from CarPlay:

* **No unread badges.** iOS gives an app no way to read another app's badge count, so Messages has none.
* **No signal bars.** iOS does not report cellular signal strength to apps. The rail shows whether the phone is on Wi-Fi, cellular or offline, and nothing it cannot know.
* **Apple's artwork.** Apple's icons for Phone, Messages, Music and the like are not on the App Store, and the wallpapers are Apple's. Those tiles and the ribbon wallpaper are original drawings in the same spirit. Icons of apps that are on the App Store (Spotify, Google Maps, Waze and so on) are fetched from it at runtime, as before.
* **Other apps' screens.** iOS has no way to show another app's screen or its live content inside Cabin Dash. Tapping Spotify or Google Maps opens that app and leaves Cabin Dash. That is why Map and Music are separate screens that Cabin Dash draws itself.
* **Phone and Messages.** Cabin Dash has no Phone or Messages screen yet. The optional Other apps screen has a Messages tile that opens `sms://`. It has no Phone tile: iOS has no public link that opens the Phone app, and the bare `tel://` the tile used opened iOS's Call prompt with no number in it (seen on a phone, 27 Oct 2026). A `tel:` link only works with a number, and iOS always asks "Call?" before dialling it. That prompt is iOS's own and cannot be skipped, so even the Phone screen planned for a later phase will show it once per call.

**None of this has been looked at on a screen.** The cloud build saves a screenshot after launching (`launch.png`), but a simulator has no GPS track, no Spotify and no Google Maps. When you first run it on a phone, check: the dock spacing on a small iPhone (SE-sized screens are the likely problem), the three Home widgets, and whether the top-right bars cover anything you need.

## 6a. The Map screen

* **The map is Apple Maps**, drawn by MapKit, with traffic on. **It is not Google Maps.** Google's own app cannot be embedded; there is a Google Maps SDK that could draw Google's map tiles inside Cabin Dash, but it needs a Google Cloud account with billing enabled and an API key, and its turn-by-turn product is not available to individuals. It has not been added.
* **Search and routes** use Apple Maps' search and directions (`MKLocalSearch`, `MKDirections`). The text you search for and the address of a saved place are sent to Apple to do that. Needs internet.
* **Turn-by-turn is basic.** The card shows the next instruction from Apple's route, and counts down the straight-line distance (not road distance, so it reads a little short on bends) to the point where that instruction applies. It advances when the phone is within 45 metres of that point. It never speaks. It does not reroute on its own: if you leave the route, tap **Reroute**. In a tunnel or with a poor GPS signal the card may lag or skip.
* **It only updates while Cabin Dash is on screen.** The app has no background-location permission, on purpose. Switch to another app and the card stops until you come back.
* **Open in Google Maps / Waze / Apple Maps** passes the destination's coordinates to the app chosen under Settings > Directions with. Google Maps and Waze use their own link when installed and their website otherwise. The coordinates come from Apple's search result, so the pin may differ slightly from what Google would pick for the same name.

## 6b. Spotify

See `docs/SPOTIFY-SETUP.md` and `docs/SPOTIFY-RULES.md`. In short: the Music screen browses your playlists and Liked Songs, searches, shows the queue and steers the Spotify app through Spotify's Web API. It needs Premium and your own Spotify developer app.

* **The audio plays in the Spotify app, not in Cabin Dash.** On this iPhone, Cabin Dash plays, shows and steers music through the Spotify app itself, with Spotify's iOS SDK. Spotify's web service is used for signing in, browsing, search, likes, and a TV or speaker you pick; it is not used to start or steer music on this phone, because the Spotify app in the background did not reliably answer it.
* **Spotify has to be awake, and only Spotify can wake itself.** When the Spotify app is asleep, a tap on Play opens it for a moment with the song you tapped, and Spotify comes back to Cabin Dash by itself. That still shows Spotify on screen briefly; nothing can start it invisibly. The first time, Spotify asks you to allow Cabin Dash. Spotify ends Cabin Dash's connection about 30 seconds after a pause, and Cabin Dash drops it when it leaves the screen; pressing Play after that opens Spotify for a moment again (Spotify's documented way back; iOS puts an app that has stopped playing to sleep, and only opening it wakes it). The paused song stays on screen meanwhile, with a note under the buttons, and Play opens Spotify at once instead of first trying to reconnect. Within an hour of the last time Spotify was opened this way, Cabin Dash reconnects by itself while Spotify is still awake, even after Cabin Dash was closed.
* **What plays after a tapped song.** A song in a playlist plays the playlist from that song, a song in Liked Songs plays Liked Songs from it, and a song from Search plays its album from it. Spotify's own list is used for that. Liked Songs has two addresses and both are tried; if the Spotify app accepts neither, or its list is in a different order from Cabin Dash's (another sort in the Spotify app), Cabin Dash plays the rest of the list itself, one song after another, with Next, Previous, shuffle and repeat all working. That backup needs Cabin Dash on screen to see each song end: with the phone locked or another app in front, Spotify plays its own picks after the song. When Spotify had to be opened first, the song starts on its own and then starts once more inside its playlist, album or Liked Songs. It needs the iOS SDK ticked and the app's Bundle ID entered in the Spotify dashboard (docs/SPOTIFY-SETUP.md).
* **A TV or speaker.** Tapping Play goes to a device you picked in the list, otherwise to this iPhone. It never picks a TV or speaker for you. The **This iPhone** row opens Spotify on the phone with your last song and makes the phone the default again.
* **Spotify's own limits apply** (development mode, as read on 27 Oct 2026): search returns 10 results per kind; the songs of a playlist can be listed only if you own it or it is collaborative; the queue can be read and added to, not edited.
* **Typing is locked while moving.** Search is switched off above about 8 km/h and comes back after 10 seconds below 4 km/h. The speed comes from the iPhone's GPS, so the lock can only engage when there is a GPS reading, and a lost signal never unlocks it by itself (it waits for a slow reading). Passenger mode turns the lock off.
* Progress is read every few seconds and moved forward locally in between, so the bar can be a second or two off.

## 7. What a simulator build cannot show

The GitHub build runs on a simulator with a pretend location. It cannot show: real GPS speed, how installed-app detection behaves when real apps are present (a simulator has no Spotify or Google Maps), whether the guessed link types are right, or anything about signing and installing. Those can only be checked on your iPhone.
