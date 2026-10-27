# Spotify's rules, and where Cabin Dash stands

Cabin Dash shows Spotify's music inside its own screens, so Spotify's developer terms and design guidelines apply to it. This page lists what Cabin Dash follows and the places where it knowingly does not. It was checked against Spotify's pages on **27 Oct 2026**. Spotify changes these without notice, so read the current versions before sharing the app with anyone:

* Design guidelines: developer.spotify.com/documentation/design
* Developer terms: developer.spotify.com/terms

Cabin Dash is a personal app sideloaded to one iPhone, signed in as its owner in a Spotify development-mode app. It is not on the App Store and is not offered to the public. Nothing here has been reviewed by Spotify.

## Guidelines Cabin Dash follows

These four are from Spotify's design guidelines as read on 27 Oct 2026.

| Guideline | What Cabin Dash does |
|---|---|
| Say where the content comes from | The Music screen always shows the Spotify name next to the link back (Spotify's icon instead of the word, once it is added; see the first gap below). |
| Link back with the wording **Open Spotify** | The button says exactly that. It opens the current track, or the album or playlist, in the Spotify app, and Spotify's home when nothing is playing. If the app is not installed it opens Spotify's web page. |
| Show cover art unaltered, with rounded corners | Album and playlist pictures are drawn as received: not recoloured, covered by text or given another shape. Corners are 8 pt on the large Now Playing picture and 4 pt on list thumbnails. The plain tile shown when a picture is missing does not imitate Spotify's art. |
| A like must go to Spotify | The heart on Now Playing adds or removes the song in your Spotify Liked Songs through Spotify's API. Cabin Dash stores no likes of its own, only a short-lived copy in memory while the app is open. |

## Cabin Dash's own practice

These are how the app behaves, not rules quoted from Spotify.

* It never plays audio. It steers the Spotify app, which plays the sound.
* Playlists, Liked Songs, the queue and devices are read for the person who signed in, shown to them, and sent nowhere else.
* Sign-in tokens live in the iPhone's Keychain. The Client ID is public by design (PKCE sign-in) and no Client Secret is used or stored.
* Search asks for 10 results of each kind, the current development-mode maximum. Songs of a playlist are listed only for playlists you own or collaborate on, as Spotify now requires. The app pauses its requests when Spotify answers "too many requests".
* It does not say it is made or endorsed by Spotify.

## Where Cabin Dash knowingly falls short of the guidelines

These are real gaps, not wording.

1. **Spotify's logo or icon is not bundled yet.** The guidelines want Spotify's own artwork next to its content, never a redrawn one. The artwork can only be taken from Spotify's guidelines page, and the environment this app is built in cannot download it. Until the icon is added, Cabin Dash writes the plain word "Spotify" and draws nothing that resembles the logo. To add it: download the icon (a PNG, at least 21 px square) from the guidelines page, then run `python3 scripts/add_spotify_icon.py path/to/the-icon.png` and commit the new `SpotifyIcon.imageset` folder. The next build shows it automatically. The script copies the file and does not alter it.
2. **The progress bar can be dragged to seek.** The guidelines describe the playback progress as information. Cabin Dash lets you tap or drag it to jump around in the song, which is a control. Drag-to-seek is turned off when Spotify says the current item cannot be seeked (some ads and podcasts).
3. **Lists can show more than 20 items.** The guidelines ask for no more than 20 items in a list without paging. Playlists and Liked Songs load a page at a time and keep scrolling, so a long list can run well past 20 rows.
## What changed in Spotify's API that shaped this

Spotify tightened development-mode apps in February 2026. As checked on 27 Oct 2026: search returns at most 10 results per type; the songs of a playlist can be listed only when you own it or it is collaborative; the "save, remove and check" calls for your library moved to a single `/v1/me/library` family; and the owner of a development-mode app needs an active Premium subscription. If Spotify relaxes or tightens these, the app's limits change with them.

## What has not been verified

What this page says about Spotify's rules comes from reading Spotify's public pages. I have not read every clause of the developer terms, so this is not a full compliance check, and Spotify has not confirmed any of it. How each screen looks and behaves against a real account has not been seen on a phone yet. See the Phase 2 section of `docs/AUDIT.md`.
