import GameCore
import SpriteKit

/// The gameplay scene: synthwave backdrop, on-screen keyboard, and (from M2)
/// the falling-note highway driven by the GameClock.
public final class GameScene: SKScene {
    private var keyboard: KeyboardNode!
    public private(set) var clock: GameClock?

    public func attach(clock: GameClock) {
        self.clock = clock
    }

    public override func didMove(to view: SKView) {
        backgroundColor = Theme.background
        scaleMode = .resizeFill
        buildBackdrop()
        buildKeyboard()
    }

    public override func didChangeSize(_ oldSize: CGSize) {
        guard keyboard != nil else { return }
        layoutKeyboard()
    }

    private func buildBackdrop() {
        // Retro perspective grid converging toward the horizon.
        let grid = SKNode()
        grid.zPosition = -10
        let horizon = size.height * 0.78
        for i in 0...14 {
            let x = size.width * CGFloat(i) / 14
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: size.width / 2 + (x - size.width / 2) * 0.25, y: horizon))
            let line = SKShapeNode(path: path)
            line.strokeColor = Theme.gridLine
            line.lineWidth = 1
            grid.addChild(line)
        }
        for i in 1...8 {
            let t = CGFloat(i) / 8
            let y = horizon * (1 - pow(1 - t, 2.2))
            let line = SKShapeNode(path: {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: size.width, y: y))
                return p
            }())
            line.strokeColor = Theme.gridLine.withAlphaComponent(0.35 * (1 - t * 0.7))
            line.lineWidth = 1
            grid.addChild(line)
        }
        addChild(grid)
    }

    private func buildKeyboard() {
        keyboard = KeyboardNode(width: min(size.width * 0.86, 980))
        addChild(keyboard)
        layoutKeyboard()
    }

    private func layoutKeyboard() {
        let kbWidth = (10.75 + 0.1 * 9.75) * keyboard.keySize
        keyboard.position = CGPoint(x: (size.width - kbWidth) / 2, y: 28)
    }

    // MARK: - Input (forwarded by the SwiftUI container)

    public func physicalKeyDown(code: UInt16) {
        guard let position = KeyMap.positionForKeyCode[code] else { return }
        keyboard.setPressed(true, at: position)
        keyboard.flashHit(at: position, color: Theme.rowColor(position.row))
    }

    public func physicalKeyUp(code: UInt16) {
        guard let position = KeyMap.positionForKeyCode[code] else { return }
        keyboard.setPressed(false, at: position)
    }
}
