import AudioAnalysis
import Foundation
import GameCore
import Testing

@Suite struct OnsetStreamTests {
    /// Synthesize clicks at known times and verify the detector finds them.
    @Test func detectsSyntheticLowClicks() {
        let sr = 44100.0
        let clickTimes: [Double] = [0.5, 1.0, 1.5, 2.0, 2.5]
        var samples = [Float](repeating: 0, count: Int(3.5 * sr))

        // 80 Hz tone bursts (low band), 60 ms, sharp attack.
        for t in clickTimes {
            let start = Int(t * sr)
            for n in 0..<Int(0.06 * sr) {
                let x = Double(n) / sr
                samples[start + n] += Float(sin(2 * .pi * 80 * x) * exp(-x * 40)) * 0.9
            }
        }

        let stream = OnsetStream(sampleRate: sr)
        var onsets: [DetectedOnset] = []
        // Feed in uneven chunks to exercise the streaming path.
        var i = 0
        for chunk in [3000, 7777, 12345, 50000, 500000] + [samples.count] {
            let end = min(i + chunk, samples.count)
            if i < end {
                onsets += stream.process(Array(samples[i..<end]))
            }
            i = end
        }

        let lowOnsets = onsets.filter { $0.band == 0 }
        #expect(lowOnsets.count == clickTimes.count, "expected \(clickTimes.count) low-band onsets, got \(lowOnsets.count)")

        for (onset, expected) in zip(lowOnsets, clickTimes) {
            #expect(abs(onset.time - expected) < 0.04, "onset at \(onset.time) vs expected \(expected)")
        }
    }

    @Test func highBandClicksLandInHighBand() {
        let sr = 44100.0
        var samples = [Float](repeating: 0, count: Int(2.5 * sr))
        for t in [0.5, 1.0, 1.5, 2.0] {
            let start = Int(t * sr)
            for n in 0..<Int(0.03 * sr) {
                let x = Double(n) / sr
                samples[start + n] += Float(sin(2 * .pi * 4000 * x) * exp(-x * 80)) * 0.8
            }
        }
        let stream = OnsetStream(sampleRate: sr)
        let onsets = stream.process(samples)
        let high = onsets.filter { $0.band == 2 }
        #expect(high.count >= 3)
    }

    @Test func chartGeneratorEnforcesDensityAndSpacing() {
        let generator = ChartGenerator(difficulty: .normal)
        // 50 onsets 20 ms apart — way denser than playable.
        var produced = 0
        for i in 0..<50 {
            let onset = DetectedOnset(time: Double(i) * 0.02, band: 1, energy: 1, centroid: 0.5)
            if generator.note(for: onset) != nil { produced += 1 }
        }
        #expect(produced <= 4) // normal caps at 4 notes/sec; window is 1 s
    }

    @Test func silenceProducesNoOnsets() {
        let stream = OnsetStream(sampleRate: 44100)
        let onsets = stream.process([Float](repeating: 0, count: 44100))
        #expect(onsets.isEmpty)
    }
}
