import GameCore
import SpriteKit

/// The on-screen keyboard: three staggered letter rows. Keys light up while
/// physically held and flash on note hits. Also exposes the x-position of
/// every key so the note highway can align falling notes to their lanes.
public final class KeyboardNode: SKNode {
    public let keySize: CGFloat
    private let keyGap: CGFloat
    private var keys: [KeyPosition: KeyCapNode] = [:]

    public init(width: CGFloat) {
        // Top row (10 keys + bottom-row stagger of 0.75) sets the width budget.
        let units = 10.0 + 0.75
        keySize = width / (units + 0.1 * (units - 1))
        keyGap = keySize * 0.1
        super.init()

        for position in KeyMap.allPositions {
            let cap = KeyCapNode(position: position, size: keySize)
            cap.position = layoutPoint(for: position)
            addChild(cap)
            keys[position] = cap
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Height of the full 3-row block.
    public var blockHeight: CGFloat { 3 * keySize + 2 * keyGap }

    private func layoutPoint(for position: KeyPosition) -> CGPoint {
        let pitch = keySize + keyGap
        let x = (CGFloat(position.row.stagger) + CGFloat(position.column)) * pitch + keySize / 2
        let y = CGFloat(2 - position.row.rawValue) * pitch + keySize / 2
        return CGPoint(x: x, y: y)
    }

    /// Keyboard-local center of a key, for lane alignment and hit targets.
    public func localCenter(for position: KeyPosition) -> CGPoint {
        layoutPoint(for: position)
    }

    public func setPressed(_ pressed: Bool, at position: KeyPosition) {
        keys[position]?.setPressed(pressed)
    }

    public func flashHit(at position: KeyPosition, color: NSColor) {
        keys[position]?.flashHit(color: color)
    }
}

/// A single neon key cap.
final class KeyCapNode: SKNode {
    private let body: SKShapeNode
    private let label: SKLabelNode
    private let baseColor: NSColor

    init(position: KeyPosition, size: CGFloat) {
        baseColor = Theme.rowColor(position.row)
        body = SKShapeNode(
            rect: CGRect(x: -size / 2, y: -size / 2, width: size, height: size),
            cornerRadius: size * 0.18
        )
        body.fillColor = Theme.keyFill
        body.strokeColor = Theme.keyStroke.withAlphaComponent(0.55)
        body.lineWidth = 1.5

        label = SKLabelNode(text: String(position.letter))
        label.fontName = "Menlo-Bold"
        label.fontSize = size * 0.42
        label.fontColor = Theme.keyText
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center

        super.init()
        addChild(body)
        addChild(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setPressed(_ pressed: Bool) {
        if pressed {
            body.fillColor = baseColor.withAlphaComponent(0.85)
            body.strokeColor = baseColor
            body.glowWidth = 6
            label.fontColor = .black
            setScale(0.93)
        } else {
            body.fillColor = Theme.keyFill
            body.strokeColor = Theme.keyStroke.withAlphaComponent(0.55)
            body.glowWidth = 0
            label.fontColor = Theme.keyText
            setScale(1.0)
        }
    }

    func flashHit(color: NSColor) {
        let flash = SKShapeNode(circleOfRadius: body.frame.width * 0.6)
        flash.fillColor = color
        flash.strokeColor = .clear
        flash.alpha = 0.8
        flash.zPosition = 5
        addChild(flash)
        flash.run(.sequence([
            .group([.scale(to: 1.8, duration: 0.25), .fadeOut(withDuration: 0.25)]),
            .removeFromParent(),
        ]))
    }
}
