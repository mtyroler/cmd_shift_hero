import AVFAudio
import Foundation
import Observation
import Synchronization

/// Latency calibration: plays a metronome click every 0.5 s through the same
/// AVAudioEngine output path the game uses; the user taps Space on the click.
/// The median tap offset (corrected for output latency) becomes the game's
/// calibration offset: positive median = user/system chain is late, so we
/// store the negative to shift judging earlier.
@Observable
final class Calibrator {
    static let interval = 0.5
    static let tapsNeeded = 10

    private(set) var taps: [Double] = []
    var isDone: Bool { taps.count >= Self.tapsNeeded }

    /// Median tap offset in seconds (positive = tapping after the click).
    var medianOffset: Double? {
        guard !taps.isEmpty else { return nil }
        let sorted = taps.sorted()
        return sorted[sorted.count / 2]
    }

    /// The value to store as the game's calibration offset.
    var suggestedCalibration: Double? {
        medianOffset.map { -$0 }
    }

    /// Mutex is ~Copyable; the render block captures this wrapper instead.
    private final class RenderCounter: @unchecked Sendable {
        let samples = Mutex(0)
    }

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode!
    private let counter = RenderCounter()

    init() {
        let sampleRate = 44100.0
        let intervalSamples = Int(Self.interval * sampleRate)
        let clickLength = Int(0.025 * sampleRate)
        let rendered = counter

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                   channels: 1, interleaved: true)!
        sourceNode = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let out = abl[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let frames = Int(frameCount)
            let start = rendered.samples.withLock { current in
                let s = current
                current += frames
                return s
            }
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

    func start() throws {
        taps.removeAll()
        try engine.start()
    }

    func stop() {
        engine.stop()
    }

    /// Space pressed: record offset to the nearest click as the user heard it.
    func registerTap() {
        guard !isDone else { return }
        let rendered = counter.samples.withLock { $0 }
        let renderTime = Double(rendered) / 44100.0
        let heardTime = renderTime - engine.outputNode.presentationLatency
        var phase = heardTime.truncatingRemainder(dividingBy: Self.interval)
        if phase > Self.interval / 2 { phase -= Self.interval }
        taps.append(phase)
    }
}
