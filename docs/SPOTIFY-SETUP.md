# Connecting Spotify

The **Music** screen shows what the Spotify app is playing and sends it play, pause, next, previous and seek. It does this through Spotify's Web API, signed in as you. Spotify keeps playing in its own app. Cabin Dash is a remote control and a display, not a music player.

**What it cannot do:** browse your playlists or search Spotify (the **Spotify** tile opens the real app for that), play music itself, or work without the Spotify app already running on a device.

**Status: not tested.** The sign-in and playback code has been written and its pure parts (the sign-in maths, the reading of Spotify's answers) have unit tests. It has never talked to Spotify. The first real check is you, on your iPhone. The rules below were checked against Spotify's own pages on 27 Oct 2026. The exact wording and layout of the dashboard form was not, so it may differ a little from the steps.

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
   * If it asks which API/SDKs you plan to use: tick **Web API**.
   * Accept the terms and **Save**.
3. Open the app's **Settings**. Copy the **Client ID**. (It is a public identifier, not a password. You do not need the Client Secret and should not use it.)
4. If the app has a **User Management** tab, add yourself: your name and the email address of your Spotify account. In development mode Spotify limits who can sign in, and its pages do not say whether the owner is added automatically. Adding yourself does no harm.
5. In your GitHub repository: **Settings > Secrets and variables > Actions > Variables tab > New repository variable.**
   * Name: `SPOTIFY_CLIENT_ID`
   * Value: the Client ID from step 3.
   * (It goes under **Variables**, not Secrets. The workflow reads it as a variable, and the Client ID is not secret.)
6. Build a new copy: **Actions > Unsigned IPA (manual) > Run workflow.** Download the artifact, and install it with iLoader as before. The Client ID is baked into that build; a build made before you set the variable has Spotify switched off.
7. On the iPhone: open Cabin Dash, tap **Music** in the dock (the music-note button), then **Connect Spotify.** Spotify's own page opens in a sheet. Sign in and press **Agree.** You land back in Cabin Dash.
8. Start a song in the Spotify app. Go back to Cabin Dash. Music shows it, the Home screen's music widget shows it, and the buttons work.

## If something goes wrong

| What Cabin Dash says | What it means |
|---|---|
| **Spotify isn't set up in this build** | The build has no Client ID. Do step 5 and build again. |
| The Spotify sign-in page says **INVALID_CLIENT** or complains about the redirect | The Client ID is wrong, or the redirect URI in the dashboard is not exactly `cabindash://spotify-callback`. |
| **Spotify refused the request** | Your account is not listed under User Management for that app (step 4), or the app is over the development-mode limits. |
| **Spotify only lets Premium accounts control playback** | The account is not Premium. |
| **Open Spotify and start playing something** | Spotify has no active device. Play something in the Spotify app, then try again. |
| Signs in, then asks again after you reopen Cabin Dash | The iPhone's Keychain refused to store the sign-in. Some sideloaded installs do that. Nothing else is affected. |

To disconnect: **Settings > Spotify > Disconnect.** To take back access completely, remove Cabin Dash from your Spotify account's **Apps** page.

## What Cabin Dash stores and sends

* The sign-in tokens go in the iPhone's Keychain, on that phone only. They are never written to the repository, the logs or any server of mine.
* While the app is on screen it asks Spotify what is playing every few seconds (faster on the Music screen). It sends nothing else about you anywhere. It does not use the Spotify logo.
* The Client ID is in the app you build, where anyone who can read the app file could find it. That is normal for this kind of sign-in (it is designed for apps that cannot keep a secret), and it is why no Client Secret is used.
