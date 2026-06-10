import SpriteKit

/// Animated synthwave backdrop rendered by a Metal fragment shader:
/// gradient sky with twinkling stars, a striped sun on the horizon, and a
/// perspective grid that scrolls toward the player. Gameplay drives it
/// through three uniforms — beat pulses on hits, combo speeds up the grid,
/// and star power crossfades the whole palette to gold.
final class BackdropNode: SKSpriteNode {
    private let beatUniform = SKUniform(name: "u_beat", float: 0)
    private let starUniform = SKUniform(name: "u_star", float: 0)
    private let comboUniform = SKUniform(name: "u_combo", float: 0)
    private let energyUniform = SKUniform(name: "u_energy", float: 0)
    private let aspectUniform = SKUniform(name: "u_aspect", float: 1)

    private var beat: Float = 0
    private var star: Float = 0
    private var energyLevel: Float = 0
    private var lastUpdate: TimeInterval?

    init(size: CGSize) {
        // Sprite shaders need a texture for v_tex_coord; a white fill does.
        super.init(texture: Self.whiteTexture, color: .white, size: size)
        anchorPoint = .zero
        let shader = SKShader(source: Self.source)
        shader.uniforms = [beatUniform, starUniform, comboUniform, energyUniform, aspectUniform]
        self.shader = shader
        aspectUniform.floatValue = Float(size.width / max(size.height, 1))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Kick the grid/sun brightness; decays over ~0.3 s.
    func pulse(_ strength: Float = 1) {
        beat = max(beat, strength)
    }

    /// Per-frame uniform feed. `time` is the scene's update timestamp;
    /// `energy` is the audible song's low-band level (0…1).
    func update(time: TimeInterval, combo: Int, starActive: Bool, energy: Float) {
        let dt = lastUpdate.map { Float(max(0, time - $0)) } ?? 0
        lastUpdate = time
        beat = max(0, beat - dt * 3.0)
        star += ((starActive ? 1 : 0) - star) * min(1, dt * 4)
        // VU-style: snap up with the kick, fall back slower.
        let rate: Float = energy > energyLevel ? 18 : 6
        energyLevel += (energy - energyLevel) * min(1, dt * rate)
        beatUniform.floatValue = beat
        starUniform.floatValue = star
        energyUniform.floatValue = energyLevel
        comboUniform.floatValue = min(1, Float(combo) / 30)
    }

    private static let whiteTexture: SKTexture = {
        let image = NSImage(size: NSSize(width: 2, height: 2), flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            return true
        }
        return SKTexture(image: image)
    }()

    private static let source = """
    float hash(vec2 p) {
        return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
    }

    void main() {
        vec2 uv = v_tex_coord;
        float horizon = 0.78;

        // Palettes crossfade toward gold while star power runs.
        vec3 skyTop    = mix(vec3(0.020, 0.012, 0.060), vec3(0.09, 0.05, 0.02), u_star);
        vec3 skyBottom = mix(vec3(0.100, 0.030, 0.180), vec3(0.24, 0.12, 0.03), u_star);
        vec3 gridCol   = mix(vec3(0.550, 0.150, 0.750), vec3(1.00, 0.70, 0.15), u_star);
        vec3 sunTop    = mix(vec3(1.000, 0.300, 0.700), vec3(1.00, 0.85, 0.30), u_star);
        vec3 sunBottom = mix(vec3(1.000, 0.550, 0.150), vec3(1.00, 0.60, 0.10), u_star);

        vec3 col;
        if (uv.y > horizon) {
            // Sky: vertical gradient plus hash-cell twinkling stars.
            float h = (uv.y - horizon) / (1.0 - horizon);
            col = mix(skyBottom, skyTop, h);
            vec2 cell = floor(uv * vec2(90.0 * u_aspect, 90.0));
            float star = step(0.992, hash(cell));
            float tw = 0.5 + 0.5 * sin(u_time * (2.0 + 4.0 * hash(cell + 7.0)) + hash(cell) * 6.2832);
            col += vec3(0.9, 0.9, 1.0) * star * tw * h;
        } else {
            // Floor: perspective grid scrolling toward the keyboard.
            float d = (horizon - uv.y) / horizon;
            float z = 1.0 / (d + 0.02);
            float speed = 0.55 + 0.45 * u_combo;
            float rows = abs(fract(z * 1.4 - u_time * speed) - 0.5);
            float rowLine = 1.0 - smoothstep(0.02, 0.16, rows);
            float xw = (uv.x - 0.5) * u_aspect * z;
            float cols = abs(fract(xw * 0.8) - 0.5);
            float colLine = 1.0 - smoothstep(0.02, 0.16, cols);
            float fade = smoothstep(0.0, 0.35, d);
            float glow = (rowLine + colLine) * fade * (0.35 + 0.45 * u_beat + 0.25 * u_combo + 0.35 * u_energy);
            col = mix(skyBottom * 0.4, skyTop, d * 0.8);
            col += gridCol * glow;
        }

        // Striped sun sitting on the horizon (occluded by the floor).
        vec2 sp = vec2((uv.x - 0.5) * u_aspect, uv.y - horizon - 0.02);
        float dist = length(sp);
        float r = 0.13 * (1.0 + 0.05 * u_beat + 0.08 * u_energy);
        if (uv.y > horizon) {
            float body = 1.0 - smoothstep(r - 0.006, r, dist);
            float stripes = smoothstep(-0.2, 0.6, sin((uv.y - horizon) * 160.0) + (uv.y - horizon) * 14.0);
            vec3 sunCol = mix(sunBottom, sunTop, clamp((sp.y + r) / (2.0 * r), 0.0, 1.0));
            col = mix(col, sunCol, body * stripes);
        }
        col += sunTop * exp(-dist * 7.0) * (0.12 + 0.10 * u_beat + 0.20 * u_energy);

        gl_FragColor = vec4(col, 1.0);
    }
    """
}
