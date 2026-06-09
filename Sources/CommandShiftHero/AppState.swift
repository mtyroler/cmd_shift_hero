import AVFAudio
import AudioAnalysis
import Foundation
import GameCore
import Observation
import TapCapture
import os

enum Screen {
    case menu
    case game
    case results
    case calibration
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

    /// Quit mid-song: straight back to the menu.
    func endGame() {
        player?.stop()
        player = nil
        session = nil
        isPaused = false
        screen = .menu
    }
}
