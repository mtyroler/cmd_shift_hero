import AVFAudio
import Foundation
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
    var lastError: String?
    private(set) var player: DelayedPlayer?

    /// M1: play the bundled demo track through the ring-buffer pipeline.
    func startDemo() {
        guard let url = Bundle.module.url(forResource: "demo", withExtension: "m4a") else {
            lastError = "demo.m4a missing from bundle"
            return
        }
        do {
            let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: true)
            let player = DelayedPlayer(
                sampleRate: file.processingFormat.sampleRate,
                channels: Int(file.processingFormat.channelCount),
                delaySeconds: 0.3 // small prefill so playback never starves the feeder
            )
            player.startFeeding(file: file)
            try player.start()
            self.player = player
            screen = .game
        } catch {
            Self.log.error("startDemo failed: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }

    func endGame() {
        player?.stop()
        player = nil
        screen = .menu
    }
}
