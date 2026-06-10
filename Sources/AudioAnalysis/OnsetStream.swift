import Accelerate
import Foundation

/// A detected musical onset in one frequency band.
public struct DetectedOnset: Sendable, Codable {
    public let time: Double      // seconds since stream start
    public let band: Int         // 0 = low (20–250 Hz), 1 = mid (250–2k), 2 = high (2k–8k)
    public let energy: Float     // flux value, for prioritizing when notes collide
    public let centroid: Float   // 0…1 spectral centroid position within the band

    public init(time: Double, band: Int, energy: Float, centroid: Float) {
        self.time = time
        self.band = band
        self.energy = energy
        self.centroid = centroid
    }
}

/// Incremental per-band spectral-flux onset detector. Push mono samples, pull
/// onsets. The identical instance serves offline file analysis and the live
/// tap stream — only the producer differs.
public final class OnsetStream {
    public static let bandCount = 3
    private static let bandEdgesHz: [(Double, Double)] = [(20, 250), (250, 2000), (2000, 8000)]

    private let sampleRate: Double
    private let stft = STFT()
    private var prevLogMags = [Float](repeating: 0, count: STFT.binCount)
    private var bandBins: [(Range<Int>)] = []

    // Rolling flux history per band, for the adaptive threshold and the
    // local-maximum test. An onset at frame f is confirmed at f+lookAhead.
    private let historyLength = 86            // ≈0.5 s at 44.1k/256
    private let lookAhead = 3                 // frames; ~17 ms confirmation latency
    private var fluxHistory: [[Float]] = Array(repeating: [], count: bandCount)
    private var centroidHistory: [[Float]] = Array(repeating: [], count: bandCount)
    private var lastOnsetTime = [Double](repeating: -1, count: bandCount)
    private var lastEmitTime = 0.0 // any band — drives starvation relax
    private var frameIndex = 0

    // Energy envelopes for the sustained-texture fallback: smooth swells
    // have ~zero spectral flux, so flux thresholds can never catch them.
    private var fastEnv = [Float](repeating: 0, count: bandCount)
    private var slowEnv = [Float](repeating: 0, count: bandCount)
    private var envAbove = [Bool](repeating: false, count: bandCount)
    private let fallbackRefractory = 0.6
    private let starvationSeconds = 3.0

    /// Sensitivity: onset requires flux > mean + k·std of the rolling window.
    public var thresholdK: Float = 1.6
    /// Minimum spacing between onsets in the same band.
    public var refractorySeconds = 0.10
    /// Music-reactive visuals tap: called every `energyStride` hops (~23 ms)
    /// with (time, smoothed low-band energy) on the producer's thread.
    public var onEnergy: ((Double, Float) -> Void)?
    private let energyStride = 4

    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
        bandBins = Self.bandEdgesHz.map { lo, hi in
            let loBin = max(1, Int(lo * Double(STFT.fftSize) / sampleRate))
            let hiBin = min(STFT.binCount - 1, Int(hi * Double(STFT.fftSize) / sampleRate))
            return loBin..<max(loBin + 1, hiBin)
        }
    }

    private var hopDuration: Double { Double(STFT.hop) / sampleRate }

    /// Feed mono samples; returns any onsets confirmed by this chunk.
    public func process(_ samples: UnsafeBufferPointer<Float>) -> [DetectedOnset] {
        var onsets: [DetectedOnset] = []
        stft.process(samples) { mags in
            ingest(spectrum: mags, into: &onsets)
        }
        return onsets
    }

    public func process(_ samples: [Float]) -> [DetectedOnset] {
        samples.withUnsafeBufferPointer { process($0) }
    }

    private func ingest(spectrum mags: [Float], into onsets: inout [DetectedOnset]) {
        var logMags = [Float](repeating: 0, count: STFT.binCount)
        var one: Float = 1
        var tmp = mags
        vDSP_vsadd(mags, 1, &one, &tmp, 1, vDSP_Length(STFT.binCount))
        var count = Int32(STFT.binCount)
        vvlogf(&logMags, tmp, &count)

        for band in 0..<Self.bandCount {
            let bins = bandBins[band]
            var flux: Float = 0
            var weighted: Float = 0
            var total: Float = 0
            for i in bins {
                flux += max(0, logMags[i] - prevLogMags[i])
                weighted += Float(i) * mags[i]
                total += mags[i]
            }
            let centroidBin = total > 0 ? weighted / total : Float(bins.lowerBound)
            let centroid = (centroidBin - Float(bins.lowerBound))
                / Float(max(1, bins.count - 1))

            fluxHistory[band].append(flux)
            centroidHistory[band].append(min(max(centroid, 0), 1))
            if fluxHistory[band].count > historyLength {
                fluxHistory[band].removeFirst()
                centroidHistory[band].removeFirst()
            }

            fastEnv[band] += 0.3 * (total - fastEnv[band])
            slowEnv[band] += 0.02 * (total - slowEnv[band])

            checkForOnset(band: band, into: &onsets)
        }

        prevLogMags = logMags
        if frameIndex % energyStride == 0, let onEnergy {
            let time = Double(frameIndex) * hopDuration
                + Double(STFT.fftSize / 2) / sampleRate
            onEnergy(time, fastEnv[0])
        }
        frameIndex += 1
    }

    /// Tests the frame `lookAhead` frames back: local max above threshold.
    private func checkForOnset(band: Int, into onsets: inout [DetectedOnset]) {
        let history = fluxHistory[band]
        let n = history.count
        guard n >= lookAhead * 2 + 1, n > 20 else { return }

        let candidateIdx = n - 1 - lookAhead
        let candidate = history[candidateIdx]

        // Starvation relax: sustained textures (ambient/orchestral) produce
        // little spectral flux, which starves the chart. After 2s without
        // any onset, progressively loosen the gate (down to 35%) so gentle
        // swells still become notes. Flux ≈ 0 in true silence, so the floor
        // keeps silent passages empty.
        let now = Double(frameIndex) * hopDuration
        let starvation = max(0, now - lastEmitTime - 2.0)
        let relax = Float(max(0.35, 1.0 - 0.25 * starvation))

        var mean: Float = 0
        var std: Float = 0
        vDSP_normalize(history, 1, nil, 1, &mean, &std, vDSP_Length(n))

        // Frame index of the candidate on the absolute timeline. The STFT
        // window is centered fftSize/2 into the frame's samples.
        let time = Double(frameIndex - lookAhead) * hopDuration
            + Double(STFT.fftSize / 2) / sampleRate

        // Envelope-crossing fallback for sustained textures: a swell crest
        // (fast envelope crossing above slow) counts as an onset once the
        // flux detector has been starved. Silence has zero envelopes and
        // can never cross.
        let crossedUp = fastEnv[band] > slowEnv[band] * 1.1 && fastEnv[band] > 1e-3
        let fallbackFired = crossedUp && !envAbove[band]
            && now - lastEmitTime > starvationSeconds
            && time - lastOnsetTime[band] >= fallbackRefractory
        envAbove[band] = crossedUp

        let fluxFired = candidate > mean + thresholdK * relax * std
            && candidate > 0.5 * relax
            && (1...lookAhead).allSatisfy {
                history[candidateIdx - $0] <= candidate && history[candidateIdx + $0] < candidate
            }
            && time - lastOnsetTime[band] >= refractorySeconds

        guard fluxFired || fallbackFired else { return }
        lastOnsetTime[band] = time
        lastEmitTime = time

        onsets.append(DetectedOnset(
            time: time,
            band: band,
            energy: max(candidate, 0.5),
            centroid: centroidHistory[band][candidateIdx]
        ))
    }
}
