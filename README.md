# Command Shift Hero

Guitar Hero, but the instrument is your Mac keyboard. ⌘⇧🎸

Pick a song from your Apple Music library. Notes fall toward an on-screen keyboard —
any letter key can be a target — and you play the song by typing in rhythm.
**Shift** is star power. **Cmd+Shift** is the combo finisher.

## How it works (the interesting part)

Apple Music audio is DRM-protected and MusicKit never exposes raw samples, so this
app takes a different road:

1. You pick a track from your Music library (enumerated via `iTunesLibrary.framework`).
2. The app tells **Music.app** to play it (`NSAppleScript`, play by persistent ID).
3. A **Core Audio process tap** (`AudioHardwareCreateProcessTap`, macOS 14.4+)
   captures Music.app's decoded audio output — and *mutes* it (`.mutedWhenTapped`).
4. The captured audio is analyzed in real time (vDSP spectral-flux onset detection,
   frequency bands mapped to keyboard rows) to generate the note chart.
5. The same audio is replayed through the app's own output **~2.5 s delayed**.
   That delay is the note lookahead: the game knows the notes before you hear them.

First play of a song generates the chart live; the analysis is cached, so replays
get a refined, complete chart from beat zero.

## Building

Requires macOS 15+ (developed on 26.x), Apple Silicon, and Swift 6.2
(Command Line Tools are enough — no Xcode project, no paid developer account).

```sh
swift build && swift test   # fast inner loop
Scripts/run.sh              # assemble the .app bundle, ad-hoc sign, and launch
```

TCC permissions (audio capture, Apple Events, media library) require launching the
real bundle via `Scripts/run.sh`, not the bare binary. If permission prompts get
wedged after rebuilds, run `Scripts/reset-tcc.sh`.

## Layout

| Module | Purpose |
|---|---|
| `CommandShiftHero` | SwiftUI app shell: menu, library browser, game container |
| `GameCore` | Chart/notes, key mapping, master clock, judging, session state |
| `GameScene` | SpriteKit rendering: note highway, on-screen keyboard, effects |
| `AudioAnalysis` | STFT + spectral flux onset detection, chart generation, cache |
| `MusicBridge` | ITLibrary enumeration + AppleScript playback control |
| `TapCapture` | Core Audio process tap, lock-free ring buffer, delayed playback |
