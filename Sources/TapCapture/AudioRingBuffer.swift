import Synchronization

/// Lock-free single-producer / single-consumer ring buffer of interleaved
/// Float32 frames. The producer is either a file feeder thread or the Core
/// Audio tap IOProc; the consumer is the AVAudioSourceNode render block.
/// Both hot-path methods are allocation-free and lock-free.
public final class AudioRingBuffer: @unchecked Sendable {
    public let channels: Int
    public let capacityFrames: Int

    private let storage: UnsafeMutablePointer<Float>
    private let written = Atomic<Int>(0) // total frames ever written
    private let read = Atomic<Int>(0)    // total frames ever read

    public init(capacityFrames: Int, channels: Int) {
        self.capacityFrames = capacityFrames
        self.channels = channels
        let count = capacityFrames * channels
        storage = .allocate(capacity: count)
        storage.initialize(repeating: 0, count: count)
    }

    deinit {
        storage.deallocate()
    }

    /// Total frames the producer has written since start (capture timeline).
    public var framesWritten: Int { written.load(ordering: .acquiring) }
    /// Total frames the consumer has read since start (playback timeline).
    public var framesRead: Int { read.load(ordering: .acquiring) }

    public var availableToRead: Int { framesWritten - framesRead }
    public var availableToWrite: Int { capacityFrames - availableToRead }

    /// Producer side. `input` is interleaved with `channels` channels.
    /// Returns the number of frames accepted (less than `frameCount` if full —
    /// callers with backpressure should retry the remainder).
    @discardableResult
    public func write(_ input: UnsafePointer<Float>, frameCount: Int) -> Int {
        let w = written.load(ordering: .relaxed)
        let r = read.load(ordering: .acquiring)
        let free = capacityFrames - (w - r)
        let toWrite = min(frameCount, free)
        guard toWrite > 0 else { return 0 }

        let startFrame = w % capacityFrames
        let firstChunk = min(toWrite, capacityFrames - startFrame)
        let secondChunk = toWrite - firstChunk

        storage.advanced(by: startFrame * channels)
            .update(from: input, count: firstChunk * channels)
        if secondChunk > 0 {
            storage.update(from: input.advanced(by: firstChunk * channels),
                           count: secondChunk * channels)
        }

        written.store(w + toWrite, ordering: .releasing)
        return toWrite
    }

    /// Consumer side. Fills `output` with up to `frameCount` interleaved
    /// frames; returns frames actually read. The caller zero-fills the rest.
    @discardableResult
    public func read(into output: UnsafeMutablePointer<Float>, frameCount: Int) -> Int {
        let r = read.load(ordering: .relaxed)
        let w = written.load(ordering: .acquiring)
        let available = w - r
        let toRead = min(frameCount, available)
        guard toRead > 0 else { return 0 }

        let startFrame = r % capacityFrames
        let firstChunk = min(toRead, capacityFrames - startFrame)
        let secondChunk = toRead - firstChunk

        output.update(from: storage.advanced(by: startFrame * channels),
                      count: firstChunk * channels)
        if secondChunk > 0 {
            output.advanced(by: firstChunk * channels)
                .update(from: storage, count: secondChunk * channels)
        }

        read.store(r + toRead, ordering: .releasing)
        return toRead
    }

    public func reset() {
        read.store(0, ordering: .releasing)
        written.store(0, ordering: .releasing)
    }
}
