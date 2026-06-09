// Generates Sources/CommandShiftHero/Resources/demo.m4a — a synthesized
// 64-second 120 BPM synthwave demo track with distinct low/mid/high content
// so the onset detector has something honest to chew on.
//
// Run: swift Scripts/make_demo.swift && afconvert -f m4af -d aac -b 192000 \
//        /tmp/csh_demo.wav Sources/CommandShiftHero/Resources/demo.m4a

import AVFoundation
import Foundation

let sampleRate = 44100.0
let bpm = 120.0
let beat = 60.0 / bpm           // 0.5 s
let bars = 32
let duration = Double(bars) * 4 * beat  // 64 s
let frames = Int(duration * sampleRate)

var left = [Float](repeating: 0, count: frames)
var right = [Float](repeating: 0, count: frames)

var rngState: UInt64 = 0x9E3779B97F4A7C15
func whiteNoise() -> Float {
    rngState ^= rngState << 13; rngState ^= rngState >> 7; rngState ^= rngState << 17
    return Float(Int64(bitPattern: rngState) >> 40) / Float(1 << 23)
}

func addSample(_ i: Int, _ l: Float, _ r: Float) {
    guard i >= 0 && i < frames else { return }
    left[i] += l
    right[i] += r
}

func kick(at t: Double) {
    let start = Int(t * sampleRate)
    let len = Int(0.16 * sampleRate)
    var phase = 0.0
    for n in 0..<len {
        let x = Double(n) / sampleRate
        let freq = 110.0 * exp(-x * 18) + 42
        phase += 2 * .pi * freq / sampleRate
        let env = exp(-x * 22)
        let s = Float(sin(phase) * env) * 0.9
        addSample(start + n, s, s)
    }
}

func snare(at t: Double) {
    let start = Int(t * sampleRate)
    let len = Int(0.18 * sampleRate)
    var lp: Float = 0
    for n in 0..<len {
        let x = Double(n) / sampleRate
        let env = Float(exp(-x * 24))
        let noise = whiteNoise()
        lp += 0.25 * (noise - lp)            // crude band shaping
        let tone = Float(sin(2 * .pi * 190 * x)) * 0.4
        let s = ((noise - lp) * 0.8 + tone) * env * 0.55
        addSample(start + n, s, s)
    }
}

func hat(at t: Double, open: Bool) {
    let start = Int(t * sampleRate)
    let len = Int((open ? 0.12 : 0.035) * sampleRate)
    var prev: Float = 0
    for n in 0..<len {
        let x = Double(n) / sampleRate
        let env = Float(exp(-x * (open ? 28 : 90)))
        let noise = whiteNoise()
        let hp = noise - prev                 // cheap high-pass
        prev = noise
        let s = hp * env * 0.30
        addSample(start + n, s * 1.1, s * 0.9)
    }
}

func bassNote(at t: Double, freq: Double, dur: Double) {
    let start = Int(t * sampleRate)
    let len = Int(dur * sampleRate)
    var phase = 0.0
    for n in 0..<len {
        let x = Double(n) / sampleRate
        phase += 2 * .pi * freq / sampleRate
        let saw = Float(2 * (phase / (2 * .pi)).truncatingRemainder(dividingBy: 1) - 1)
        let env = Float(min(1, x / 0.005) * exp(-x * 6))
        let s = saw * env * 0.32
        addSample(start + n, s, s)
    }
}

func leadNote(at t: Double, freq: Double, dur: Double) {
    let start = Int(t * sampleRate)
    let len = Int(dur * sampleRate)
    var p1 = 0.0, p2 = 0.0
    for n in 0..<len {
        let x = Double(n) / sampleRate
        p1 += 2 * .pi * freq / sampleRate
        p2 += 2 * .pi * freq * 2.01 / sampleRate
        let env = Float(min(1, x / 0.003) * exp(-x * 9))
        let s = Float(sin(p1) * 0.6 + sin(p2) * 0.4) * env * 0.22
        addSample(start + n, s * 0.8, s * 1.2)
    }
}

// Am – F – C – G, one chord per bar
let bassRoots = [55.0, 43.65, 65.41, 49.0]               // A1 F1 C2 G1
let leadScales: [[Double]] = [
    [440, 523.25, 659.25, 880],    // A C E A
    [349.23, 440, 523.25, 698.46], // F A C F
    [523.25, 659.25, 783.99, 1046.5], // C E G C
    [392, 493.88, 587.33, 783.99], // G B D G
]

for bar in 0..<bars {
    let barStart = Double(bar) * 4 * beat
    let chord = bar % 4
    let section = bar / 8   // 0 intro, 1 +bass, 2 +lead, 3 full

    for b in 0..<4 {
        let t = barStart + Double(b) * beat
        kick(at: t)
        if b % 2 == 1 { snare(at: t) }
        hat(at: t, open: false)
        hat(at: t + beat / 2, open: b == 3)
    }

    if section >= 1 {
        for e in 0..<8 {
            let t = barStart + Double(e) * beat / 2
            if e % 8 != 7 { bassNote(at: t, freq: bassRoots[chord], dur: beat * 0.45) }
        }
    }

    if section >= 2 {
        let pattern = [0, 2, 1, 3, 0, 3, 2, 1]
        let step = section == 3 ? 8 : 4
        for e in 0..<step {
            let t = barStart + Double(e) * (4 * beat) / Double(step)
            leadNote(at: t, freq: leadScales[chord][pattern[e % 8] % 4], dur: beat * 0.4)
        }
    }
}

// Normalize to -1 dBFS
let peak = max(left.map { abs($0) }.max() ?? 1, right.map { abs($0) }.max() ?? 1)
let gain = 0.89 / max(peak, 0.0001)
for i in 0..<frames { left[i] *= gain; right[i] *= gain }

// Write WAV
let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 2, interleaved: false)!
let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
buffer.frameLength = AVAudioFrameCount(frames)
left.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: frames) }
right.withUnsafeBufferPointer { buffer.floatChannelData![1].update(from: $0.baseAddress!, count: frames) }

let outURL = URL(fileURLWithPath: "/tmp/csh_demo.wav")
try? FileManager.default.removeItem(at: outURL)
do {
    let outFile = try AVAudioFile(
        forWriting: outURL,
        settings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
        ]
    )
    try outFile.write(from: buffer)
    outFile.close() // finalize the header before the process exits
}
print("wrote /tmp/csh_demo.wav (\(duration)s)")
