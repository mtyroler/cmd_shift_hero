import AudioAnalysis
import SwiftUI

struct MenuView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.03, blue: 0.10).ignoresSafeArea()

            VStack(spacing: 36) {
                VStack(spacing: 8) {
                    Text("⌘⇧")
                        .font(.system(size: 64, weight: .black))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(red: 1, green: 0.35, blue: 0.75), Color(red: 0.1, green: 0.95, blue: 1)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                    Text("COMMAND SHIFT HERO")
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .kerning(4)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(red: 1, green: 0.35, blue: 0.75), Color(red: 0.65, green: 0.45, blue: 1), Color(red: 0.1, green: 0.95, blue: 1)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .shadow(color: Color(red: 1, green: 0.35, blue: 0.75).opacity(0.6), radius: 18)
                    Text("your keyboard is the instrument")
                        .font(.system(.title3, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 18) {
                    HStack(spacing: 10) {
                        ForEach(Difficulty.allCases, id: \.self) { level in
                            DifficultyChip(level: level, selected: appState.difficulty == level) {
                                appState.difficulty = level
                            }
                        }
                    }

                    NeonButton(title: appState.isAnalyzing ? "ANALYZING…" : "PLAY DEMO TRACK") {
                        appState.startDemo()
                    }

                    HStack(spacing: 14) {
                        NeonButton(title: "APPLE MUSIC LIBRARY") { appState.openLibrary() }
                        NeonButton(title: "CALIBRATE") { appState.screen = .calibration }
                    }

                    Text("SHIFT star power  ·  ⌘⇧ finisher  ·  ESC pause")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                if let error = appState.lastError {
                    Text(error)
                        .font(.caption.monospaced())
                        .foregroundStyle(.red)
                }
            }
        }
    }
}

struct DifficultyChip: View {
    let level: Difficulty
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(level.rawValue.uppercased())
                .font(.caption.monospaced().weight(.bold))
                .kerning(1.5)
                .foregroundStyle(selected ? .black : Color(red: 0.65, green: 0.45, blue: 1))
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(selected ? Color(red: 0.65, green: 0.45, blue: 1) : Color(red: 0.07, green: 0.08, blue: 0.18))
                        .overlay(Capsule().stroke(Color(red: 0.65, green: 0.45, blue: 1).opacity(0.6), lineWidth: 1.5))
                )
        }
        .buttonStyle(.plain)
    }
}

struct NeonButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(.title2, design: .monospaced).weight(.bold))
                .kerning(2)
                .foregroundStyle(Color(red: 0.1, green: 0.95, blue: 1))
                .padding(.horizontal, 36)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(red: 0.1, green: 0.95, blue: 1).opacity(hovering ? 1 : 0.6), lineWidth: 2)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(red: 0.07, green: 0.08, blue: 0.18).opacity(0.9))
                        )
                )
                .shadow(color: Color(red: 0.1, green: 0.95, blue: 1).opacity(hovering ? 0.8 : 0.3), radius: 12)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
