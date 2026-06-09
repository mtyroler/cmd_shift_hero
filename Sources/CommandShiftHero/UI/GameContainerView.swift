import GameCore
import GameScene
import SpriteKit
import SwiftUI

struct GameContainerView: View {
    @Environment(AppState.self) private var appState
    @State private var scene = GameScene()
    @State private var keyMonitor: Any?
    @State private var lastFlags: NSEvent.ModifierFlags = []
    private let drainCheck = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            SpriteView(scene: scene, preferredFramesPerSecond: 120)
                .ignoresSafeArea()

            if appState.isPaused {
                PauseOverlay()
            }
        }
        .onAppear {
            if let clock = appState.player, let session = appState.session {
                scene.attach(clock: clock, session: session)
            }
            installKeyMonitor()
        }
        .onDisappear(perform: removeKeyMonitor)
        .onChange(of: appState.isPaused) { _, paused in
            scene.isPaused = paused
        }
        .onReceive(drainCheck) { _ in
            // Song over once the feeder finished and the buffer drained.
            if !appState.isPaused, appState.player?.isDrained == true {
                appState.finishGame()
            }
        }
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { event in
            switch event.type {
            case .flagsChanged:
                return handleFlags(event)
            case .keyDown:
                return handleKeyDown(event)
            case .keyUp:
                scene.physicalKeyUp(code: event.keyCode)
                return KeyMap.positionForKeyCode[event.keyCode] != nil ? nil : event
            default:
                return event
            }
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        if event.keyCode == 53 { // Esc toggles pause
            appState.isPaused ? appState.resumeGame() : appState.pauseGame()
            return nil
        }
        if appState.isPaused {
            switch event.keyCode {
            case 15: appState.restartGame(); return nil  // R
            case 12: appState.endGame(); return nil      // Q
            default: return event
            }
        }
        guard !event.isARepeat else { return nil }
        scene.physicalKeyDown(code: event.keyCode)
        // Swallow letter keys so system shortcuts/beeps never fire mid-game.
        return KeyMap.positionForKeyCode[event.keyCode] != nil ? nil : event
    }

    /// Shift = star power; Cmd+Shift = finisher (on the Shift press).
    private func handleFlags(_ event: NSEvent) -> NSEvent? {
        defer { lastFlags = event.modifierFlags }
        let added = event.modifierFlags.subtracting(lastFlags)
        guard !appState.isPaused else { return event }
        if added.contains(.shift) {
            if event.modifierFlags.contains(.command) {
                scene.finisherPressed()
            } else {
                scene.shiftPressed()
            }
        }
        return event
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}

struct PauseOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
            VStack(spacing: 18) {
                Text("PAUSED")
                    .font(.system(size: 46, weight: .black, design: .monospaced))
                    .kerning(6)
                    .foregroundStyle(Color(red: 0.1, green: 0.95, blue: 1))
                Text("ESC resume   ·   R restart   ·   Q quit")
                    .font(.title3.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
