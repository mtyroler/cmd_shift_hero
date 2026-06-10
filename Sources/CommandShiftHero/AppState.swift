import AVFAudio
import AppKit
import AudioAnalysis
import Foundation
import GameCore
import GameScene
import MusicBridge
import Observation
import TapCapture
import os

enum Screen {
    case menu
    case game
    case results
    case calibration
    case library
}

@Observable
final class AppState {
    private static let log = Logger(subsystem: "com.maxtyroler.csh", category: "AppState")
    private static let calibrationKey = "csh.calibrationOffset"

    var screen: Screen = .menu
    var isAnalyzing = false
    var isPaused = false
    var lastError: String?
    var difficulty: Difficulty = .normal

    enum PlaybackMode {
        case localFile
        case musicTap
    }

    private(set) var mode: PlaybackMode = .localFile
    private(set) var player: DelayedPlayer?
    private(set) var session: GameSession?
    private(set) var finalScore: ScoreState?
    /// Low-band energy of the current song, sampled by the backdrop.
    private(set) var energyEnvelope: EnergyEnvelope?

    /// Music-tap mode (M5+).
    private var tap: ProcessTapController?
    private(set) var currentTrack: LibraryTrack?
    private(set) var analysisRing: AudioRingBuffer?
    private var liveAnalyzer: LiveAnalyzer?
    private var cachedAnalysis: CachedAnalysis?
    private var audioStartOffset: Double?
    static let tapDelaySeconds = 2.5

    /// Kept for instant restart without re-analysis.
    private var currentChart: Chart?
    private var currentURL: URL?
    private var localFileDuration: Double?

    var calibrationOffset: Double {
        get { UserDefaults.standard.double(forKey: Self.calibrationKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.calibrationKey) }
    }

    // MARK: - Demo / local-file flow

    func startDemo() {
        guard !isAnalyzing else { return }
        guard let url = Bundle.module.url(forResource: "demo", withExtension: "m4a") else {
            lastError = "demo.m4a missing from bundle"
            return
        }
        isAnalyzing = true
        lastError = nil
        let difficulty = self.difficulty
        let energy = EnergyEnvelope()

        Task {
            do {
                let chart = try await Task.detached(priority: .userInitiated) {
                    try OfflineAnalyzer.analyze(url: url, difficulty: difficulty, energy: energy)
                }.value
                self.energyEnvelope = energy
                self.currentChart = chart
                self.currentURL = url
                try self.startPlayback(chart: chart, url: url)
                Self.log.info("demo started: \(chart.notes.count) notes, \(difficulty.rawValue)")
            } catch {
                Self.log.error("startDemo failed: \(error.localizedDescription)")
                self.lastError = error.localizedDescription
            }
            self.isAnalyzing = false
        }
    }

    func restartGame() {
        switch mode {
        case .musicTap:
            guard let track = currentTrack else { return }
            teardownPlayback()
            startMusicTrack(track)
        case .localFile:
            guard let chart = currentChart, let url = currentURL else { return }
            player?.stop()
            do {
                try startPlayback(chart: chart, url: url)
            } catch {
                lastError = error.localizedDescription
                screen = .menu
            }
        }
    }

    private func startPlayback(chart: Chart, url: URL) throws {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: true)
        localFileDuration = Double(file.length) / file.processingFormat.sampleRate
        let player = DelayedPlayer(
            sampleRate: file.processingFormat.sampleRate,
            channels: Int(file.processingFormat.channelCount),
            delaySeconds: 0.3 // small prefill so playback never starves the feeder
        )
        player.calibrationOffset = calibrationOffset
        player.startFeeding(file: file)
        try player.start()

