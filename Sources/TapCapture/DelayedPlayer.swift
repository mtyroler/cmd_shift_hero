import AVFAudio
import Foundation
import GameCore
import Synchronization
import os

/// Plays interleaved audio pulled from an AudioRingBuffer through its own
/// AVAudioEngine output, and exposes the playback position as the game's
/// master clock. The same pipeline serves both modes:
///   - file mode: a feeder thread decodes a local file into the ring buffer
///   - tap mode (M5): the Core Audio tap IOProc writes captured Music.app audio
///
/// The lookahead delay works via `prefillFrames`: output stays silent until
/// the producer has written that many frames, after which the read cursor
/// trails the write cursor by ~that amount for the rest of the session.
public final class DelayedPlayer: GameClock, @unchecked Sendable {
    private static let log = Logger(subsystem: "com.maxtyroler.csh", category: "DelayedPlayer")

    /// Atomics are ~Copyable, so the realtime render block captures this
    /// reference wrapper instead of the individual counters.
    private final class State: @unchecked Sendable {
        let framesConsumed = Atomic<Int>(0)
        let prefilled = Atomic<Bool>(false)
        let running = Atomic<Bool>(false)
        let feederFinished = Atomic<Bool>(false)
        let calibrationOffset = Atomic<Double>(0)
    }

    public let ring: AudioRingBuffer
    public let sampleRate: Double
    public let prefillFrames: Int

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode!
    private let state = State()
    private var feederThread: Thread?

    public init(sampleRate: Double, channels: Int = 2, delaySeconds: Double = 0, bufferSeconds: Double = 20) {
        self.sampleRate = sampleRate
        self.prefillFrames = Int(delaySeconds * sampleRate)
        self.ring = AudioRingBuffer(
            capacityFrames: Int(bufferSeconds * sampleRate),
            channels: channels
        )

        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(channels),
            interleaved: true
        )!

        let ring = self.ring
        let state = self.state
        let prefillFrames = self.prefillFrames

        sourceNode = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let out = abl[0].mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }
            let frames = Int(frameCount)
            out.update(repeating: 0, count: frames * ring.channels)

            guard state.running.load(ordering: .acquiring) else { return noErr }

            // Hold silence until the lookahead buffer has filled once.
            if !state.prefilled.load(ordering: .relaxed) {
                if ring.availableToRead >= prefillFrames {
                    state.prefilled.store(true, ordering: .relaxed)
                } else {
                    return noErr
                }
            }

            let got = ring.read(into: out, frameCount: frames)
            if got > 0 {
                state.framesConsumed.wrappingAdd(got, ordering: .releasing)
            }
            return noErr
        }

        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)
    }

    // MARK: - GameClock

    /// Song position of what the user is hearing right now, in seconds.
    public var audibleSongTime: Double {
        let consumed = Double(state.framesConsumed.load(ordering: .acquiring)) / sampleRate
        let latency = engine.outputNode.presentationLatency
        return consumed - latency + state.calibrationOffset.load(ordering: .relaxed)
    }

    /// Set from the calibration screen (M3); added to the reported song time.
    public var calibrationOffset: Double {
        get { state.calibrationOffset.load(ordering: .relaxed) }
        set { state.calibrationOffset.store(newValue, ordering: .relaxed) }
    }

    // MARK: - Transport

    public func start() throws {
        try engine.start()
        state.running.store(true, ordering: .releasing)
    }

    public func pause() {
        state.running.store(false, ordering: .releasing)
        engine.pause()
    }

    public func resume() throws {
        try engine.start()
        state.running.store(true, ordering: .releasing)
    }

    public func stop() {
        state.running.store(false, ordering: .releasing)
        feederThread?.cancel()
        engine.stop()
    }

    /// True once the producer has finished and playback has drained the buffer.
    public var isDrained: Bool {
        state.feederFinished.load(ordering: .acquiring) && ring.availableToRead == 0
    }

    // MARK: - File feeder (demo / local-file mode)

    /// Decodes `file` into the ring buffer on a background thread, faster than
    /// realtime, with backpressure when the ring is full.
    /// The file must be opened with
    /// `AVAudioFile(forReading:commonFormat:.pcmFormatFloat32, interleaved:true)`
    /// and its channel count must match the ring's.
    public func startFeeding(file: AVAudioFile) {
        precondition(file.processingFormat.isInterleaved
                     && file.processingFormat.commonFormat == .pcmFormatFloat32
                     && Int(file.processingFormat.channelCount) == ring.channels,
                     "file must be opened as interleaved float32 with matching channels")
        let ring = self.ring
        let state = self.state
        let channels = ring.channels

        let thread = Thread {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8192) else { return }
            while !Thread.current.isCancelled {
                do {
                    try file.read(into: buffer)
                } catch {
                    Self.log.error("file read failed: \(error.localizedDescription)")
                    break
                }
                if buffer.frameLength == 0 { break } // EOF
                guard let data = buffer.floatChannelData?[0] else { break }

                var offset = 0
                let total = Int(buffer.frameLength)
                while offset < total, !Thread.current.isCancelled {
                    let wrote = ring.write(data.advanced(by: offset * channels),
                                           frameCount: total - offset)
                    offset += wrote
                    if wrote == 0 {
                        Thread.sleep(forTimeInterval: 0.05) // ring full — backpressure
                    }
                }
            }
            state.feederFinished.store(true, ordering: .releasing)
        }
        thread.name = "csh.file-feeder"
        thread.qualityOfService = .userInitiated
        feederThread = thread
        thread.start()
    }
}
