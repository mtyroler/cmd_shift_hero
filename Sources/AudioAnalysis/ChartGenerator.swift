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
        case .easy: 2
        case .normal: 4
        case .hard: 7
        }
    }

    /// Onset-detector sensitivity (lower = more notes).
    var thresholdK: Float {
        switch self {
        case .easy: 2.4
        case .normal: 1.8
        case .hard: 1.4
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

    private var lastTimePerRow: [KeyRow: Double] = [:]
    private var lastColumnPerRow: [KeyRow: Int] = [:]
    private var lastTimePerKey: [KeyPosition: Double] = [:]
    private var recentNoteTimes: [Double] = []   // sliding 1s window for density cap
    private var chordWindow: [(time: Double, count: Int)] = []

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

    /// Returns a playable note for this onset, or nil if constraints drop it.
    public func note(for onset: DetectedOnset) -> Note? {
        var row = Self.row(forBand: onset.band)
        if !difficulty.allowedRows.contains(row) {
            row = .home // easy mode folds everything onto the home row
        }
        let t = onset.time

        // Density cap (notes in the trailing second).
        recentNoteTimes.removeAll { $0 < t - 1.0 }
        guard Double(recentNoteTimes.count) < difficulty.maxNotesPerSecond else { return nil }

        // Simultaneity cap across rows (rollover safety).
        chordWindow.removeAll { $0.time < t - chordWindowSeconds }
        let simultaneous = chordWindow.reduce(0) { $0 + $1.count }
        guard simultaneous < difficulty.maxChord else { return nil }

        // Per-row spacing.
        if let last = lastTimePerRow[row], t - last < minRowGap { return nil }

        // Column from the spectral centroid, clamped to a reachable jump.
        let keyCount = row.keyCount
        var column = Int((onset.centroid * Float(keyCount - 1)).rounded())
        if let prev = lastColumnPerRow[row] {
            column = min(max(column, prev - maxColumnJump), prev + maxColumnJump)
        }
        column = min(max(column, 0), keyCount - 1)

        // Per-key spacing: nudge sideways once, otherwise drop.
        var key = KeyPosition(row: row, column: column)
        if let last = lastTimePerKey[key], t - last < minKeyGap {
            let alternatives = [column - 1, column + 1].filter { (0..<keyCount).contains($0) }
            guard let alt = alternatives.first(where: { c in
                let k = KeyPosition(row: row, column: c)
                return lastTimePerKey[k].map { t - $0 >= minKeyGap } ?? true
            }) else { return nil }
            key = KeyPosition(row: row, column: alt)
        }

        lastTimePerRow[row] = t
        lastColumnPerRow[row] = key.column
        lastTimePerKey[key] = t
        recentNoteTimes.append(t)
        chordWindow.append((t, 1))

        return Note(time: t, key: key)
    }
}
