import Foundation
import Observation
import TapCapture

/// Latency calibration: MetronomeEngine (TapCapture — its render block must
/// stay off the MainActor) plays a click every 0.5 s through the same output
/// path the game uses; the user taps Space on the click. The median tap
/// offset becomes the game's calibration offset: positive median = the
/// user/system chain runs late, so we store the negative to shift judging.
@Observable
final class Calibrator {
    static let interval = 0.5
    static let tapsNeeded = 10

    private(set) var taps: [Double] = []
    var isDone: Bool { taps.count >= Self.tapsNeeded }

    /// Median tap offset in seconds (positive = tapping after the click).
    var medianOffset: Double? {
        guard !taps.isEmpty else { return nil }
        let sorted = taps.sorted()
        return sorted[sorted.count / 2]
    }

    /// The value to store as the game's calibration offset.
    var suggestedCalibration: Double? {
        medianOffset.map { -$0 }
    }

    private let metronome = MetronomeEngine(sampleRate: 44100, interval: interval)

    func start() throws {
        taps.removeAll()
        try metronome.start()
    }

    func stop() {
        metronome.stop()
    }

    /// Space pressed: record offset to the nearest click as the user heard it.
    func registerTap() {
        guard !isDone else { return }
        let heardTime = metronome.renderedTime - metronome.outputLatency
        var phase = heardTime.truncatingRemainder(dividingBy: Self.interval)
        if phase > Self.interval / 2 { phase -= Self.interval }
        taps.append(phase)
    }
}
