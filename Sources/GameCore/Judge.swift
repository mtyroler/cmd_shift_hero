public enum HitJudgment: Sendable {
    case perfect   // within ±50 ms
    case good      // within ±110 ms
    case miss      // note passed unhit, or press with no note in window

    public static let perfectWindow = 0.050
    public static let goodWindow = 0.110
}

public struct ScoreState: Sendable {
    public var score = 0
    public var combo = 0
    public var bestCombo = 0
    public var perfects = 0
    public var goods = 0
    public var misses = 0

    /// Multiplier tiers at 10/20/30 combo, like the classics.
    public var multiplier: Int { min(4, 1 + combo / 10) }

    public var totalNotes: Int { perfects + goods + misses }
    public var accuracy: Double {
        let total = totalNotes
        guard total > 0 else { return 0 }
        return Double(perfects * 2 + goods) / Double(total * 2)
    }

    public var grade: String {
        if accuracy >= 0.95 && misses == 0 { return "S" }
        if accuracy >= 0.90 { return "A" }
        if accuracy >= 0.80 { return "B" }
        if accuracy >= 0.65 { return "C" }
        return "D"
    }
}

/// Judges key presses against the chart and tracks the score.
/// Single-threaded by design: call only from the render/input thread (main).
public final class GameSession {
    public private(set) var chart: Chart
    public private(set) var state = ScoreState()

    /// Star power: meter fills on hits; Shift spends a full meter for 8 s of
    /// ×2 scoring; Cmd+Shift spends it to perfect-clear the visible notes.
    public private(set) var starPowerActive = false
    public private(set) var starMeter = 0.0
    private var starPowerEndTime: Double?
    public static let starPowerDuration = 8.0
    public static let finisherWindow = 1.5

    /// Parallel to chart.notes: true once judged (hit or missed).
    private var judged: [Bool]
    /// Index below which every note is judged — keeps scans O(small).
    private var lowWatermark = 0

    public init(chart: Chart) {
        self.chart = chart
        self.judged = Array(repeating: false, count: chart.notes.count)
    }

    /// For live play (M6): append notes as the analyzer emits them.
    public func appendNote(_ note: Note) {
        chart.append(note)
        judged.append(false)
    }

    /// For cached replays (M6): swap in the full chart once the audio-start
    /// offset is known. Only valid before any note has been judged.
    public func loadChart(_ newChart: Chart, timeOffset: Double) {
        guard chart.notes.isEmpty || state.totalNotes == 0 else { return }
        chart = Chart(notes: newChart.notes.map {
            Note(time: $0.time + timeOffset, key: $0.key)
        })
        judged = Array(repeating: false, count: chart.notes.count)
        lowWatermark = 0
    }

    public var noteCount: Int { chart.notes.count }
    public func isJudged(_ index: Int) -> Bool { judged[index] }
    public func note(at index: Int) -> Note { chart.notes[index] }

    /// A key was physically pressed at song time `t`.
    /// Returns the judgment and the matched note index, if any.
    @discardableResult
    public func registerPress(key: KeyPosition, at t: Double) -> (HitJudgment, Int)? {
        var bestIndex: Int?
        var bestDelta = Double.infinity

        var i = lowWatermark
        while i < chart.notes.count {
            let note = chart.notes[i]
            if note.time > t + HitJudgment.goodWindow { break }
            if !judged[i], note.key == key {
                let delta = abs(note.time - t)
                if delta <= HitJudgment.goodWindow, delta < bestDelta {
                    bestDelta = delta
                    bestIndex = i
                }
            }
            i += 1
        }

        guard let index = bestIndex else { return nil } // stray press — no note nearby

        judged[index] = true
        let judgment: HitJudgment = bestDelta <= HitJudgment.perfectWindow ? .perfect : .good
        applyHit(judgment)
        advanceWatermark()
        return (judgment, index)
    }

    /// Seconds of star power left at song time `t`, or nil when inactive.
    /// Lets the HUD drain the meter as a countdown instead of snapping empty.
    public func starPowerRemaining(at t: Double) -> Double? {
        guard starPowerActive, let end = starPowerEndTime else { return nil }
        return max(0, end - t)
    }

    /// Shift pressed: activate star power if the meter is full.
    @discardableResult
    public func tryActivateStarPower(at t: Double) -> Bool {
        guard !starPowerActive, starMeter >= 1 else { return false }
        starMeter = 0
        starPowerActive = true
        starPowerEndTime = t + Self.starPowerDuration
        return true
    }

    /// Cmd+Shift pressed: spend a full meter to perfect-hit every pending
    /// note from now through the finisher window. Returns the cleared
    /// indices, or nil if the meter wasn't full.
    public func tryFinisher(at t: Double) -> [Int]? {
        guard starMeter >= 1 else { return nil }

        var cleared: [Int] = []
        var i = lowWatermark
        while i < chart.notes.count {
            let note = chart.notes[i]
            if note.time > t + Self.finisherWindow { break }
            if !judged[i], note.time >= t - HitJudgment.goodWindow {
                judged[i] = true
                applyHit(.perfect)
                cleared.append(i)
            }
            i += 1
        }
        starMeter = 0 // after the hits — finisher hits must not refill the meter
        advanceWatermark()
        return cleared
    }

    /// Advance the song clock; returns indices of notes that just became misses.
    public func advance(to t: Double) -> [Int] {
        if let end = starPowerEndTime, t >= end {
            starPowerActive = false
            starPowerEndTime = nil
        }
        var missed: [Int] = []
        var i = lowWatermark
        while i < chart.notes.count {
            let note = chart.notes[i]
            if note.time >= t - HitJudgment.goodWindow { break }
            if !judged[i] {
                judged[i] = true
                missed.append(i)
                state.misses += 1
                state.combo = 0
            }
            i += 1
        }
        advanceWatermark()
        return missed
    }

    private func applyHit(_ judgment: HitJudgment) {
        let base = judgment == .perfect ? 100 : 50
        let starBonus = starPowerActive ? 2 : 1
        state.score += base * state.multiplier * starBonus
        state.combo += 1
        state.bestCombo = max(state.bestCombo, state.combo)
        if judgment == .perfect { state.perfects += 1 } else { state.goods += 1 }
        if !starPowerActive {
            starMeter = min(1, starMeter + (judgment == .perfect ? 0.04 : 0.02))
        }
    }

    private func advanceWatermark() {
        while lowWatermark < judged.count, judged[lowWatermark] {
            lowWatermark += 1
        }
    }
}
