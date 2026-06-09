/// Physical-position key mapping for the three letter rows.
/// Mapping is by hardware keyCode (Carbon kVK_ANSI_* values), so it works
/// regardless of the user's keyboard layout language.

public enum KeyRow: Int, CaseIterable, Codable, Sendable, Hashable {
    case top = 0     // QWERTYUIOP
    case home = 1    // ASDFGHJKL
    case bottom = 2  // ZXCVBNM

    public var keyCount: Int { KeyMap.letters[rawValue].count }

    /// Horizontal stagger of this row relative to the top row, in key widths,
    /// mirroring a physical ANSI keyboard.
    public var stagger: Double {
        switch self {
        case .top: 0.0
        case .home: 0.25
        case .bottom: 0.75
        }
    }
}

public struct KeyPosition: Hashable, Codable, Sendable {
    public let row: KeyRow
    public let column: Int

    public init(row: KeyRow, column: Int) {
        self.row = row
        self.column = column
    }

    public var letter: Character { KeyMap.letters[row.rawValue][column] }
}

public enum KeyMap {
    public static let letters: [[Character]] = [
        Array("QWERTYUIOP"),
        Array("ASDFGHJKL"),
        Array("ZXCVBNM"),
    ]

    /// kVK_ANSI_* hardware key codes → grid position.
    public static let positionForKeyCode: [UInt16: KeyPosition] = {
        let codes: [[UInt16]] = [
            // Q     W     E     R     T     Y     U     I     O     P
            [0x0C, 0x0D, 0x0E, 0x0F, 0x11, 0x10, 0x20, 0x22, 0x1F, 0x23],
            // A     S     D     F     G     H     J     K     L
            [0x00, 0x01, 0x02, 0x03, 0x05, 0x04, 0x26, 0x28, 0x25],
            // Z     X     C     V     B     N     M
            [0x06, 0x07, 0x08, 0x09, 0x0B, 0x2D, 0x2E],
        ]
        var map: [UInt16: KeyPosition] = [:]
        for (r, rowCodes) in codes.enumerated() {
            for (c, code) in rowCodes.enumerated() {
                map[code] = KeyPosition(row: KeyRow(rawValue: r)!, column: c)
            }
        }
        return map
    }()

    public static var allPositions: [KeyPosition] {
        KeyRow.allCases.flatMap { row in
            (0..<row.keyCount).map { KeyPosition(row: row, column: $0) }
        }
    }
}
