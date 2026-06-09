import SwiftUI

struct CalibrationView: View {
    @Environment(AppState.self) private var appState
    @State private var calibrator = Calibrator()
    @State private var keyMonitor: Any?
    @State private var failed = false

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.03, blue: 0.10).ignoresSafeArea()

            VStack(spacing: 30) {
                Text("LATENCY CALIBRATION")
                    .font(.system(.title, design: .monospaced).weight(.black))
                    .kerning(3)
                    .foregroundStyle(Color(red: 0.1, green: 0.95, blue: 1))

                Text("Press SPACE exactly on each click — \(Calibrator.tapsNeeded) taps")
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)

                Text("\(calibrator.taps.count) / \(Calibrator.tapsNeeded)")
                    .font(.system(size: 64, weight: .black, design: .monospaced))
                    .foregroundStyle(.white)

                if calibrator.isDone, let suggestion = calibrator.suggestedCalibration {
                    VStack(spacing: 16) {
                        Text(String(format: "your offset: %+.0f ms", -suggestion * 1000))
                            .font(.title2.monospaced())
                            .foregroundStyle(Color(red: 1, green: 0.35, blue: 0.85))
                        HStack(spacing: 16) {
                            NeonButton(title: "SAVE") {
                                appState.calibrationOffset = suggestion
                                appState.screen = .menu
                            }
                            NeonButton(title: "RETRY") { try? calibrator.start() }
                        }
                    }
                } else if failed {
                    Text("audio engine failed to start")
                        .foregroundStyle(.red)
                }

                NeonButton(title: "BACK") { appState.screen = .menu }
            }
        }
        .onAppear {
            do { try calibrator.start() } catch { failed = true }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 49, !event.isARepeat { // Space
                    calibrator.registerTap()
                    return nil
                }
                if event.keyCode == 53 { // Esc
                    appState.screen = .menu
                    return nil
                }
                return event
            }
        }
        .onDisappear {
            calibrator.stop()
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
        }
    }
}
