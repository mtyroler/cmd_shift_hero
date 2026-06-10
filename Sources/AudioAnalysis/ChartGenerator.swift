import Foundation
import GameCore

public enum Difficulty: String, CaseIterable, Codable, Sendable {
    case easy, normal, hard

    /// Rows notes may land on.
    var allowedRows: Set<KeyRow> {
        switch self {
        case .easy: [.home]
        case .normal: [.home, .bottom, .top]
        case .hard: [.home, .bottom, .top]
        }
    }

    /// Global note-density ceiling.
    var maxNotesPerSecond: Double {
        switch self {
        case .easy: 1.8
        case .normal: 3
        case .hard: 6
        }
    }

    /// Minimum spacing between ANY two notes, across all rows. Sub-200ms
    /// cross-row cascades read as chords to human hands.
    var minGlobalGap: Double {
        switch self {
        case .easy: 0.50
        case .normal: 0.28
        case .hard: 0.16
        }
    }

    /// Onset-detector sensitivity (lower = more notes).
    var thresholdK: Float {
        switch self {
        case .easy: 2.6
        case .normal: 2.1
        case .hard: 1.5
        }
    }

    /// Maximum simultaneous letter keys (keyboard rollover safety).
    var maxChord: Int {
        switch self {
        case .easy: 1
        case .normal: 1
        case .hard: 2
        }
    }
}

/// Stateful onset → note mapper with playability constraints. Feed onsets in
/// time order (works identically for offline and live analysis).
public final class ChartGenerator {
    private let difficulty: Difficulty

    private enum Hand { case left, right }

    private var lastNoteTime = -Double.infinity
    private var lastTimePerRow: [KeyRow: Double] = [:]
    private var lastColumnPerRow: [KeyRow: Int] = [:]
    private var lastTimePerKey: [KeyPosition: Double] = [:]
    private var recentNoteTimes: [Double] = []   // sliding 1s window for density cap
    private var chordWindow: [(time: Double, count: Int)] = []
    private var recentHands: [Hand] = []         // trailing emitted notes, max 3
    private var easyNextHand: Hand = .left       // easy strictly alternates hands

    // Playability constants
    private let minRowGap = 0.110
    private let minKeyGap = 0.180
    private let maxColumnJump = 3
    private let chordWindowSeconds = 0.05

    public init(difficulty: Difficulty) {
        self.difficulty = difficulty
    }

    /// Band index → keyboard row: bass at the bottom, highs on top.
    private static func row(forBand band: Int) -> KeyRow {
        switch band {
        case 0: .bottom
        case 1: .home
        default: .top
        }
    }

    /// Which hand a key naturally belongs to, by row midpoint.
    private static func hand(of column: Int, in row: KeyRow) -> Hand {
        column <= (row.keyCount - 1) / 2 ? .left : .right
    }

    /// Easy mode plays only ASDF (left) and HJKL (right) — G stays free so
    /// the two hand zones never touch.
    private static func easyColumns(for hand: Hand) -> ClosedRange<Int> {
        hand == .left ? 0...3 : 5...8
    }

    /// Returns a playable note for this onset, or nil if constraints drop it.
    public func note(for onset: DetectedOnset) -> Note? {
        var row = Self.row(forBand: onset.band)
        if !difficulty.allowedRows.contains(row) {
            row = .home // easy mode folds everything onto the home row
        }
        let t = onset.time

        // One-hand-at-a-time rule: global spacing across all rows.
        guard t - lastNoteTime >= difficulty.minGlobalGap else { return nil }

        // Density cap (notes in the trailing second).
        recentNoteTimes.removeAll { $0 < t - 1.0 }
        guard Double(recentNoteTimes.count) < difficulty.maxNotesPerSecond else { return nil }

        // Simultaneity cap across rows (rollover safety).
        chordWindow.removeAll { $0.time < t - chordWindowSeconds }
        let simultaneous = chordWindow.reduce(0) { $0 + $1.count }
        guard simultaneous < difficulty.maxChord else { return nil }

        // Per-row spacing.
        if let last = lastTimePerRow[row], t - last < minRowGap { return nil }

        let keyCount = row.keyCount
        var column: Int
        var allowedColumns = 0...(keyCount - 1)

        if difficulty == .easy {
            // Strict hand alternation: each note lands in the zone of
            // whichever hand is up next; the centroid picks the finger.
            let zone = Self.easyColumns(for: easyNextHand)
            column = zone.lowerBound + Int((onset.centroid * Float(zone.count - 1)).rounded())
            allowedColumns = zone
        } else {
            // Column from the spectral centroid, clamped to a reachable jump.
            column = Int((onset.centroid * Float(keyCount - 1)).rounded())
            if let prev = lastColumnPerRow[row] {
                column = min(max(column, prev - maxColumnJump), prev + maxColumnJump)
            }
            column = min(max(column, 0), keyCount - 1)

            // Hand balance (normal only): after three notes in a row on one
            // hand, mirror the next note across the row midpoint. Cross-hand
            // jumps don't need the reach clamp — it's a fresh hand.
            if difficulty == .normal,
               recentHands.count >= 3,
               recentHands.allSatisfy({ $0 == recentHands[0] }),
               Self.hand(of: column, in: row) == recentHands[0] {
                column = keyCount - 1 - column
            }
        }

        // Per-key spacing: nudge sideways once, otherwise drop.
        var key = KeyPosition(row: row, column: column)
        if let last = lastTimePerKey[key], t - last < minKeyGap {
            let alternatives = [column - 1, column + 1].filter { allowedColumns.contains($0) }
            guard let alt = alternatives.first(where: { c in
                let k = KeyPosition(row: row, column: c)
                return lastTimePerKey[k].map { t - $0 >= minKeyGap } ?? true
            }) else { return nil }
            key = KeyPosition(row: row, column: alt)
        }

        lastNoteTime = t
        lastTimePerRow[row] = t
        lastColumnPerRow[row] = key.column
        lastTimePerKey[key] = t
        recentNoteTimes.append(t)
        chordWindow.append((t, 1))
        easyNextHand = easyNextHand == .left ? .right : .left
        recentHands.append(Self.hand(of: key.column, in: row))
        if recentHands.count > 3 { recentHands.removeFirst() }

        return Note(time: t, key: key)
    }
}
