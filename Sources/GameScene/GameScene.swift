import AppKit
import GameCore
import SpriteKit

/// Song metadata shown in the gameplay HUD.
public struct SongHUDInfo {
    public let title: String
    public let artist: String
    public let duration: Double?
    public let artwork: NSImage?

    public init(title: String, artist: String, duration: Double?, artwork: NSImage?) {
        self.title = title
        self.artist = artist
        self.duration = duration
        self.artwork = artwork
    }
}

/// The gameplay scene: synthwave backdrop, on-screen keyboard, falling-note
/// highway, and score HUD. Every note's position is a pure function of the
/// GameClock — no actions, no accumulated deltas, no drift.
public final class GameScene: SKScene {
    private var keyboard: KeyboardNode!
    private var clock: GameClock?
    private var session: GameSession?
    private var songInfo: SongHUDInfo?

    /// Seconds a note is on screen before its hit moment. Must stay under
    /// the live-detection lookahead (~2.2 s of the 2.5 s tap delay).
    public var travelTime = 2.0

    private var spawnIndex = 0
    private var activeNotes: [Int: NoteNode] = [:]
    private var noteRadius: CGFloat = 18

    private var scoreLabel: SKLabelNode!
    private var comboLabel: SKLabelNode!
    private var starBarBack: SKShapeNode!
    private var starBarFill: SKShapeNode!
    private var starOverlay: SKShapeNode!
    private var readyLabel: SKLabelNode!
    private var missOverlay: SKShapeNode!
    private var songLabel: SKLabelNode!
    private var artworkNode: SKSpriteNode?
    private var progressFill: SKSpriteNode!
    private var lastDisplayedScore = -1
    private var lastDisplayedCombo = -1
    private var lastStarMeter = -1.0
    private var lastStarActive = false
    private var lastMultiplier = 1
    private let starBarWidth: CGFloat = 220

    public func attach(clock: GameClock, session: GameSession, song: SongHUDInfo? = nil) {
        self.clock = clock
        self.session = session
        self.songInfo = song
        spawnIndex = 0
        activeNotes.removeAll()
        if songLabel != nil { applySongInfo() }
    }

    public override func didMove(to view: SKView) {
        backgroundColor = Theme.background
        buildBackdrop()
        buildKeyboard()
        buildHUD()
    }

    public override func didChangeSize(_ oldSize: CGSize) {
        // Rebuild the size-dependent layers (live note nodes reposition
        // themselves from the clock every frame regardless).
        guard keyboard != nil, oldSize != size else { return }
        backdrop?.removeFromParent()
        buildBackdrop()
        keyboard.removeFromParent()
        buildKeyboard()
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
                backdrop?.pulse(0.35)
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
        let comboBeforeSweep = session.state.combo
        let missed = session.advance(to: t)
        for index in missed {
            if let node = activeNotes.removeValue(forKey: index) {
                node.fadeMiss()
            }
            showJudgment(.miss, at: session.note(at: index).key)
        }
        if !missed.isEmpty, comboBeforeSweep >= 10 {
            flashComboBreak()
        }

        backdrop?.update(time: currentTime, combo: session.state.combo,
                         starActive: session.starPowerActive)
        updateHUD(at: t)
    }

    private var spawnY: CGFloat { size.height + noteRadius * 2 }

    // MARK: - Input (forwarded by the SwiftUI container)

    public func physicalKeyDown(code: UInt16) {
        guard let position = KeyMap.positionForKeyCode[code] else { return }
        keyboard.setPressed(true, at: position)

        guard let clock, let session else { return }
        if let (judgment, index) = session.registerPress(key: position, at: clock.audibleSongTime) {
            if let node = activeNotes.removeValue(forKey: index) {
                if judgment == .perfect {
                    sparkBurst(at: node.position, color: Theme.rowColor(position.row), count: 7)
                    ripple(at: node.position, color: Theme.rowColor(position.row))
                }
                node.explodeHit()
            }
            keyboard.flashHit(at: position, color: judgment == .perfect ? Theme.hitFlash : Theme.rowColor(position.row))
            showJudgment(judgment, at: position)
            backdrop?.pulse(judgment == .perfect ? 1.0 : 0.7)
        }
    }

    public func physicalKeyUp(code: UInt16) {
        guard let position = KeyMap.positionForKeyCode[code] else { return }
        keyboard.setPressed(false, at: position)
    }

    /// Shift pressed (no Cmd): star power if the meter is full.
    public func shiftPressed() {
        guard let clock, let session else { return }
        if session.tryActivateStarPower(at: clock.audibleSongTime) {
            announce("STAR POWER", color: Theme.starGold)
            ripple(at: CGPoint(x: size.width / 2, y: size.height * 0.5),
                   color: Theme.starGold, maxScale: 30)
        }
    }

