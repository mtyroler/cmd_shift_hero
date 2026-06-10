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

    /// Starts playing a library track. Tries the AppleScript persistent ID
    /// (uppercase hex) with retries — Music's scripting engine can answer
    /// -1700 while the app is still warming up — then falls back to a
    /// name + artist match.
    public func play(persistentIDHex: String, title: String, artist: String) async throws {
        // IDs are hex we generate ourselves, but never interpolate untrusted
        // strings into AppleScript.
        precondition(persistentIDHex.allSatisfy(\.isHexDigit))
        let byID = """
        tell application "Music"
            play (first track of library playlist 1 whose persistent ID is "\(persistentIDHex)")
        end tell
        """

        var lastError: Error?
        for attempt in 1...3 {
            do {
                try run(byID)
                return
            } catch {
                lastError = error
                Self.log.warning("play by ID attempt \(attempt) failed: \(error.localizedDescription)")
                try? await Task.sleep(for: .milliseconds(700))
            }
        }

        // Fallback: match by metadata (handles rare ITLib/AppleScript ID
        // disagreements).
        let byName = """
        tell application "Music"
            play (first track of library playlist 1 whose name is \(quoted(title)) and artist is \(quoted(artist)))
        end tell
        """
        do {
            try run(byName)
            Self.log.info("played via name+artist fallback: \(title)")
        } catch {
            throw MusicRemoteError.scriptError(
                "couldn't start \"\(title)\" (\(persistentIDHex)): \(lastError?.localizedDescription ?? error.localizedDescription)"
            )
        }
    }

    private func quoted(_ s: String) -> String {
        "\"" + s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
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
