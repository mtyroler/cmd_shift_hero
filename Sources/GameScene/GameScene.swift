import GameCore
import SpriteKit

/// The gameplay scene: synthwave backdrop, on-screen keyboard, falling-note
/// highway, and score HUD. Every note's position is a pure function of the
/// GameClock — no actions, no accumulated deltas, no drift.
public final class GameScene: SKScene {
    private var keyboard: KeyboardNode!
    private var clock: GameClock?
    private var session: GameSession?

    /// Seconds a note is on screen before its hit moment.
    public var travelTime = 1.8

    private var spawnIndex = 0
    private var activeNotes: [Int: NoteNode] = [:]
    private var noteRadius: CGFloat = 18

    private var scoreLabel: SKLabelNode!
    private var comboLabel: SKLabelNode!
    private var lastDisplayedScore = -1
    private var lastDisplayedCombo = -1

    public func attach(clock: GameClock, session: GameSession) {
        self.clock = clock
        self.session = session
        spawnIndex = 0
        activeNotes.removeAll()
    }

    public override func didMove(to view: SKView) {
        backgroundColor = Theme.background
        scaleMode = .resizeFill
        buildBackdrop()
        buildKeyboard()
        buildHUD()
    }

    public override func didChangeSize(_ oldSize: CGSize) {
        guard keyboard != nil else { return }
        layoutKeyboard()
        layoutHUD()
    }

    // MARK: - Frame loop

    public override func update(_ currentTime: TimeInterval) {
        guard let clock, let session else { return }
        let t = clock.audibleSongTime

        // Spawn notes entering the lookahead window.
        while spawnIndex < session.noteCount {
            let note = session.note(at: spawnIndex)
            if note.time > t + travelTime { break }
            if !session.isJudged(spawnIndex), note.time > t - HitJudgment.goodWindow {
                let node = NoteNode(noteIndex: spawnIndex, key: note.key, radius: noteRadius)
                let target = keyCenter(for: note.key)
                node.position = CGPoint(x: target.x, y: spawnY)
                node.zPosition = 10
                addChild(node)
                activeNotes[spawnIndex] = node
            }
            spawnIndex += 1
        }

        // Position every live note from the clock.
        for (index, node) in activeNotes {
            let note = session.note(at: index)
            let target = keyCenter(for: note.key)
            let progress = (note.time - t) / travelTime
            node.position = CGPoint(
                x: target.x,
                y: target.y + CGFloat(progress) * (spawnY - target.y)
            )
        }

        // Sweep notes whose window expired.
        for index in session.advance(to: t) {
            if let node = activeNotes.removeValue(forKey: index) {
                node.fadeMiss()
            }
            showJudgment(.miss, at: session.note(at: index).key)
        }

        updateHUD()
    }

    private var spawnY: CGFloat { size.height + noteRadius * 2 }

    // MARK: - Input (forwarded by the SwiftUI container)

    public func physicalKeyDown(code: UInt16) {
        guard let position = KeyMap.positionForKeyCode[code] else { return }
        keyboard.setPressed(true, at: position)

        guard let clock, let session else { return }
        if let (judgment, index) = session.registerPress(key: position, at: clock.audibleSongTime) {
            if let node = activeNotes.removeValue(forKey: index) {
                node.explodeHit()
            }
            keyboard.flashHit(at: position, color: judgment == .perfect ? Theme.hitFlash : Theme.rowColor(position.row))
            showJudgment(judgment, at: position)
        }
    }

    public func physicalKeyUp(code: UInt16) {
        guard let position = KeyMap.positionForKeyCode[code] else { return }
        keyboard.setPressed(false, at: position)
    }

    // MARK: - HUD

    private func buildHUD() {
        scoreLabel = SKLabelNode(text: "0")
        scoreLabel.fontName = "Menlo-Bold"
        scoreLabel.fontSize = 30
        scoreLabel.fontColor = Theme.keyText
        scoreLabel.horizontalAlignmentMode = .right
        scoreLabel.zPosition = 50
        addChild(scoreLabel)

        comboLabel = SKLabelNode(text: "")
        comboLabel.fontName = "Menlo-Bold"
        comboLabel.fontSize = 24
        comboLabel.fontColor = Theme.hitFlash
        comboLabel.horizontalAlignmentMode = .left
        comboLabel.zPosition = 50
        addChild(comboLabel)

        layoutHUD()
    }

    private func layoutHUD() {
        scoreLabel?.position = CGPoint(x: size.width - 28, y: size.height - 52)
        comboLabel?.position = CGPoint(x: 28, y: size.height - 52)
    }

    private func updateHUD() {
        guard let session else { return }
        if session.state.score != lastDisplayedScore {
            lastDisplayedScore = session.state.score
            scoreLabel.text = "\(session.state.score)"
            scoreLabel.removeAllActions()
            scoreLabel.run(.sequence([.scale(to: 1.18, duration: 0.05), .scale(to: 1, duration: 0.1)]))
        }
        if session.state.combo != lastDisplayedCombo {
            lastDisplayedCombo = session.state.combo
            let combo = session.state.combo
            comboLabel.text = combo >= 2 ? "\(combo)x COMBO  ·  ×\(session.state.multiplier)" : ""
        }
    }

    private func showJudgment(_ judgment: HitJudgment, at key: KeyPosition) {
        let (text, color): (String, NSColor) = switch judgment {
        case .perfect: ("PERFECT", Theme.hitFlash)
        case .good: ("GOOD", Theme.keyStroke)
        case .miss: ("MISS", .systemRed)
        }
        let label = SKLabelNode(text: text)
        label.fontName = "Menlo-Bold"
        label.fontSize = 15
        label.fontColor = color
        let center = keyCenter(for: key)
        label.position = CGPoint(x: center.x, y: center.y + 46)
        label.zPosition = 40
        addChild(label)
        label.run(.sequence([
            .group([.moveBy(x: 0, y: 26, duration: 0.45), .fadeOut(withDuration: 0.45)]),
            .removeFromParent(),
        ]))
    }

    // MARK: - Layout

    private func buildBackdrop() {
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
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            let line = SKShapeNode(path: path)
            line.strokeColor = Theme.gridLine.withAlphaComponent(0.35 * (1 - t * 0.7))
            line.lineWidth = 1
            grid.addChild(line)
        }
        addChild(grid)
    }

    private func buildKeyboard() {
        keyboard = KeyboardNode(width: min(size.width * 0.86, 980))
        noteRadius = keyboard.keySize * 0.32
        addChild(keyboard)
        layoutKeyboard()
    }

    private func layoutKeyboard() {
        let kbWidth = (10.75 + 0.1 * 9.75) * keyboard.keySize
        keyboard.position = CGPoint(x: (size.width - kbWidth) / 2, y: 28)
    }

    private func keyCenter(for position: KeyPosition) -> CGPoint {
        let local = keyboard.localCenter(for: position)
        return CGPoint(x: keyboard.position.x + local.x, y: keyboard.position.y + local.y)
    }
}
