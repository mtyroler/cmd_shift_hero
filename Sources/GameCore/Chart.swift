public struct Note: Codable, Sendable, Hashable {
    /// Seconds on the song timeline (capture timeline for live play).
    public let time: Double
    public let key: KeyPosition

    public init(time: Double, key: KeyPosition) {
        self.time = time
        self.key = key
    }
}

public struct Chart: Codable, Sendable {
    /// Notes sorted ascending by time.
    public private(set) var notes: [Note]

    public init(notes: [Note]) {
        self.notes = notes.sorted { $0.time < $1.time }
    }

    public mutating func append(_ note: Note) {
        // Live charts append in time order; sort defensively only when needed.
        if let last = notes.last, note.time < last.time {
            notes.append(note)
            notes.sort { $0.time < $1.time }
        } else {
            notes.append(note)
        }
    }
}
