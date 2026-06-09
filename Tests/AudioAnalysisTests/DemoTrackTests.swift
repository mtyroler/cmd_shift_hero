import AudioAnalysis
import Foundation
import GameCore
import Testing

@Suite struct DemoTrackTests {
    private var demoURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // AudioAnalysisTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // package root
            .appendingPathComponent("Sources/CommandShiftHero/Resources/demo.m4a")
    }

    /// End-to-end: the bundled 64s demo track must yield a playable chart.
    @Test func demoTrackProducesPlayableChart() throws {
        let chart = try OfflineAnalyzer.analyze(url: demoURL, difficulty: .normal)
        let notes = chart.notes

        // 64s of 120BPM music with kick/snare/bass/lead: expect a healthy
        // but playable density (normal caps at 4 notes/s → max 256).
        #expect(notes.count > 60, "got \(notes.count) notes — detector too deaf")
        #expect(notes.count <= 256, "got \(notes.count) notes — density cap broken")

        // Sorted, all within track bounds, on valid keys.
        #expect(zip(notes, notes.dropFirst()).allSatisfy { $0.time <= $1.time })
        #expect(notes.allSatisfy { $0.time >= 0 && $0.time <= 64 })

        // All three rows should appear (track has low/mid/high content).
        let rows = Set(notes.map(\.key.row))
        #expect(rows == Set(KeyRow.allCases), "rows used: \(rows)")

        // No two consecutive notes on the same key closer than 180 ms.
        var lastPerKey: [KeyPosition: Double] = [:]
        for note in notes {
            if let last = lastPerKey[note.key] {
                #expect(note.time - last >= 0.179, "key \(note.key.letter) re-hit after \(note.time - last)s")
            }
            lastPerKey[note.key] = note.time
        }
    }
}
