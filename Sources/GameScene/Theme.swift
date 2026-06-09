import AppKit
import GameCore

/// Neon synthwave palette.
public enum Theme {
    public static let background = NSColor(red: 0.04, green: 0.03, blue: 0.10, alpha: 1)
    public static let gridLine = NSColor(red: 0.55, green: 0.15, blue: 0.75, alpha: 0.35)
    public static let keyStroke = NSColor(red: 0.0, green: 0.85, blue: 1.0, alpha: 0.9)
    public static let keyFill = NSColor(red: 0.07, green: 0.08, blue: 0.18, alpha: 0.9)
    public static let keyText = NSColor(red: 0.75, green: 0.95, blue: 1.0, alpha: 1)
    public static let hitFlash = NSColor(red: 1.0, green: 0.35, blue: 0.85, alpha: 1)

    /// Per-row note colors: highs hot pink, mids cyan, lows violet.
    public static func rowColor(_ row: KeyRow) -> NSColor {
        switch row {
        case .top: NSColor(red: 1.0, green: 0.35, blue: 0.75, alpha: 1)
        case .home: NSColor(red: 0.10, green: 0.95, blue: 1.0, alpha: 1)
        case .bottom: NSColor(red: 0.65, green: 0.45, blue: 1.0, alpha: 1)
        }
    }
}
