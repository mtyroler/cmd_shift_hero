import GameCore
import SpriteKit

/// A falling note: glowing disc carrying the letter of its target key.
final class NoteNode: SKNode {
    let noteIndex: Int

    init(noteIndex: Int, key: KeyPosition, radius: CGFloat) {
        self.noteIndex = noteIndex
        super.init()

        let color = Theme.rowColor(key.row)

        let halo = SKShapeNode(circleOfRadius: radius * 1.25)
        halo.fillColor = color.withAlphaComponent(0.18)
        halo.strokeColor = .clear
        addChild(halo)

        let disc = SKShapeNode(circleOfRadius: radius)
        disc.fillColor = color.withAlphaComponent(0.92)
        disc.strokeColor = .white.withAlphaComponent(0.85)
        disc.lineWidth = 1.5
        disc.glowWidth = 5
        addChild(disc)

        let label = SKLabelNode(text: String(key.letter))
        label.fontName = "Menlo-Bold"
        label.fontSize = radius * 1.1
        label.fontColor = .black
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        addChild(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func explodeHit() {
        removeAllActions()
        run(.sequence([
            .group([.scale(to: 1.6, duration: 0.12), .fadeOut(withDuration: 0.12)]),
            .removeFromParent(),
        ]))
    }

    func fadeMiss() {
        removeAllActions()
        run(.sequence([
            .group([
                .colorize(with: .red, colorBlendFactor: 0.8, duration: 0.2),
                .fadeAlpha(to: 0, duration: 0.35),
                .moveBy(x: 0, y: -30, duration: 0.35),
            ]),
            .removeFromParent(),
        ]))
    }
}
