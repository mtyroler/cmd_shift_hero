import AppKit
import SwiftUI

@main
struct CSHApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup("Command Shift Hero") {
            RootView()
                .environment(appState)
                .frame(minWidth: 960, minHeight: 640)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate()
                }
        }
        .windowResizability(.contentMinSize)
    }
}

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            switch appState.screen {
            case .menu:
                MenuView()
            case .game:
                GameContainerView()
            }
        }
        .preferredColorScheme(.dark)
    }
}
