import MusicBridge
import SwiftUI

struct LibraryBrowserView: View {
    @Environment(AppState.self) private var appState
    @State private var query = ""

    private var filtered: [LibraryTrack] {
        guard !query.isEmpty else { return appState.libraryTracks }
        let q = query.lowercased()
        return appState.libraryTracks.filter {
            $0.title.lowercased().contains(q)
                || $0.artist.lowercased().contains(q)
                || $0.album.lowercased().contains(q)
        }
    }

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.03, blue: 0.10).ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    NeonButton(title: "BACK") { appState.closeLibrary() }
                    TextField("search your library…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.title3.monospaced())
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.07, green: 0.08, blue: 0.18)))
                    Text("\(filtered.count) songs")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                .padding(16)

                if let error = appState.libraryError {
                    Spacer()
                    Text(error)
                        .font(.body.monospaced())
                        .foregroundStyle(.red)
                        .padding()
                    Spacer()
                } else if appState.libraryTracks.isEmpty {
                    Spacer()
                    ProgressView("reading your Music library…")
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(filtered) { track in
                                TrackRow(track: track)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }

                Text("click a song to play it — Music.app stays silent; you hear the game's delayed copy")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 10)
            }
        }
    }
}

private struct TrackRow: View {
    @Environment(AppState.self) private var appState
    let track: LibraryTrack
    @State private var artwork: NSImage?
    @State private var hovering = false

    var body: some View {
        Button {
            appState.startMusicTrack(track)
        } label: {
            HStack(spacing: 12) {
                Group {
                    if let artwork {
                        Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(red: 0.07, green: 0.08, blue: 0.18))
                            .overlay(Image(systemName: "music.note").foregroundStyle(.tertiary))
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.body.monospaced().weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(track.artist)  ·  \(track.album)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(timeString(track.duration))
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(hovering ? Color(red: 0.10, green: 0.12, blue: 0.26) : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .task {
            artwork = appState.artwork(for: track)
        }
    }

    private func timeString(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
