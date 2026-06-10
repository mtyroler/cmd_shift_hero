# Command Shift Hero

> Guitar Hero, but the instrument is your keyboard. ⌘⇧🎸

Pick any song from your Apple Music library. Notes fall toward a glowing on-screen keyboard. You play the song by typing in rhythm — any letter key is fair game.

**Shift** activates star power. **Cmd+Shift** triggers the finisher.

---

## The trick

Apple Music audio is DRM-protected and no official API exposes raw samples. So this app does something sneaky:

```
1. Tell Music.app to play your track via AppleScript
2. Tap the process audio with a Core Audio process tap  ← the sneaky part
3. Mute Music.app's real output (the tap owns it now)
4. Analyze the captured PCM in real time: FFT → spectral flux → note chart
5. Replay the same audio through the game, delayed ~2.5 s
   └─ that delay is the lookahead — notes appear before you hear them
```

First play generates the chart live. The analysis is cached, so every replay gets a complete, refined chart from beat zero.

---

## Building

Requires macOS 15+, Apple Silicon, and Swift 6.2. No Xcode, no paid developer account — Command Line Tools are enough.

```sh
# Fast inner loop (build + test)
swift build && swift test

# Assemble the .app bundle, ad-hoc sign, and launch
Scripts/run.sh
```

TCC permissions (audio capture, Apple Events, media library) only kick in when launching the real bundle via `Scripts/run.sh`, not the bare binary. If permission prompts get stuck after a rebuild, `Scripts/reset-tcc.sh` clears them.

---

## Architecture

Six modules, clean dependency flow:

```
GameCore          pure logic — notes, judging, key mapping, scoring
AudioAnalysis  →  STFT + spectral-flux onset detection, chart gen, cache
GameScene      →  SpriteKit: note highway, keyboard, HUD, effects
MusicBridge       iTunesLibrary enumeration + AppleScript playback control
TapCapture     →  Core Audio process tap, lock-free ring buffer, delayed playback
CommandShiftHero  SwiftUI shell — ties everything together
```

The note highway position of every note is derived entirely from one clock (`audibleSongTime`). No accumulated deltas, no drift.

---

## How it actually feels

Your whole keyboard lights up. Low frequencies map to the bottom rows, highs to the top. A driving kick pattern becomes a floor-level stomp; a bright synth lead runs across the number row. Every song plays differently.
