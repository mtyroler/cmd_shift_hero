import AVFAudio
import Foundation
import GameCore
import os

/// Full-file analysis for local/DRM-free audio: decode, detect onsets,
/// generate a complete chart before play starts.
public enum OfflineAnalyzer {
    private static let log = Logger(subsystem: "com.maxtyroler.csh", category: "OfflineAnalyzer")

    public static func analyze(url: URL, difficulty: Difficulty) throws -> Chart {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let sampleRate = file.processingFormat.sampleRate
        let channels = Int(file.processingFormat.channelCount)

        let stream = OnsetStream(sampleRate: sampleRate)
        stream.thresholdK = difficulty.thresholdK
        let generator = ChartGenerator(difficulty: difficulty)
        var notes: [Note] = []

        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16384) else {
            throw NSError(domain: "csh.analysis", code: 1)
        }
        var mono = [Float]()

        // Note: read(into:) can throw a spurious error at EOF on compressed
        // files, so stop on framePosition instead of frameLength == 0.
        while file.framePosition < file.length {
            try file.read(into: buffer)
            let frames = Int(buffer.frameLength)
            if frames == 0 { break }
            guard let data = buffer.floatChannelData else { break }

            // Mix to mono.
            mono.removeAll(keepingCapacity: true)
            mono.reserveCapacity(frames)
            if channels == 1 {
                mono.append(contentsOf: UnsafeBufferPointer(start: data[0], count: frames))
            } else {
                for i in 0..<frames {
                    var sum: Float = 0
                    for c in 0..<channels { sum += data[c][i] }
                    mono.append(sum / Float(channels))
                }
            }

            for onset in stream.process(mono) {
                if let note = generator.note(for: onset) {
                    notes.append(note)
                }
            }
        }

        log.info("offline analysis: \(notes.count) notes from \(url.lastPathComponent)")
        return Chart(notes: notes)
    }
}
