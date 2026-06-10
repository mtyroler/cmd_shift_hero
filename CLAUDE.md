# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
# Build, bundle, and launch the app
./Scripts/run.sh

# Build the .app bundle only (ad-hoc signed)
./Scripts/bundle.sh

# Run all tests
./Scripts/test.sh

# Run a single test target
./Scripts/test.sh GameCoreTests
./Scripts/test.sh AudioAnalysisTests
```

The project uses SwiftPM (no Xcode project). Direct `swift build` won't work — use the scripts, which handle framework search paths and app bundling. Tests use Swift Testing (`import Testing`), not XCTest.

Requires macOS 15+. At runtime the app needs three TCC permissions: Media & Apple Music, Apple Events (to control Music.app), and System Audio Recording.

## Architecture

Six library modules feeding into one executable target (`CommandShiftHero`):

```
GameCore        — pure logic, no UI/audio deps
AudioAnalysis   — STFT/onset detection, chart caching (→ GameCore)
GameScene       — SpriteKit rendering, MainActor (→ GameCore)
MusicBridge     — iTunes library access, AppleScript Music.app control
TapCapture      — Core Audio process tap, ring buffer, delayed playback (→ GameCore)
CommandShiftHero — SwiftUI shell, AppState orchestrator (→ all above)
```

### Core invariant: clock-driven rendering

Everything visual derives position from `GameClock.audibleSongTime`. `GameScene` never accumulates deltas. This is the main reason drifts and sync bugs are rare — any change that accumulates state off the clock will break sync.

### Two playback modes

**Local file mode**: `DelayedPlayer` reads an `AVAudioFile` on a feeder thread with a 2.5s lookahead delay. Used for the built-in demo track.

**Music-tap mode**: `ProcessTapController` installs a Core Audio process tap on Music.app, captures its PCM output into `AudioRingBuffer`, mutes the original process, then `DelayedPlayer` replays the captured audio with the same delay. `LiveAnalyzer` reads from the same ring buffer concurrently on a background thread to perform real-time analysis.

### Real-time analysis pipeline

`LiveAnalyzer` → `STFT` → `OnsetStream` → `ChartGenerator` → `Chart`

- `STFT` (Accelerate vDSP): streaming 512-bin FFT, Hann-windowed
- `OnsetStream`: per-band spectral-flux onset detection; also emits energy envelopes for sustained/ambient passages
- `ChartGenerator`: stateful onset-to-note mapper with playability constraints (density caps, column-jump limits, simultaneous-key limits per difficulty)
- `ChartCache`: persists onset data keyed by track ID; merges across plays; normalizes onset times relative to first non-silent sample

### Concurrency

- `AudioRingBuffer`: lock-free SPSC (atomic read/write counters, no mutex)
- `DelayedPlayer` render block: reads frame counters atomically, no locks on hot path
- `LiveAnalyzer`: `Mutex` wraps onset storage; all callbacks dispatched to main thread
- `AppState`: `@Observable`, drives all screen transitions and audio lifecycle from main thread
- `GameScene` and `CommandShiftHero` targets declare `defaultIsolation: MainActor`

### State machine

`AppState` is the single source of truth. It owns the `GameSession`, `ProcessTapController`, `DelayedPlayer`, and `LiveAnalyzer` instances and manages their lifecycle. Views observe `AppState` properties and call its methods — they don't own audio objects directly.

### Difficulty scaling

`Difficulty` enum controls allowed keyboard rows, note density cap, minimum note spacing, onset detection threshold, and maximum simultaneous keys. `ChartGenerator` enforces these constraints independently of the analysis backend, so difficulty is a pure post-processing step.
