# Changelog

Every IPA built by the **Unsigned IPA (manual)** workflow is a **beta**, numbered from that workflow's run number:
run 1 is Beta 0.1, run 10 is Beta 1.0, run 21 is Beta 2.1, run 22 is Beta 2.2. The build number is the run number.
A failed or cancelled run still uses up its number, so a number can be skipped. Full releases come later: one is made by
typing its version (for example 1.0) into the workflow's **release_version** box, and is listed here as **Release 1.0**.
Beta numbers are not release numbers, so the first full release can still be 1.0. How it works: README, "Versions".

From Beta 2.2 on, the version is written into the app (**Settings > About**: "Beta 2.2 (build 22)"), into the IPA's file
name (`CabinDash-beta-2.2.ipa`) and into the run's summary on GitHub, and each IPA is published as a GitHub release
(**Code > Releases**, tagged `beta-2.2`) that is kept until it is deleted. The "Next beta" section below is what the next
IPA will contain and becomes its release notes; after the run it is renamed after the beta it became. Betas 0.1 to 2.1 were numbered afterwards, from
their runs; inside the app they all say "1.0 (1)".

Each entry: what changed for you, the run and the commit it was built from. "Rebuilt" means the same code as the beta
before it. The details, including what was and was not checked, are in `docs/AUDIT.md`.

## Next beta (2.2, from the next IPA run)

- Version numbers: Settings > About says which beta (or release) and build this is; the IPA file and the artifact are named
  after it (`cabindash-beta-2.2`); this changelog and the README's "Versions" section.
- Every IPA is also published as a GitHub release (Code > Releases) with these notes, so it no longer disappears after
  7 days.
- The next-turn and now-playing bars moved from the top right to the bottom right of every screen, so each screen's own
  controls start at the top (on Music, the section tabs line up with the top of the dock).
- Green instead of orange everywhere the app highlights something: Music's tabs, shuffle and repeat when on, the like
  tick, buttons, the Drive gauge and toasts. At night it is Spotify's own green; by day a deeper green that reads on light.

## Beta 2.1 (run 21, 29 Oct 2026, `926f5ea`)

- The background behind Music is a smooth, dark frosted glass. Beta 2.0's blur showed as jagged, stepped bands.

## Beta 2.0 (run 20, 29 Oct 2026, `80f0b01`)

- New app icon: the CD mark flat on black, without the glass tile.
- Spotify's own artwork: its like and liked icons on Now Playing instead of the heart, its green icon on a black Music
  button in the dock, and its white icon beside "Open Spotify".
- A darker, blurred background behind Music.
- In Liked Songs, the shuffle button stays lit after skipping.

## Beta 1.9 (run 19, 29 Oct 2026, `0f856bc`)

- Liked Songs keeps going after the tapped song: both of Spotify's Liked Songs addresses are tried, and otherwise Cabin
  Dash plays the list itself, with skip, back, shuffle and repeat.
- After a long pause, Play opens Spotify at once, and Now Playing says it will.

## Beta 1.8 (run 18, 29 Oct 2026, `32b3b9d`)

- Music on this iPhone rebuilt around one channel, the Spotify app itself: a song tapped in a playlist plays the
  playlist from it, an album song from Search plays its album, shuffle, repeat, skip and seek read back from Spotify,
  and pausing keeps the song on screen instead of going blank.

## Beta 1.7 (run 17, 28 Oct 2026, `faeaa08`)

- After Spotify was opened, nothing more was sent through Spotify's web service. Known problems, fixed in 1.8: skip,
  shuffle and repeat were hit or miss, a pause blanked Now Playing, and a song in a playlist played on its own.

## Beta 1.6 (run 16, 28 Oct 2026, `2842c38`)

- "Starting playback" and "Opening Spotify" messages instead of a silent wait; Now Playing also read the Spotify app.
  Known problem, fixed in 1.7: a song could play for under a second and stop.

## Beta 1.5 (run 15, 28 Oct 2026, `6409d2e`)

- Cabin Dash connects to the Spotify app after opening it. Settings gained a **Spotify log**.

## Beta 1.4 (run 14, 28 Oct 2026, `b0a7fe7`)

- Play goes to this iPhone by itself, opening Spotify with the tapped song when it is not running.

## Beta 1.3 (run 13, 28 Oct 2026, `6a769f8`)

- Rebuilt.

## Beta 1.2 (run 12, 28 Oct 2026, `6a769f8`)

- Plays on the device you picked. **This iPhone** opens Spotify through Spotify's SDK and comes back by itself.

## Beta 1.1 (run 11, 28 Oct 2026, `2c1564b`)

- Cabin Dash never picks a speaker or TV for you; the device list gained a **This iPhone** row.

## Beta 1.0 (run 10, 28 Oct 2026, `b7eccf4`)

- Rebuilt.

## Beta 0.9 (run 9, 28 Oct 2026, `b7eccf4`)

- A roomier section bar on Music; the Settings title no longer overlaps its options.

## Beta 0.8 (run 8, 28 Oct 2026, `650bd21`)

- Music became a small Spotify client: Playlists, Liked Songs, Search, Queue, a device picker, a heart to like the song,
  shuffle and repeat. Search is locked while driving, with a Passenger mode in Settings.

## Beta 0.7 (run 7, 27 Oct 2026, `73ee1c9`)

- Rebuilt; only the Spotify setup guide changed.

## Beta 0.6 (run 6, 27 Oct 2026, `7569446`)

- Your artwork became the app icon. The Map follows your heading again when you come back to it.

## Beta 0.5 (run 5, 27 Oct 2026, `a77be37`)

- The Home map widget draws the route. The Phone tile left the Other apps screen.

## Beta 0.4 (run 4, 26 Oct 2026, `d4b37a7`)

- Home polished from your first screenshot: the clock fits, Maps attribution, the speed dial.

## Beta 0.3 (run 3, 26 Oct 2026, `9359bc1`)

- The dock with Home, Map, Music, Drive and Settings; live Home widgets; the playing song and next turn on every screen;
  an optional Other apps screen.

## Beta 0.2 (run 2, 26 Oct 2026, `c5b2c5c`)

- Rebuilt as a CarPlay-style screen with Maps and Spotify.

## Beta 0.1 (run 1, 25 Oct 2026, `c3deec9`)

- The first build.
