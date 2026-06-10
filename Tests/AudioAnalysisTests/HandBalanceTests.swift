import AudioAnalysis
import Foundation
import GameCore
import Testing

@Suite struct HandBalanceTests {
    /// Easy mode: home row only, strict left/right alternation in the
    /// ASDF / HJKL zones, G never used.
    @Test func easyAlternatesHands() {
        let generator = ChartGenerator(difficulty: .easy)
        var notes: [Note] = []
        for i in 0..<40 {
            let onset = DetectedOnset(
                time: Double(i) * 0.6,
                band: i % 3,
                energy: 1,
                centroid: Float(i % 5) / 4
            )
            if let note = generator.note(for: onset) { notes.append(note) }
        }

        #expect(notes.count > 20, "constraints dropped too many notes: \(notes.count)")
        #expect(notes.allSatisfy { $0.key.row == .home })
        #expect(!notes.contains { $0.key.column == 4 }, "G must stay free")
        for (a, b) in zip(notes, notes.dropFirst()) {
            let leftA = a.key.column <= 3
            let leftB = b.key.column <= 3
            #expect(leftA != leftB, "consecutive notes on the same hand: \(a.key.letter)\(b.key.letter)")
        }
    }

    /// Normal mode: even with onsets that all map to the far left, the
    /// balancer must cap same-hand runs at three notes.
    @Test func normalAvoidsLongSingleHandRuns() {
        let generator = ChartGenerator(difficulty: .normal)
        var notes: [Note] = []
        for i in 0..<200 {
            let onset = DetectedOnset(
                time: Double(i) * 0.35,
                band: i % 3,
                energy: 1,
                centroid: 0 // hard left bias — worst case for one hand
            )
            if let note = generator.note(for: onset) { notes.append(note) }
        }
        #expect(notes.count > 50, "constraints dropped too many notes: \(notes.count)")

        func isLeft(_ note: Note) -> Bool {
            note.key.column <= (note.key.row.keyCount - 1) / 2
        }
        var maxRun = 0
        var run = 0
        var lastHand: Bool?
        for note in notes {
            let hand = isLeft(note)
            run = hand == lastHand ? run + 1 : 1
            lastHand = hand
            maxRun = max(maxRun, run)
        }
        #expect(maxRun <= 3, "one hand played \(maxRun) notes in a row")
    }
}
