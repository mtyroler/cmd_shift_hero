import AVFAudio
import Synchronization

/// Click-track engine for latency calibration. Lives in this nonisolated
/// module on purpose: the render block runs on the realtime audio thread,
/// and a closure written in the MainActor-default app target would carry an
/// inferred isolation check that traps there.
public final class MetronomeEngine: @unchecked Sendable {
    private final class Counter: @unchecked Sendable {
        let samples = Atomic<Int>(0)
    }

    public let sampleRate: Double
    public let interval: Double

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode!
    private let counter = Counter()

    public init(sampleRate: Double = 44100, interval: Double = 0.5) {
        self.sampleRate = sampleRate
        self.interval = interval

        let intervalSamples = Int(interval * sampleRate)
        let clickLength = Int(0.025 * sampleRate)
        let counter = self.counter

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        sourceNode = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let out = abl[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let frames = Int(frameCount)
            let start = counter.samples.wrappingAdd(frames, ordering: .relaxed).oldValue
            for n in 0..<frames {
                let phase = (start + n) % intervalSamples
                if phase < clickLength {
                    let x = Double(phase) / sampleRate
                    out[n] = Float(sin(2 * .pi * 1000 * x) * exp(-x * 180)) * 0.6
                } else {
                    out[n] = 0
                }
            }
            return noErr
        }
        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)
    }

    public func start() throws {
        counter.samples.store(0, ordering: .releasing)
        try engine.start()
    }

    public func stop() {
        engine.stop()
    }

    /// Seconds of audio rendered so far.
    public var renderedTime: Double {
        Double(counter.samples.load(ordering: .acquiring)) / sampleRate
    }

    /// Output chain latency to subtract when comparing taps to clicks.
    public var outputLatency: Double {
        engine.outputNode.presentationLatency
    }
}
