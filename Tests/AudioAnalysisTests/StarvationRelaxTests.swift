import AudioAnalysis
import Foundation
import GameCore
import Testing

@Suite struct StarvationRelaxTests {
    /// Ambient material (slow swells, no percussive attacks) must still
    /// produce onsets once the detector starves — the Cornfield Chase fix.
    @Test func sustainedSwellsEventuallyProduceOnsets() {
        let sr = 44100.0
        let duration = 16.0
        var samples = [Float](repeating: 0, count: Int(duration * sr))

        // A 220 Hz pad whose amplitude swells gently every ~3 s — tiny flux,
        // far below the strict threshold, nothing like a drum hit.
        for n in 0..<samples.count {
            let t = Double(n) / sr
            let swell = 0.25 + 0.2 * sin(2 * .pi * t / 3.0)
            samples[n] = Float(sin(2 * .pi * 220 * t) * swell * 0.4)
        }

        let stream = OnsetStream(sampleRate: sr)
        stream.thresholdK = 2.1 // normal difficulty's strict setting
        let onsets = stream.process(samples)

        #expect(onsets.count >= 3, "16s of swelling pad should yield notes, got \(onsets.count)")
    }

    @Test func silenceStillProducesNothingDespiteRelax() {
        let stream = OnsetStream(sampleRate: 44100)
        stream.thresholdK = 2.1
        // 20s of digital silence — starvation relax must never invent notes.
        let onsets = stream.process([Float](repeating: 0, count: 20 * 44100))
        #expect(onsets.isEmpty)
    }
}
