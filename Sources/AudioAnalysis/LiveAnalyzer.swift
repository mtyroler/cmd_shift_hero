import Foundation
import GameCore
import Synchronization
import os

/// Consumes the tap's analysis ring on a background thread, detects onsets,
/// and emits playable notes in real time — the live half of the M6 loop.
///
/// Timeline note: the capture clock starts when the tap starts, which is a
/// few hundred ms before Music actually makes sound. Both the delayed audio
/// and live notes share that clock, so gameplay stays in sync regardless —
/// but cached charts must be portable across plays, so all onsets are also
/// normalized to `audioStartTime` (first non-silent sample) before caching.
public final class LiveAnalyzer: @unchecked Sendable {
    private static let log = Logger(subsystem: "com.maxtyroler.csh", category: "LiveAnalyzer")
    private static let silenceThreshold: Float = 0.001

    private let ring: AudioRingBuffer
    private let sampleRate: Double
    private let channels: Int
    private let stream: OnsetStream
    private let generator: ChartGenerator
    private let emitNotes: Bool
    private let onAudioStart: @MainActor @Sendable (Double) -> Void
    private let onNote: @MainActor @Sendable (Note) -> Void

    /// Mutex is ~Copyable; wrapped so the thread closure can capture it.
    private final class OnsetStore: @unchecked Sendable {
        let onsets = Mutex<[DetectedOnset]>([])
    }

    private var thread: Thread?
    private let store = OnsetStore()
    private var audioStartTime: Double?
    private var framesScanned = 0

    /// - Parameters:
    ///   - emitNotes: false when a cached chart is already loaded (analysis
    ///     then only refines the cache).
    ///   - onAudioStart: called once (main thread) with the capture-timeline
    ///     time of the first audible sample.
    ///   - onNote: live notes on the capture timeline (main thread).
    public init(ring: AudioRingBuffer, sampleRate: Double, channels: Int,
                difficulty: Difficulty, emitNotes: Bool,
                onAudioStart: @escaping @MainActor @Sendable (Double) -> Void,
                onNote: @escaping @MainActor @Sendable (Note) -> Void) {
        self.ring = ring
        self.sampleRate = sampleRate
        self.channels = channels
        self.stream = OnsetStream(sampleRate: sampleRate)
        self.stream.thresholdK = difficulty.thresholdK
        self.generator = ChartGenerator(difficulty: difficulty)
        self.emitNotes = emitNotes
        self.onAudioStart = onAudioStart
        self.onNote = onNote
    }

    public func start() {
        let thread = Thread { [self] in
            run()
        }
        thread.name = "csh.live-analyzer"
        thread.qualityOfService = .userInitiated
        self.thread = thread
        thread.start()
    }

    public func stop() {
        thread?.cancel()
        thread = nil
    }

    /// Cache-ready onsets (times relative to audio start).
    public func snapshotNormalizedOnsets() -> [DetectedOnset] {
        store.onsets.withLock { $0 }
    }

    private func run() {
        let chunkFrames = 4096
        let interleaved = UnsafeMutablePointer<Float>.allocate(capacity: chunkFrames * channels)
        defer { interleaved.deallocate() }
        var mono = [Float](repeating: 0, count: chunkFrames)

        while !Thread.current.isCancelled {
            let frames = ring.read(into: interleaved, frameCount: chunkFrames)
            if frames == 0 {
                Thread.sleep(forTimeInterval: 0.02)
                continue
            }

            // Mono mixdown.
            for n in 0..<frames {
                var sum: Float = 0
                for c in 0..<channels { sum += interleaved[n * channels + c] }
                mono[n] = sum / Float(channels)
            }

            // First audible sample → capture-timeline origin for the cache.
            if audioStartTime == nil {
                if let hit = (0..<frames).first(where: { abs(mono[$0]) > Self.silenceThreshold }) {
                    let t0 = Double(framesScanned + hit) / sampleRate
                    audioStartTime = t0
                    Self.log.info("audio starts at capture t=\(t0, format: .fixed(precision: 3))s")
                    let callback = onAudioStart
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { callback(t0) }
                    }
                }
            }
            framesScanned += frames

            guard audioStartTime != nil else { continue }

            let onsets = mono.withUnsafeBufferPointer { buf in
                stream.process(UnsafeBufferPointer(rebasing: buf[0..<frames]))
            }
            guard !onsets.isEmpty, let t0 = audioStartTime else { continue }

            for onset in onsets {
                let normalized = DetectedOnset(
                    time: onset.time - t0, band: onset.band,
                    energy: onset.energy, centroid: onset.centroid
                )
                store.onsets.withLock { $0.append(normalized) }
                if emitNotes, let note = generator.note(for: onset) {
                    let callback = onNote
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { callback(note) }
                    }
                }
            }
        }
    }
}
