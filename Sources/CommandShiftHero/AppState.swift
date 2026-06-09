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
}

@Observable
final class AppState {
    private static let log = Logger(subsystem: "com.maxtyroler.csh", category: "AppState")

    var screen: Screen = .menu
    var isAnalyzing = false
    var lastError: String?
    var difficulty: Difficulty = .normal

    private(set) var player: DelayedPlayer?
    private(set) var session: GameSession?

    /// M2: offline-analyze the bundled demo track, then play it through the
    /// ring-buffer pipeline with a full pre-computed chart.
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

                let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: true)
                let player = DelayedPlayer(
                    sampleRate: file.processingFormat.sampleRate,
                    channels: Int(file.processingFormat.channelCount),
                    delaySeconds: 0.3 // small prefill so playback never starves the feeder
                )
                player.startFeeding(file: file)
                try player.start()

                self.session = GameSession(chart: chart)
                self.player = player
                self.isAnalyzing = false
                self.screen = .game
                Self.log.info("demo started: \(chart.notes.count) notes, \(self.difficulty.rawValue)")
            } catch {
                Self.log.error("startDemo failed: \(error.localizedDescription)")
                self.lastError = error.localizedDescription
                self.isAnalyzing = false
            }
        }
    }

    func endGame() {
        player?.stop()
        player = nil
        session = nil
        screen = .menu
    }
}
