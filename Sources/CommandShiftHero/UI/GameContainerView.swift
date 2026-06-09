import GameCore
import GameScene
import SpriteKit
import SwiftUI

struct GameContainerView: View {
    @Environment(AppState.self) private var appState
    @State private var scene = GameScene()
    @State private var keyMonitor: Any?
    private let drainCheck = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        SpriteView(scene: scene, preferredFramesPerSecond: 120)
            .ignoresSafeArea()
            .onAppear {
                if let clock = appState.player, let session = appState.session {
                    scene.attach(clock: clock, session: session)
                }
                installKeyMonitor()
            }
            .onDisappear(perform: removeKeyMonitor)
            .onReceive(drainCheck) { _ in
                // Song over once the feeder finished and the buffer drained.
                if appState.player?.isDrained == true {
                    appState.endGame()
                }
            }
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
            return KeyMap.positionForKeyCode[event.keyCode] != nil ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}
