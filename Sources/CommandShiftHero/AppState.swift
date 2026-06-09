import AVFAudio
import AppKit
import AudioAnalysis
import Foundation
import GameCore
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

    private(set) var player: DelayedPlayer?
    private(set) var session: GameSession?
    private(set) var finalScore: ScoreState?

    /// Kept for instant restart without re-analysis.
    private var currentChart: Chart?
    private var currentURL: URL?

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

        Task {
            do {
                let chart = try await Task.detached(priority: .userInitiated) {
                    try OfflineAnalyzer.analyze(url: url, difficulty: difficulty)
                }.value
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
        guard let chart = currentChart, let url = currentURL else { return }
        player?.stop()
        do {
            try startPlayback(chart: chart, url: url)
        } catch {
            lastError = error.localizedDescription
            screen = .menu
        }
    }

    private func startPlayback(chart: Chart, url: URL) throws {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: true)
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
        isPaused = false
        finalScore = nil
        screen = .game
    }

    // MARK: - Transport

    func pauseGame() {
        guard !isPaused else { return }
        player?.pause()
        isPaused = true
    }

    func resumeGame() {
        guard isPaused else { return }
        do {
            try player?.resume()
            isPaused = false
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Song drained: show results.
    func finishGame() {
        finalScore = session?.state
        player?.stop()
        player = nil
        session = nil
        isPaused = false
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

    /// M4 verification path: play the track in Music.app (audible for now —
    /// the tap pipeline mutes it from M5 on).
    func previewInMusic(_ track: LibraryTrack) {
        do {
            try musicRemote.play(persistentIDHex: track.persistentIDHex)
            previewTrack = track
        } catch {
            libraryError = error.localizedDescription
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
        player?.stop()
        player = nil
        session = nil
        isPaused = false
        screen = .menu
    }
}
