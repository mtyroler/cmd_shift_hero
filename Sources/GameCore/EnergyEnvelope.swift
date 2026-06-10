import Synchronization

/// A band-energy time series on the song/capture timeline. The analyzer
/// appends samples from its own thread (offline: all upfront; live: ~2.5 s
/// ahead of the audible clock thanks to the tap delay), and the renderer
/// samples it at `GameClock.audibleSongTime` — so visuals breathe with what
/// the player hears, never with what the analyzer just read.
public final class EnergyEnvelope: @unchecked Sendable {
    private struct Storage {
        var times: [Double] = []
        var values: [Float] = []
        var peak: Float = 0
    }

    private let storage = Mutex<Storage>(Storage())

    public init() {}

    /// Append a sample; times must be non-decreasing (out-of-order is dropped).
    public func append(time: Double, value: Float) {
        storage.withLock { s in
            guard s.times.last.map({ time >= $0 }) ?? true else { return }
            s.times.append(time)
            s.values.append(max(0, value))
            s.peak = max(s.peak, value)
        }
    }

    /// Peak-normalized level (0…1) at song time `t`, linearly interpolated.
    /// Before the first sample: 0. Past the last sample: holds the last value.
    public func level(at t: Double) -> Float {
        storage.withLock { s in
            guard let first = s.times.first, s.peak > 1e-6 else { return 0 }
            if t < first { return 0 }
            if t >= s.times[s.times.count - 1] {
                return min(1, s.values[s.values.count - 1] / s.peak)
            }
            // Rightmost sample with time <= t.
            var lo = 0
            var hi = s.times.count - 1
            while lo + 1 < hi {
                let mid = (lo + hi) / 2
                if s.times[mid] <= t { lo = mid } else { hi = mid }
            }
            let span = s.times[hi] - s.times[lo]
            let f = span > 0 ? Float((t - s.times[lo]) / span) : 0
            let v = s.values[lo] + (s.values[hi] - s.values[lo]) * f
            return min(1, max(0, v / s.peak))
        }
    }
}
