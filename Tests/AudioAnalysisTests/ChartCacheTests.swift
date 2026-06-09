import AudioAnalysis
import GameCore
import Testing

@Suite struct ChartCacheTests {
    @Test func mergeDedupesSameEventKeepingHigherEnergy() {
        let existing = CachedAnalysis(
            version: AnalysisVersion.current, trackID: "ABC", duration: 60, playCount: 1,
            onsets: [
                DetectedOnset(time: 1.000, band: 0, energy: 2.0, centroid: 0.5),
                DetectedOnset(time: 2.000, band: 1, energy: 1.0, centroid: 0.3),
            ]
        )
        let fresh = [
            DetectedOnset(time: 1.010, band: 0, energy: 5.0, centroid: 0.6), // dup of #1, stronger
            DetectedOnset(time: 2.000, band: 0, energy: 1.0, centroid: 0.2), // different band — kept
            DetectedOnset(time: 3.000, band: 2, energy: 1.0, centroid: 0.9), // new
        ]
        let merged = ChartCache.merge(existing: existing, newOnsets: fresh, trackID: "ABC", duration: 60)

        #expect(merged.onsets.count == 4)
        #expect(merged.playCount == 2)
        let band0 = merged.onsets.filter { $0.band == 0 && $0.time < 1.5 }
        #expect(band0.count == 1)
        #expect(band0[0].energy == 5.0)
    }

    @Test func mergeWithoutExistingStartsAtPlayOne() {
        let merged = ChartCache.merge(
            existing: nil,
            newOnsets: [DetectedOnset(time: 0.5, band: 1, energy: 1, centroid: 0.5)],
            trackID: "X", duration: 30
        )
        #expect(merged.playCount == 1)
        #expect(merged.version == AnalysisVersion.current)
    }

    @Test func chartFromAnalysisRespectsDifficulty() {
        // 100 mid-band onsets, 0.25s apart (4/s) — easy should thin them out.
        let onsets = (0..<100).map {
            DetectedOnset(time: Double($0) * 0.25, band: 1, energy: 1, centroid: 0.5)
        }
        let analysis = CachedAnalysis(
            version: AnalysisVersion.current, trackID: "Y", duration: 26, playCount: 1, onsets: onsets
        )
        let easy = ChartCache.chart(from: analysis, difficulty: .easy)
        let hard = ChartCache.chart(from: analysis, difficulty: .hard)
        #expect(easy.notes.count < hard.notes.count)
        #expect(easy.notes.allSatisfy { $0.key.row == KeyRow.home })
    }

    @Test func sessionLoadChartShiftsTimes() {
        let session = GameSession(chart: Chart(notes: []))
        let chart = Chart(notes: [Note(time: 1.0, key: KeyPosition(row: .home, column: 0))])
        session.loadChart(chart, timeOffset: 0.35)
        #expect(session.noteCount == 1)
        #expect(abs(session.note(at: 0).time - 1.35) < 1e-9)
    }
}