    /// Cmd+Shift: finisher — perfect-clears the visible notes.
    public func finisherPressed() {
        guard let clock, let session else { return }
        guard let cleared = session.tryFinisher(at: clock.audibleSongTime) else { return }
        announce("⌘⇧ FINISHER", color: .white)
        backdrop?.pulse(1)
        ripple(at: CGPoint(x: size.width / 2, y: keyboard.position.y + keyboard.blockHeight),
               color: .white, maxScale: 40)
        for index in cleared {
            if let node = activeNotes.removeValue(forKey: index) {
                sparkBurst(at: node.position, color: Theme.hitFlash, count: 10)
                node.explodeHit()
            }
        }
    }

    private func announce(_ text: String, color: NSColor, fontSize: CGFloat = 46) {
        let label = SKLabelNode(text: text)
        label.fontName = "Menlo-Bold"
        label.fontSize = fontSize
        label.fontColor = color
        label.position = CGPoint(x: size.width / 2, y: size.height * 0.55)
        label.zPosition = 60
        label.setScale(0.4)
        addChild(label)
        label.run(.sequence([
            .group([.scale(to: 1.0, duration: 0.18), .fadeIn(withDuration: 0.1)]),
            .wait(forDuration: 0.7),
            .fadeOut(withDuration: 0.3),
            .removeFromParent(),
        ]))
    }

    /// Cheap neon spark burst (shape nodes, no textures).
    private func sparkBurst(at point: CGPoint, color: NSColor, count: Int) {
        for _ in 0..<count {
            let spark = SKShapeNode(circleOfRadius: CGFloat.random(in: 1.5...3))
            spark.fillColor = color
            spark.strokeColor = .clear
            spark.glowWidth = 2
            spark.position = point
            spark.zPosition = 30
            addChild(spark)
            let angle = CGFloat.random(in: 0..<(2 * .pi))
            let distance = CGFloat.random(in: 30...80)
            spark.run(.sequence([
                .group([
                    .moveBy(x: cos(angle) * distance, y: sin(angle) * distance, duration: 0.35),
                    .fadeOut(withDuration: 0.35),
                ]),
                .removeFromParent(),
            ]))
        }
    }

    /// Expanding neon ring.
    private func ripple(at point: CGPoint, color: NSColor, maxScale: CGFloat = 6) {
        let ring = SKShapeNode(circleOfRadius: 8)
        ring.fillColor = .clear
        ring.strokeColor = color
        ring.lineWidth = 2
        ring.glowWidth = 3
        ring.position = point
        ring.zPosition = 25
        addChild(ring)
        ring.run(.sequence([
            .group([.scale(to: maxScale, duration: 0.45), .fadeOut(withDuration: 0.45)]),
            .removeFromParent(),
        ]))
    }

    /// Brief red edge wash when a 10+ combo dies.
    private func flashComboBreak() {
        missOverlay.removeAllActions()
        missOverlay.alpha = 0
        missOverlay.run(.sequence([
            .fadeAlpha(to: 0.12, duration: 0.06),
            .fadeAlpha(to: 0, duration: 0.35),
        ]))
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

        starBarBack = SKShapeNode(rect: CGRect(x: 0, y: 0, width: starBarWidth, height: 10), cornerRadius: 5)
        starBarBack.fillColor = Theme.keyFill
        starBarBack.strokeColor = Theme.keyStroke.withAlphaComponent(0.4)
        starBarBack.zPosition = 50
        addChild(starBarBack)

        starBarFill = SKShapeNode(rect: CGRect(x: 0, y: 0, width: starBarWidth, height: 10), cornerRadius: 5)
        starBarFill.fillColor = Theme.hitFlash
        starBarFill.strokeColor = .clear
        starBarFill.glowWidth = 3
        starBarFill.xScale = 0
        starBarFill.zPosition = 51
        addChild(starBarFill)

        readyLabel = SKLabelNode(text: "⇧ READY")
        readyLabel.fontName = "Menlo-Bold"
        readyLabel.fontSize = 13
        readyLabel.fontColor = Theme.starGold
        readyLabel.horizontalAlignmentMode = .left
        readyLabel.zPosition = 51
        readyLabel.isHidden = true
        addChild(readyLabel)

        songLabel = SKLabelNode(text: "")
        songLabel.fontName = "Menlo-Bold"
        songLabel.fontSize = 12
        songLabel.fontColor = Theme.keyText.withAlphaComponent(0.75)
        songLabel.zPosition = 50
        addChild(songLabel)

        let progressBack = SKSpriteNode(color: Theme.keyFill, size: CGSize(width: size.width, height: 3))
        progressBack.anchorPoint = .zero
        progressBack.zPosition = 50
        progressBack.name = "progressBack"
        addChild(progressBack)

        progressFill = SKSpriteNode(color: Theme.hitFlash, size: CGSize(width: size.width, height: 3))
        progressFill.anchorPoint = .zero
        progressFill.xScale = 0
        progressFill.zPosition = 51
        addChild(progressFill)

        // Full-screen wash shown while star power is active.
        starOverlay = SKShapeNode(rect: CGRect(origin: .zero, size: CGSize(width: 4000, height: 3000)))
        starOverlay.fillColor = Theme.starGold
        starOverlay.strokeColor = .clear
        starOverlay.alpha = 0
        starOverlay.zPosition = -5
        addChild(starOverlay)

        // Full-screen red wash for combo breaks.
        missOverlay = SKShapeNode(rect: CGRect(origin: .zero, size: CGSize(width: 4000, height: 3000)))
        missOverlay.fillColor = Theme.missRed
        missOverlay.strokeColor = .clear
        missOverlay.alpha = 0
        missOverlay.zPosition = -4
        addChild(missOverlay)

        applySongInfo()
        layoutHUD()
    }