        session = GameSession(chart: chart)
        self.player = player
        mode = .localFile
        isPaused = false
        finalScore = nil
        screen = .game
    }

    // MARK: - Music-tap flow (M5)

    /// The headline path: tap Music.app, mute it, analyze the real song,
    /// replay it 2.5 s delayed for note lookahead.
    func startMusicTrack(_ track: LibraryTrack) {
        stopPreview()
        lastError = nil
        libraryError = nil
        Task {
            do {
                try musicRemote.launch()
                let pid = try await musicPID()

                let tap = ProcessTapController()
                let format = try tap.activate(pid: pid) // first run: audio-capture TCC prompt

                let player = DelayedPlayer(
                    sampleRate: format.sampleRate,
                    channels: format.channels,
                    delaySeconds: Self.tapDelaySeconds,
                    bufferSeconds: 30
                )
                player.calibrationOffset = calibrationOffset

                // Second ring so live analysis (M6) reads the same capture
                // independently of the playback cursor.
                let analysisRing = AudioRingBuffer(
                    capacityFrames: Int(30 * format.sampleRate),
                    channels: format.channels
                )

                // Cached analysis from a previous play → full chart from
                // beat zero; otherwise the chart builds live as we listen.
                let cached = ChartCache.load(trackID: track.persistentIDHex)
                let session = GameSession(chart: Chart(notes: []))
                let difficulty = self.difficulty
                let energy = EnergyEnvelope()

                let analyzer = LiveAnalyzer(
                    ring: analysisRing,
                    sampleRate: format.sampleRate,
                    channels: format.channels,
                    difficulty: difficulty,
                    emitNotes: cached == nil,
                    energy: energy,
                    onAudioStart: { [weak self] t0 in
                        guard let self else { return }
                        self.audioStartOffset = t0
                        if let cached = self.cachedAnalysis {
                            // Shift cache-relative times onto this play's
                            // capture timeline.
                            let chart = ChartCache.chart(from: cached, difficulty: difficulty)
                            self.session?.loadChart(chart, timeOffset: t0)
                            Self.log.info("cached chart loaded: \(chart.notes.count) notes, offset \(t0)s")
                        }
                    },
                    onNote: { [weak self] note in
                        self?.session?.appendNote(note)
                    }
                )

                try tap.startCapture(into: [player.ring, analysisRing])
                try await musicRemote.play(persistentIDHex: track.persistentIDHex,
                                           title: track.title, artist: track.artist)
                try player.start()
                analyzer.start()

                self.tap = tap
                self.player = player
                self.analysisRing = analysisRing
                self.currentTrack = track
                self.session = session
                self.energyEnvelope = energy
                self.cachedAnalysis = cached
                self.audioStartOffset = nil
                self.liveAnalyzer = analyzer
                self.mode = .musicTap
                self.isPaused = false
                self.finalScore = nil
                self.screen = .game
                Self.log.info("tap game started: \(track.title) @ \(format.sampleRate)Hz, cache=\(cached != nil)")
            } catch {
                Self.log.error("startMusicTrack failed: \(error.localizedDescription)")
                self.teardownPlayback()
                self.libraryError = error.localizedDescription
                self.screen = .library
            }
        }
    }

    private func musicPID() async throws -> pid_t {
        for _ in 0..<20 {
            if let app = NSRunningApplication
                .runningApplications(withBundleIdentifier: "com.apple.Music").first {
                return app.processIdentifier
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw TapError.processNotRunning("com.apple.Music")
    }

    /// Metadata for the in-game HUD: title, artist, duration, artwork.
    var songHUDInfo: SongHUDInfo? {
        switch mode {
        case .musicTap:
            guard let track = currentTrack else { return nil }
            return SongHUDInfo(title: track.title, artist: track.artist,
                               duration: track.duration, artwork: artwork(for: track))
        case .localFile:
            return SongHUDInfo(title: "DEMO TRACK", artist: "built-in",
                               duration: localFileDuration, artwork: nil)
        }
    }

    /// Song-end check, polled by the game container.
    func checkSongEnd() {
        guard !isPaused, screen == .game else { return }
        switch mode {
        case .localFile:
            if player?.isDrained == true { finishGame() }
        case .musicTap:
            // We never read Music's player position; the audible clock plus
            // the library-reported duration decides when the song is over.
            if let track = currentTrack, let player,
               player.audibleSongTime > track.duration + 0.5 {
                finishGame()
            }
        }
    }

    private func teardownPlayback() {
        // Persist this play's analysis before tearing anything down.
        if mode == .musicTap, let analyzer = liveAnalyzer, let track = currentTrack {
            analyzer.stop()
            let onsets = analyzer.snapshotNormalizedOnsets()
            if onsets.count > 10 {
                let merged = ChartCache.merge(
                    existing: cachedAnalysis,
                    newOnsets: onsets,
                    trackID: track.persistentIDHex,
                    duration: track.duration
                )
                ChartCache.save(merged)
            }
        }
        liveAnalyzer?.stop()
        liveAnalyzer = nil
        if mode == .musicTap { energyEnvelope = nil } // local-file envelope survives restarts
        cachedAnalysis = nil
        audioStartOffset = nil
        player?.stop()
        player = nil
        tap?.stop()
        tap = nil
        analysisRing = nil
        if mode == .musicTap {
            try? musicRemote.stop()
        }
        session = nil
        isPaused = false
    }

    // MARK: - Transport

    func pauseGame() {
        guard !isPaused else { return }
        player?.pause()
        if mode == .musicTap {
            try? musicRemote.pause()
        }
        isPaused = true
    }

    func resumeGame() {
        guard isPaused else { return }
        do {
            if mode == .musicTap {
                try musicRemote.resume()
            }
            try player?.resume()
            isPaused = false
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Song over: show results.
    func finishGame() {
        finalScore = session?.state
        teardownPlayback()
        screen = .results
    }

    // MARK: - Apple Music library (M4)

    private var library: MusicLibrary?
    private(set) var libraryTracks: [LibraryTrack] = []
    var libraryError: String?
    private(set) var previewTrack: LibraryTrack?
    private let musicRemote = MusicRemote()

    func openLibrary() {
        screen = .library
        guard library == nil else { return }
        Task {
            do {
                // ITLibrary init triggers the Media Library permission prompt.
                let library = try MusicLibrary()
                self.library = library
                self.libraryTracks = library.songs()
                Self.log.info("library loaded: \(self.libraryTracks.count) songs")
            } catch {
                Self.log.error("library load failed: \(error.localizedDescription)")
                self.libraryError = "Could not read your Music library — check " +
                    "System Settings → Privacy & Security → Media & Apple Music. (\(error.localizedDescription))"
            }
        }
    }

    func closeLibrary() {
        stopPreview()
        screen = .menu
    }

    /// Debug path: play the track audibly in Music.app (no tap).
    func previewInMusic(_ track: LibraryTrack) {
        Task {
            do {
                try await musicRemote.play(persistentIDHex: track.persistentIDHex,
                                           title: track.title, artist: track.artist)
                previewTrack = track
            } catch {
                libraryError = error.localizedDescription
            }
        }
    }

    func stopPreview() {
        guard previewTrack != nil else { return }
        try? musicRemote.stop()
        previewTrack = nil
    }

    func artwork(for track: LibraryTrack) -> NSImage? {
        library?.artwork(for: track.id)
    }

    /// Quit mid-song: straight back to the menu.
    func endGame() {
        teardownPlayback()
        screen = .menu
    }
}
