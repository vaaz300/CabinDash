# Spotify's rules, and where Cabin Dash stands

Cabin Dash shows Spotify's music inside its own screens, so Spotify's developer terms and design guidelines apply to it. This page lists what Cabin Dash follows and the places where it knowingly does not. It was checked against Spotify's pages on **27 Oct 2026**. Spotify changes these without notice, so read the current versions before sharing the app with anyone:

* Design guidelines: developer.spotify.com/documentation/design
* Developer terms: developer.spotify.com/terms

Cabin Dash is a personal app sideloaded to one iPhone, signed in as its owner in a Spotify development-mode app. It is not on the App Store and is not offered to the public. Nothing here has been reviewed by Spotify.

## Guidelines Cabin Dash follows

These are from Spotify's design guidelines as read on 27 Oct 2026; the logo rules were checked again on 29 Oct 2026.

| Guideline | What Cabin Dash does |
|---|---|
| Say where the content comes from | The Music screen shows Spotify's icon next to the link back. It is Spotify's own white icon from its design page, unchanged, at 24 pt (the minimum is 21 px); white because the Music screen is dark and Spotify allows its green icon only on black or white. |
| Use Spotify's artwork as supplied | Spotify's files (icon in green and white, and its like icons) were supplied from Spotify's design page and are copied into the asset catalogue unchanged by `scripts/add_spotify_icon.py`: not resized, recoloured or redrawn. Without them the app falls back to the word "Spotify", a heart and a music note. |
| Green icon only on black or white, with clear space | The Music button in the dock is Spotify's green icon on a black tile. The icon is half the tile, which leaves clear space of half its height on every side, as the guidelines ask. |
| Link back with the wording **Open Spotify** | The button says exactly that. It opens the current track, or the album or playlist, in the Spotify app, and Spotify's home when nothing is playing. If the app is not installed it opens Spotify's web page. |
| Show cover art unaltered, with rounded corners | Album and playlist pictures are drawn as received: not recoloured, covered by text or given another shape. Corners are 8 pt on the large Now Playing picture and 4 pt on list thumbnails. The plain tile shown when a picture is missing does not imitate Spotify's art. |
| A like must go to Spotify | The like button on Now Playing (Spotify's own "add" and green "added" icons) adds or removes the song in your Spotify Liked Songs through Spotify's API. Cabin Dash stores no likes of its own, only a short-lived copy in memory while the app is open. |

## Cabin Dash's own practice

These are how the app behaves, not rules quoted from Spotify.

* It never plays audio. It steers the Spotify app, which plays the sound.
* It uses Spotify's iOS SDK (version 5.0.1, from Spotify's own repository) to play and steer music on this iPhone: `authorizeAndPlayURI` to start the Spotify app and return, the App Remote connection for play, pause, skip, seek, shuffle, repeat and the queue, its player state for Now Playing, and its content calls to play a playlist, album or Liked Songs from a given song. Album pictures come from the Web API's catalogue. Spotify's SDK terms limit such apps to non-commercial use and forbid changing, syncing or broadcasting the audio; Cabin Dash does none of those.
* Playlists, Liked Songs, the queue and devices are read for the person who signed in, shown to them, and sent nowhere else.
* Sign-in tokens live in the iPhone's Keychain. The Client ID is public by design (PKCE sign-in) and no Client Secret is used or stored.
* Search asks for 10 results of each kind, the current development-mode maximum. Songs of a playlist are listed only for playlists you own or collaborate on, as Spotify now requires. The app pauses its requests when Spotify answers "too many requests".
* It does not say it is made or endorsed by Spotify.

## Where Cabin Dash knowingly falls short of the guidelines

These are real gaps, not wording.

1. **The progress bar can be dragged to seek.** The guidelines describe the playback progress as information. Cabin Dash lets you tap or drag it to jump around in the song, which is a control. Drag-to-seek is turned off when Spotify says the current item cannot be seeked (some ads and podcasts).
2. **Lists can show more than 20 items.** The guidelines ask for no more than 20 items in a list without paging. Playlists and Liked Songs load a page at a time and keep scrolling, so a long list can run well past 20 rows.
## What changed in Spotify's API that shaped this

Spotify tightened development-mode apps in February 2026. As checked on 27 Oct 2026: search returns at most 10 results per type; the songs of a playlist can be listed only when you own it or it is collaborative; the "save, remove and check" calls for your library moved to a single `/v1/me/library` family; and the owner of a development-mode app needs an active Premium subscription. If Spotify relaxes or tightens these, the app's limits change with them.

## What has not been verified

What this page says about Spotify's rules comes from reading Spotify's public pages. I have not read every clause of the developer terms, so this is not a full compliance check, and Spotify has not confirmed any of it. How each screen looks and behaves against a real account has not been seen on a phone yet. See the Phase 2 section of `docs/AUDIT.md`.
