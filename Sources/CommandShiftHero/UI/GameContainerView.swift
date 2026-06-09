import GameScene
import SpriteKit
import SwiftUI

struct GameContainerView: View {
    @Environment(AppState.self) private var appState
    @State private var scene = GameScene()
    @State private var keyMonitor: Any?

    var body: some View {
        SpriteView(scene: scene, preferredFramesPerSecond: 120)
            .ignoresSafeArea()
            .onAppear {
                if let clock = appState.player {
                    scene.attach(clock: clock)
                }
                installKeyMonitor()
            }
            .onDisappear(perform: removeKeyMonitor)
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            if event.type == .keyDown {
                if event.keyCode == 53 { // Esc — leave the game
                    appState.endGame()
                    return nil
                }
                guard !event.isARepeat else { return nil }
                scene.physicalKeyDown(code: event.keyCode)
            } else {
                scene.physicalKeyUp(code: event.keyCode)
            }
            // Swallow letter keys so the system beep never fires during play.
            return GameCoreKeyCodes.isLetter(event.keyCode) || event.keyCode == 53 ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}

import GameCore

enum GameCoreKeyCodes {
    static func isLetter(_ code: UInt16) -> Bool {
        KeyMap.positionForKeyCode[code] != nil
    }
}
