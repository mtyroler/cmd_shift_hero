import Foundation
import os

public enum MusicRemoteError: Error, LocalizedError {
    case scriptError(String)

    public var errorDescription: String? {
        switch self {
        case .scriptError(let message): "Music control failed: \(message)"
        }
    }
}

/// Controls Music.app playback via raw AppleScript (NSAppleScript, not
/// ScriptingBridge — the latter is unreliable on macOS 26). First use
/// triggers the Apple Events permission prompt (NSAppleEventsUsageDescription).
///
/// Deliberately minimal: play-by-ID, pause, resume, stop. We never read
/// `player position` — the tapped audio stream is the timing ground truth.
@MainActor
public final class MusicRemote {
    private static let log = Logger(subsystem: "com.maxtyroler.csh", category: "MusicRemote")

    public init() {}

    /// Starts playing the library track with the given AppleScript persistent
    /// ID (uppercase hex). Works for subscription/cloud tracks in the library.
    public func play(persistentIDHex: String) throws {
        // IDs are hex we generate ourselves, but never interpolate untrusted
        // strings into AppleScript.
        precondition(persistentIDHex.allSatisfy(\.isHexDigit))
        try run("""
        tell application "Music"
            play (first track of library playlist 1 whose persistent ID is "\(persistentIDHex)")
        end tell
        """)
    }

    /// Launches Music.app without bringing it to the front; returns once it
    /// is running (so its PID can be resolved for the tap).
    public func launch() throws {
        try run("tell application \"Music\" to launch")
    }

    public func pause() throws {
        try run("tell application \"Music\" to pause")
    }

    public func resume() throws {
        try run("tell application \"Music\" to play")
    }

    public func stop() throws {
        try run("tell application \"Music\" to stop")
    }

    private func run(_ source: String) throws {
        guard let script = NSAppleScript(source: source) else {
            throw MusicRemoteError.scriptError("could not compile script")
        }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let error {
            let message = (error[NSAppleScript.errorMessage] as? String) ?? "\(error)"
            Self.log.error("AppleScript error: \(message)")
            throw MusicRemoteError.scriptError(message)
        }
    }
}
