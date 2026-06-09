import AppKit
import Foundation
import iTunesLibrary

public struct LibraryTrack: Identifiable, Sendable, Hashable {
    public let id: UInt64          // ITLib persistent ID
    public let title: String
    public let artist: String
    public let album: String
    public let duration: Double    // seconds

    /// AppleScript's `persistent ID` is this value as uppercase hex.
    public var persistentIDHex: String { String(format: "%016llX", id) }
}

/// Read-only Apple Music library access via iTunesLibrary.framework.
/// First use triggers the Media Library permission prompt
/// (NSAppleMusicUsageDescription). Works for cloud/subscription tracks.
public final class MusicLibrary {
    private let library: ITLibrary
    private var itemsByID: [UInt64: ITLibMediaItem] = [:]

    public init() throws {
        library = try ITLibrary(apiVersion: "1.1")
    }

    /// All songs, sorted by artist then title.
    public func songs() -> [LibraryTrack] {
        var tracks: [LibraryTrack] = []
        for item in library.allMediaItems where item.mediaKind == .kindSong {
            itemsByID[item.persistentID.uint64Value] = item
            tracks.append(LibraryTrack(
                id: item.persistentID.uint64Value,
                title: item.title,
                artist: item.artist?.name ?? "Unknown Artist",
                album: item.album.title ?? "",
                duration: Double(item.totalTime) / 1000.0
            ))
        }
        return tracks.sorted {
            ($0.artist.lowercased(), $0.title.lowercased())
                < ($1.artist.lowercased(), $1.title.lowercased())
        }
    }

    /// Album artwork, if Music has it locally. Call songs() first.
    public func artwork(for trackID: UInt64) -> NSImage? {
        itemsByID[trackID]?.artwork?.image
    }
}
