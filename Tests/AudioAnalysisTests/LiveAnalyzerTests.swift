import AudioAnalysis
import Foundation
import GameCore
import Testing

@Suite struct LiveAnalyzerTests {
    /// Regression test for the Cornfield Chase sync bug: with a long silent
    /// lead-in (Music.app startup latency), onset times must stay on the
    /// capture timeline — notes were coming in early by the lead-in length.
    @Test func onsetTimesIncludeLeadInSilence() async throws {
        let sr = 44100.0
        let leadIn = 1.2
        let clickTimes = [2.0, 2.5, 3.0, 3.5] // capture-timeline seconds

        let ring = AudioRingBuffer(capacityFrames: Int(6 * sr), channels: 2)
        let analyzer = LiveAnalyzer(
            ring: ring, sampleRate: sr, channels: 2,
            difficulty: .normal, emitNotes: false,
            onAudioStart: { _ in }, onNote: { _ in }
        )

        // 5s of stereo: silence until leadIn-adjacent clicks (low 80 Hz bursts).
        var samples = [Float](repeating: 0, count: Int(5 * sr) * 2)
        for t in clickTimes {
            let start = Int(t * sr)
            for n in 0..<Int(0.06 * sr) {
                let x = Double(n) / sr
                let v = Float(sin(2 * .pi * 80 * x) * exp(-x * 40)) * 0.9
                samples[(start + n) * 2] = v
                samples[(start + n) * 2 + 1] = v
            }
        }
        // Make the "first audible sample" land at leadIn with a tiny blip.
        samples[Int(leadIn * sr) * 2] = 0.01

        analyzer.start()
        samples.withUnsafeBufferPointer { buf in
            var offset = 0
            let total = buf.count / 2
            while offset < total {
                let wrote = ring.write(buf.baseAddress!.advanced(by: offset * 2),
                                       frameCount: total - offset)
                offset += wrote
                if wrote == 0 { usleep(5000) }
            }
        }

        // Wait until the analyzer drains the ring and finds every click.
        for _ in 0..<200 {
            let band0 = analyzer.snapshotNormalizedOnsets().filter { $0.band == 0 }.count
            if band0 >= clickTimes.count, ring.availableToRead == 0 { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        analyzer.stop()

        let normalized = analyzer.snapshotNormalizedOnsets().filter { $0.band == 0 }
        #expect(normalized.count == clickTimes.count,
                "expected \(clickTimes.count) onsets, got \(normalized.count)")

        // Normalized times are relative to the first audible sample (leadIn),
        // so capture time = normalized + leadIn must match the click times.
        for (onset, expected) in zip(normalized, clickTimes) {
            let captureTime = onset.time + leadIn
            #expect(abs(captureTime - expected) < 0.05,
                    "onset at capture \(captureTime) vs expected \(expected)")
        }
    }
}
