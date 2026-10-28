# Connecting Spotify

The **Music** screen is a small Spotify client. It shows what the Spotify app is playing and sends it play, pause, next, previous, seek, shuffle and repeat. It lists your playlists and Liked Songs, searches Spotify, shows the queue, lets you pick which device plays, and has a heart that likes the current song. It does all of this through Spotify's Web API, signed in as you. Spotify keeps playing the sound in its own app. Cabin Dash is a remote control and a library browser, not a music player.

**What it cannot do:** play music itself, work without the Spotify app already running on a device (**Open Spotify** is the way back to it), list the songs of a playlist you neither own nor collaborate on (Spotify's rule since February 2026; you can still play it), show more than 10 search results of each kind, or reorder or remove things in the queue. There is no Browse tab and no artist pages. The other rules Spotify sets are in `docs/SPOTIFY-RULES.md`.

**Status:** signing in, and the Music widget on Home, were confirmed working on your iPhone on 27 Oct 2026. The playlist, Liked, Search, Queue, device and like screens have never talked to Spotify: their parsing of Spotify's answers has unit tests, and the app compiles, but the first real check is you. The rules below were checked against Spotify's own pages on 27 Oct 2026. The exact wording and layout of the dashboard form was not, so it may differ a little from the steps.

## If you connected before Phase 2: connect once more

Spotify fixes the permissions when you sign in, and Phase 2 needs more than before. Cabin Dash notices this by itself: after you install the new build, the Music screen says **Connect Spotify again**. Tap it and press **Agree** on Spotify's page. You only do this once. The permissions it asks for:

| Permission | Used for |
|---|---|
| See and control playback (3 permissions) | What is playing, play and pause, skip, seek, shuffle, repeat, the queue, and the device list. |
| Read your private and collaborative playlists | Your playlists, and the songs in the ones you own. |
| Read your Liked Songs | The Liked section and the heart's lit state. |
| Add and remove Liked Songs | The heart. |

Cabin Dash does not ask to change your playlists or to follow anyone.

## What you need

* A **Spotify Premium** account. Spotify only lets Premium accounts control playback through the Web API.
* A free Spotify developer app, which you make yourself. It takes about five minutes. It is how Spotify knows which app is asking.

**Checked on 27 Oct 2026 against Spotify's pages:** every development-mode app needs its **owner** to have an active Premium subscription (if it lapses, the app stops working until it is renewed), and a new app allows **5 users**. Redirect addresses with a custom scheme, such as `cabindash://`, are still supported, and a redirect address must match the one in the dashboard exactly. Rules change, so check the dashboard for the current terms.

## Step by step (all in a browser on your PC)

1. Go to **developer.spotify.com/dashboard** and sign in with the Spotify account you listen with.
2. **Create app.**
   * App name: `Cabin Dash` (anything).
   * Description: anything.
   * **Redirect URI:** type exactly `cabindash://spotify-callback` and press **Add**. It must match to the letter, or Spotify refuses to sign you in. (Spotify's own page lists only the name, description and terms on the create dialog and puts redirect addresses under **Edit Settings**. If your create form has no Redirect URI field, create the app first and add it in the app's **Settings**.)
   * If it asks which API/SDKs you plan to use: tick **Web API** only. Do not tick **iOS**, and leave any **Bundle IDs** field empty. Cabin Dash signs in through Apple's in-app web sheet and talks to the Web API. It does not use Spotify's iOS SDK (that one needs the Spotify app open and a Bundle ID), so nothing in the app reads those settings. Spotify's pages don't describe this selector, so if your form shows something that doesn't match, tell me what it says rather than guessing.
   * Accept the terms and **Save**.
3. Open the app's **Settings**. Copy the **Client ID**. (It is a public identifier, not a password. You do not need the Client Secret and should not use it.)
4. If the app has a **User Management** tab, add yourself: your name and the email address of your Spotify account. In development mode Spotify limits who can sign in, and its pages do not say whether the owner is added automatically. Adding yourself does no harm.
5. In your GitHub repository: **Settings > Secrets and variables > Actions > Variables tab > New repository variable.**
   * Name: `SPOTIFY_CLIENT_ID`
   * Value: the Client ID from step 3.
   * (It goes under **Variables**, not Secrets. The workflow reads it as a variable, and the Client ID is not secret.)
6. Build a new copy: **Actions > Unsigned IPA (manual) > Run workflow.** Download the artifact, and install it with iLoader as before. The Client ID is baked into that build; a build made before you set the variable has Spotify switched off.
7. On the iPhone: open Cabin Dash, tap **Music** in the dock (the music-note button), then **Connect Spotify.** Spotify's own page opens in a sheet. Sign in and press **Agree.** You land back in Cabin Dash.
8. Start a song in the Spotify app. Go back to Cabin Dash. Music shows it, the Home screen's music widget shows it, and the buttons work. From then on you can start things from Cabin Dash itself (**Playlists**, **Liked**, **Search**). Keep the Spotify app running in the background on the iPhone: it is what makes the sound.

## If something goes wrong

| What Cabin Dash says | What it means |
|---|---|
| **Spotify isn't set up in this build** | The build has no Client ID. Do step 5 and build again. |
| The Spotify sign-in page says **INVALID_CLIENT** or complains about the redirect | The Client ID is wrong, or the redirect URI in the dashboard is not exactly `cabindash://spotify-callback`. |
| **Spotify refused the request** | Your account is not listed under User Management for that app (step 4), or the app is over the development-mode limits. |
| **Spotify only lets Premium accounts control playback** | The account is not Premium. |
| **Open Spotify and start playing something** | Spotify has no active device. Play something in the Spotify app, then try again. |
| **Spotify has no device ready to play** (with a **Devices** button) | Spotify knows no device to play on. Tap **Devices**. If this iPhone is not in the list, tap **This iPhone**, which opens Spotify; come back to Cabin Dash and the iPhone appears in the list. Tap the device you want, then pick something to play. Cabin Dash never chooses a device for you; once you have picked one, it plays there when Spotify has no active device. |
| **Connect Spotify again** | You signed in before Phase 2 added permissions. Tap it and press **Agree** once. |
| A playlist says Spotify only lets Cabin Dash list tracks in playlists you own | Spotify's rule for development-mode apps. Play and Shuffle still work. |
| The heart is dim | Cabin Dash has not heard yet whether the song is in your Liked Songs. Tapping it asks again. |
| Search is switched off, with a lock | The car is moving. Typing is blocked above about 8 km/h. **Passenger mode** in Settings turns this off. |
| Signs in, then asks again after you reopen Cabin Dash | The iPhone's Keychain refused to store the sign-in. Some sideloaded installs do that. Nothing else is affected. |

To disconnect: **Settings > Spotify > Disconnect.** To take back access completely, remove Cabin Dash from your Spotify account's **Apps** page.

## What Cabin Dash stores and sends

* The sign-in tokens go in the iPhone's Keychain, on that phone only. They are never written to the repository, the logs or any server of mine.
* While the app is on screen it asks Spotify what is playing every few seconds (faster on the Music screen). Opening Playlists, Liked, Search, Queue or Devices asks Spotify for those lists, and what you type in Search is sent to Spotify to find results. It sends nothing else about you anywhere. Likes live in Spotify, not on the phone. Spotify's logo is not bundled yet: see `docs/SPOTIFY-RULES.md` for how to add it.
* The Client ID is in the app you build, where anyone who can read the app file could find it. That is normal for this kind of sign-in (it is designed for apps that cannot keep a secret), and it is why no Client Secret is used.
