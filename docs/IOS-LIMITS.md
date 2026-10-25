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
| **Permission denied or restricted** | No crash. The Drive screen shows a card explaining that location is off, with a button that opens iOS Settings. The Apps screen keeps working. |
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

`Keep screen on` (default on) sets iOS's idle timer to off while the app is on screen, which stops auto-lock and screen dimming. It is applied when the app returns to the screen and when you change the setting. It only works while Cabin Dash is the app in front; after you leave, iOS goes back to normal. It drains the battery noticeably, so a charging cable is the practical way to use it in a car. Low Power Mode and Screen Time limits were not tested.

## 6. Landscape and the dock

Portrait puts the dock along the bottom; landscape (screen wider than 1.25× its height) moves it to a 92 pt column on the left. Both landscape directions are enabled, and upside-down is not (normal for iPhones). The content stays inside the safe area, so the Dynamic Island and the rounded corners should not cover it.

**This has not been looked at on a real screen or simulator.** The cloud build saves a portrait screenshot after launching (`launch-portrait.png`), but nothing rotates the simulator. The first time you run the app on a phone, turn it sideways and check: the dock column, the two Drive gauges, and the app grid on a small iPhone (SE-sized screens are the likely problem).

## 7. What a simulator build cannot show

The GitHub build runs on a simulator with a pretend location. It cannot show: real GPS speed, how installed-app detection behaves when real apps are present (a simulator has no Spotify), whether the guessed link types are right, or anything about signing and installing. Those can only be checked on your iPhone.