    private func applySongInfo() {
        artworkNode?.removeFromParent()
        artworkNode = nil
        guard let songInfo else {
            songLabel.text = ""
            return
        }
        songLabel.text = songInfo.artist.isEmpty
            ? songInfo.title
            : "\(songInfo.title) — \(songInfo.artist)"
        if let image = songInfo.artwork {
            let sprite = SKSpriteNode(texture: SKTexture(image: image))
            sprite.size = CGSize(width: 26, height: 26)
            sprite.zPosition = 50
            addChild(sprite)
            artworkNode = sprite
        }
        layoutHUD()
    }

    private func layoutHUD() {
        scoreLabel?.position = CGPoint(x: size.width - 28, y: size.height - 52)
        comboLabel?.position = CGPoint(x: 28, y: size.height - 52)
        starBarBack?.position = CGPoint(x: (size.width - starBarWidth) / 2, y: size.height - 46)
        starBarFill?.position = starBarBack.position
        readyLabel?.position = CGPoint(x: (size.width + starBarWidth) / 2 + 12, y: size.height - 45)
        songLabel?.position = CGPoint(x: size.width / 2, y: size.height - 24)
        if let songLabel, let artworkNode {
            artworkNode.position = CGPoint(
                x: songLabel.position.x - songLabel.frame.width / 2 - 22,
                y: size.height - 19
            )
        }
        if let back = childNode(withName: "progressBack") as? SKSpriteNode {
            back.size.width = size.width
            back.position = CGPoint(x: 0, y: size.height - 3)
        }
        progressFill?.size.width = size.width
        progressFill?.position = CGPoint(x: 0, y: size.height - 3)
    }

    private func updateHUD(at t: Double) {
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
        // Multiplier tier-ups get a shout (×2 at 10, ×3 at 20, ×4 at 30).
        let multiplier = session.state.multiplier
        if multiplier > lastMultiplier {
            announce("×\(multiplier)", color: Theme.keyStroke, fontSize: 36)
        }
        lastMultiplier = multiplier

        // Meter: gold countdown while star power runs, fill level otherwise.
        let displayedMeter: Double
        if let remaining = session.starPowerRemaining(at: t) {
            displayedMeter = remaining / GameSession.starPowerDuration
            starBarFill.fillColor = Theme.starGold
        } else {
            displayedMeter = session.starMeter
            starBarFill.fillColor = Theme.hitFlash
        }
        if displayedMeter != lastStarMeter {
            lastStarMeter = displayedMeter
            starBarFill.xScale = CGFloat(displayedMeter)
        }
        let ready = !session.starPowerActive && session.starMeter >= 1
        if ready != !readyLabel.isHidden {
            readyLabel.isHidden = !ready
            if ready {
                starBarFill.run(.repeatForever(.sequence([
                    .fadeAlpha(to: 0.5, duration: 0.3),
                    .fadeAlpha(to: 1.0, duration: 0.3),
                ])), withKey: "pulse")
                readyLabel.run(.repeatForever(.sequence([
                    .fadeAlpha(to: 0.4, duration: 0.3),
                    .fadeAlpha(to: 1.0, duration: 0.3),
                ])), withKey: "pulse")
            } else {
                starBarFill.removeAction(forKey: "pulse")
                starBarFill.alpha = 1
                readyLabel.removeAction(forKey: "pulse")
                readyLabel.alpha = 1
            }
        }
        if session.starPowerActive != lastStarActive {
            lastStarActive = session.starPowerActive
            starOverlay.removeAllActions()
            if session.starPowerActive {
                starOverlay.run(.repeatForever(.sequence([
                    .fadeAlpha(to: 0.10, duration: 0.5),
                    .fadeAlpha(to: 0.04, duration: 0.5),
                ])))
            } else {
                starOverlay.run(.fadeAlpha(to: 0, duration: 0.4))
            }
        }
        if let duration = songInfo?.duration, duration > 0 {
            progressFill.xScale = CGFloat(min(max(t / duration, 0), 1))
        }
    }

    private func showJudgment(_ judgment: HitJudgment, at key: KeyPosition) {
        let (text, color): (String, NSColor) = switch judgment {
        case .perfect: ("PERFECT", Theme.hitFlash)
        case .good: ("GOOD", Theme.keyStroke)
        case .miss: ("MISS", Theme.missRed)
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

    private var backdrop: BackdropNode?

    private func buildBackdrop() {
        let node = BackdropNode(size: size)
        node.zPosition = -10
        addChild(node)
        backdrop = node
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
