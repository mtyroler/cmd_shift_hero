import GameCore
import SwiftUI

struct ResultsView: View {
    @Environment(AppState.self) private var appState
    let score: ScoreState

    private var gradeColor: Color {
        switch score.grade {
        case "S": Color(red: 1, green: 0.85, blue: 0.2)
        case "A": Color(red: 0.1, green: 0.95, blue: 1)
        case "B": Color(red: 0.65, green: 0.45, blue: 1)
        case "C": Color(red: 1, green: 0.55, blue: 0.25)
        default: Color(red: 1, green: 0.3, blue: 0.4)
        }
    }

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.03, blue: 0.10).ignoresSafeArea()

            VStack(spacing: 28) {
                Text(score.grade)
                    .font(.system(size: 120, weight: .black, design: .rounded))
                    .foregroundStyle(gradeColor)
                    .shadow(color: gradeColor.opacity(0.7), radius: 30)

                Text("\(score.score)")
                    .font(.system(size: 52, weight: .black, design: .monospaced))
                    .foregroundStyle(.white)

                HStack(spacing: 36) {
                    stat("PERFECT", "\(score.perfects)", Color(red: 1, green: 0.35, blue: 0.85))
                    stat("GOOD", "\(score.goods)", Color(red: 0.1, green: 0.95, blue: 1))
                    stat("MISS", "\(score.misses)", Color(red: 1, green: 0.3, blue: 0.4))
                    stat("BEST COMBO", "\(score.bestCombo)x", Color(red: 0.65, green: 0.45, blue: 1))
                    stat("ACCURACY", String(format: "%.1f%%", score.accuracy * 100), .white)
                }

                HStack(spacing: 18) {
                    NeonButton(title: "PLAY AGAIN") { appState.restartGame() }
                    NeonButton(title: "MENU") { appState.endGame() }
                }
            }
        }
    }

    private func stat(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(.title, design: .monospaced).weight(.bold))
                .foregroundStyle(color)
            Text(title)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
    }
}
