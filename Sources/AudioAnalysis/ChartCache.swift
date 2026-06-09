import Foundation
import GameCore
import os

/// Per-track analysis cached on disk. Onset times are normalized to the
/// first audible sample, so charts are portable across plays despite the
/// variable lead-in before Music starts making sound.
public struct CachedAnalysis: Codable, Sendable {
    public var version: Int
    public var trackID: String       // AppleScript persistent ID (hex)
    public var duration: Double
    public var playCount: Int
    public var onsets: [DetectedOnset]

    public init(version: Int, trackID: String, duration: Double,
                playCount: Int, onsets: [DetectedOnset]) {
        self.version = version
        self.trackID = trackID
        self.duration = duration
        self.playCount = playCount
        self.onsets = onsets
    }
}

public enum ChartCache {
    private static let log = Logger(subsystem: "com.maxtyroler.csh", category: "ChartCache")
    /// Same-band onsets closer than this are considered the same event.
    private static let dedupeWindow = 0.03

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("CommandShiftHero/Charts", isDirectory: true)
    }

    private static func url(for trackID: String) -> URL {
        directory.appendingPathComponent("\(trackID).json")
    }

    public static func load(trackID: String) -> CachedAnalysis? {
        guard let data = try? Data(contentsOf: url(for: trackID)),
              let cached = try? JSONDecoder().decode(CachedAnalysis.self, from: data),
              cached.version == AnalysisVersion.current
        else { return nil }
        return cached
    }

    public static func save(_ analysis: CachedAnalysis) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(analysis)
            try data.write(to: url(for: analysis.trackID), options: .atomic)
            log.info("cached \(analysis.onsets.count) onsets for \(analysis.trackID) (play \(analysis.playCount))")
        } catch {
            log.error("cache save failed: \(error.localizedDescription)")
        }
    }

    /// Union of an existing analysis and a new play's onsets: keeps every
    /// distinct event, prefers the higher-energy duplicate.
    public static func merge(existing: CachedAnalysis?, newOnsets: [DetectedOnset],
                             trackID: String, duration: Double) -> CachedAnalysis {
        var pool = (existing?.onsets ?? []) + newOnsets
        pool.sort { $0.time < $1.time }

        var merged: [DetectedOnset] = []
        for onset in pool {
            if let lastIdx = merged.lastIndex(where: { $0.band == onset.band }),
               onset.time - merged[lastIdx].time < dedupeWindow {
                if onset.energy > merged[lastIdx].energy {
                    merged[lastIdx] = onset
                }
            } else {
                merged.append(onset)
            }
        }

        return CachedAnalysis(
            version: AnalysisVersion.current,
            trackID: trackID,
            duration: duration,
            playCount: (existing?.playCount ?? 0) + 1,
            onsets: merged
        )
    }

    /// Builds a playable chart (times still relative to audio start; the
    /// caller shifts by the current play's audio-start offset).
    public static func chart(from analysis: CachedAnalysis, difficulty: Difficulty) -> Chart {
        let generator = ChartGenerator(difficulty: difficulty)
        var notes: [Note] = []
        for onset in analysis.onsets {
            if let note = generator.note(for: onset) {
                notes.append(note)
            }
        }
        return Chart(notes: notes)
    }
}
