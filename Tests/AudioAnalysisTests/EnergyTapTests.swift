import AudioAnalysis
import Foundation
import Testing

@Suite struct EnergyTapTests {
    /// The onEnergy tap must trace the low band: near-zero through silence,
    /// clearly hot once an 80 Hz bass line starts.
    @Test func energyFollowsBassContent() {
        let sr = 44100.0
        let stream = OnsetStream(sampleRate: sr)
        var points: [(time: Double, value: Float)] = []
        stream.onEnergy = { points.append(($0, $1)) }

        var samples = [Float](repeating: 0, count: Int(2 * sr))
        for n in Int(sr)..<samples.count {
            let t = Double(n) / sr
            samples[n] = Float(sin(2 * .pi * 80 * t)) * 0.8
        }
        _ = stream.process(samples)

        #expect(points.count > 50, "tap should fire steadily, got \(points.count)")
        #expect(zip(points, points.dropFirst()).allSatisfy { $0.time < $1.time })

        let silent = points.filter { $0.time < 0.9 }.map(\.value).max() ?? 0
        let loud = points.filter { $0.time > 1.2 }.map(\.value).max() ?? 0
        #expect(loud > max(silent, 1e-6) * 10,
                "bass section (\(loud)) should dwarf silence (\(silent))")
    }
}
