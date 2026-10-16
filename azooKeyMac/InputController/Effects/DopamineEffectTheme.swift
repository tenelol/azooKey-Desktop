import AppKit
import CoreText
import QuartzCore

/// コンボ数・ランク・キーワードで派手に盛り上げる演出。
/// IMKInputController はクライアントごとに生成されるため、コンボ状態はテーマ側で保持する。
@MainActor
final class DopamineEffectTheme: EffectTheme {
    let id = "dopamine"
    let title = "ドーパミン"

    private struct Rank {
        var letter: String
        var colors: [NSColor]
    }

    private struct KeywordEffect {
        var keywords: [String]
        var title: String
        var colors: [NSColor]
        var emoji: [String]
        var tint: NSColor?
        var rockets: Bool = false
    }

    private static let comboTimeout: TimeInterval = 3.0
    private static let keywordBufferLength = 32

    private static let keywordEffects: [KeywordEffect] = [
        .init(
            keywords: ["リリース", "release", "ship", "デプロイ", "deploy", "完成", "マージ", "merge", "公開"],
            title: "SHIPPED!",
            colors: [.effectHex(0xB45CFF), .effectHex(0x5CF2FF), .effectHex(0x5CFF8F)],
            emoji: ["🚀", "✨"],
            tint: nil,
            rockets: true
        ),
        .init(
            keywords: ["好き", "すき", "愛", "love", "かわいい", "可愛い"],
            title: "LOVE",
            colors: [.effectHex(0xFF4D6D), .effectHex(0xFF9ECF), .effectHex(0xFFD1E8)],
            emoji: ["💖", "💕", "😍"],
            tint: .effectHex(0xFF2D6F)
        ),
        .init(
            keywords: ["最強", "天才", "完璧", "最高", "critical"],
            title: "CRITICAL!!",
            colors: [.effectHex(0xFFE45C), .effectHex(0xFF9F1C), .effectHex(0xFF4D6D)],
            emoji: ["💎", "✨", "⭐️"],
            tint: .effectHex(0xFFB020)
        ),
        .init(
            keywords: ["ドーパミン", "ドパ", "やばい", "ヤバい", "すごい", "凄い"],
            title: "MEGA HIT",
            colors: [.effectHex(0x5CF2FF), .effectHex(0x8F7BFF), .effectHex(0xFF5CF2)],
            emoji: ["⚡️", "🔥", "💥"],
            tint: .effectHex(0x7B5CFF)
        ),
        .init(
            keywords: ["ありがとう", "感謝", "thanks", "thank you"],
            title: "THANKS!!",
            colors: [.effectHex(0x5CFF8F), .effectHex(0xFFE45C)],
            emoji: ["🙏", "🌸", "🎉"],
            tint: nil
        ),
        .init(
            keywords: ["バグ", "bug", "エラー", "error"],
            title: "BUG?!",
            colors: [.effectHex(0xA3FF5C), .effectHex(0x2EC27E)],
            emoji: ["🐛", "💥", "🪲"],
            tint: .effectHex(0x2EC27E)
        )
    ]

    private var comboLayer: CALayer?
    private var comboTimerLayer: CALayer?
    private var combo = 0
    private var resetWorkItem: DispatchWorkItem?
    private var recentCommittedText = ""
    /// 30コンボ以上で出し続ける虹色の縁と紙吹雪の雨
    private var feverLayers: [CALayer] = []
    private var imageCache: [String: CGImage] = [:]

    // MARK: - EffectTheme

    func keystroke(at caret: CGRect) {
        guard let (root, local) = self.prepareRoot(for: caret) else {
            return
        }
        self.combo += 1
        let rank = Self.rank(for: self.combo)

        self.emitSparks(at: local, colors: rank.colors, intensity: min(1 + CGFloat(self.combo) / 25, 3), in: root)
        self.emitSpeedLines(at: local, color: rank.colors[0], in: root)
        self.pulseRing(at: local, color: rank.colors[rank.colors.count - 1], in: root)
        // コンボが伸びるほど絵文字が飛び出しやすくなる
        if Double.random(in: 0..<1) < min(0.25 + Double(self.combo) / 100, 0.7) {
            self.popEmoji(Self.keystrokeEmoji(for: rank).randomElement() ?? "✨", at: local, in: root)
        }
        if self.combo >= 30 {
            self.startFever(in: root)
        }
        if self.combo % 10 == 0 {
            self.showMilestone(rank: rank, in: root)
        }
        self.showComboLabel(rank: rank, near: local, in: root)
        self.scheduleComboReset()
    }

    /// キーワードを含む確定文字列には専用の演出を出す
    func commit(_ text: String, at caret: CGRect) {
        guard let (root, local) = self.prepareRoot(for: caret) else {
            return
        }
        // 英字入力は1文字ずつ確定されるため、直近の確定文字列をまとめてキーワード判定する
        self.recentCommittedText = String((self.recentCommittedText + text).suffix(Self.keywordBufferLength))
        let haystack = self.recentCommittedText.lowercased()
        if let effect = Self.keywordEffects.first(where: { $0.keywords.contains(where: haystack.contains) }) {
            self.recentCommittedText = ""
            self.playKeywordEffect(effect, near: local, in: root)
        } else if text.count >= 2 {
            let praise = Self.praise(forLength: text.count)
            self.emitStarShower(at: local, in: root)
            if text.count >= 8 {
                for index in 0..<3 {
                    let point = CGPoint(x: local.x + CGFloat.random(in: -160...160), y: local.y + CGFloat.random(in: 40...160))
                    self.fireworks(at: point, colors: praise.colors, delay: Double(index) * 0.12, in: root)
                }
            }
            self.showFloatingText(praise.text, colors: praise.colors, fontSize: praise.fontSize, at: local, in: root)
        }
    }

    /// 確定した長さで褒め言葉と大きさを上げる
    private struct Praise {
        var text: String
        var fontSize: CGFloat
        var colors: [NSColor]
    }

    private static func praise(forLength length: Int) -> Praise {
        switch length {
        case 12...:
            Praise(text: "PERFECT!!!", fontSize: 46, colors: [.effectHex(0xFFE45C), .effectHex(0xFF4D6D), .effectHex(0xB45CFF), .effectHex(0x5CF2FF)])
        case 8...:
            Praise(text: "EXCELLENT!!", fontSize: 38, colors: [.effectHex(0xFF9F1C), .effectHex(0xFF4D6D), .effectHex(0xFFE45C)])
        case 5...:
            Praise(text: "GREAT!", fontSize: 30, colors: [.effectHex(0x5CFF8F), .effectHex(0xFFE45C)])
        default:
            Praise(text: "NICE!", fontSize: 24, colors: [.effectHex(0x5CF2FF), .effectHex(0xFFFFFF)])
        }
    }

    private static func keystrokeEmoji(for rank: Rank) -> [String] {
        switch rank.letter {
        case "C": ["✨", "💫"]
        case "B": ["⚡️", "✨", "💥"]
        case "A": ["🔥", "💥", "⚡️", "😎"]
        default: ["🔥", "🌈", "💎", "🚀", "👑", "🤯"]
        }
    }

    func makeCandidateDecoration() -> (any CandidateDecoration)? {
        DopamineCandidateDecoration()
    }

    /// コンボ演出はキャレット行の左端・中央を基準にする
    private func prepareRoot(for caret: CGRect) -> (CALayer, CGPoint)? {
        guard let (root, local) = EffectOverlayWindow.shared.prepareRoot(for: caret) else {
            return nil
        }
        return (root, CGPoint(x: local.minX, y: local.midY))
    }

    private var backingScale: CGFloat {
        EffectOverlayWindow.shared.backingScale
    }

    // MARK: - Combo

    private static func rank(for combo: Int) -> Rank {
        switch combo {
        case ..<10:
            Rank(letter: "C", colors: [.effectHex(0x5CF2FF), .effectHex(0x3B82F6)])
        case ..<20:
            Rank(letter: "B", colors: [.effectHex(0xFFE45C), .effectHex(0xFF9F1C)])
        case ..<30:
            Rank(letter: "A", colors: [.effectHex(0xFFB020), .effectHex(0xFF4D6D)])
        default:
            Rank(letter: "S", colors: [.effectHex(0xFF4D6D), .effectHex(0xFFE45C), .effectHex(0x5CFF8F), .effectHex(0x5CF2FF), .effectHex(0xB45CFF)])
        }
    }

    private func showComboLabel(rank: Rank, near point: CGPoint, in root: CALayer) {
        guard let image = self.renderTitle("\(self.combo) COMBO  \(rank.letter)", fontSize: 36, colors: rank.colors, glow: rank.colors[0]) else {
            return
        }
        let size = CGSize(width: CGFloat(image.width) / self.backingScale, height: CGFloat(image.height) / self.backingScale)
        let center = self.clamped(CGPoint(x: point.x + size.width / 2 + 24, y: point.y + 46), size: size, in: root.bounds)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let label = self.comboLayer ?? {
            let layer = CALayer()
            // コンボ表示は常に最前面に置く
            layer.zPosition = 10
            root.addSublayer(layer)
            self.comboLayer = layer
            return layer
        }()
        label.contents = image
        label.contentsScale = self.backingScale
        label.bounds = CGRect(origin: .zero, size: size)
        label.position = center
        label.opacity = 1
        label.removeAnimation(forKey: "fadeOut")

        // 残り猶予を示すゲージ
        let timer = self.comboTimerLayer ?? {
            let layer = CALayer()
            layer.anchorPoint = CGPoint(x: 0, y: 0.5)
            layer.cornerRadius = 2
            layer.shadowOffset = .zero
            layer.shadowRadius = 6
            layer.shadowOpacity = 1
            layer.zPosition = 10
            root.addSublayer(layer)
            self.comboTimerLayer = layer
            return layer
        }()
        let gaugeWidth = size.width * 0.7
        timer.bounds = CGRect(x: 0, y: 0, width: gaugeWidth, height: 4)
        timer.position = CGPoint(x: center.x - gaugeWidth / 2, y: center.y - size.height / 2 + 6)
        timer.backgroundColor = rank.colors[0].cgColor
        timer.shadowColor = rank.colors[0].cgColor
        timer.opacity = 1
        CATransaction.commit()

        let pop = CASpringAnimation(keyPath: "transform.scale")
        pop.fromValue = 1.45
        pop.toValue = 1.0
        pop.damping = 9
        pop.stiffness = 420
        pop.duration = pop.settlingDuration
        label.add(pop, forKey: "pop")

        let wiggle = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        let angle = CGFloat.random(in: 0.04...0.09) * (Bool.random() ? 1 : -1)
        wiggle.values = [0, angle, -angle / 2, 0]
        wiggle.duration = 0.22
        label.add(wiggle, forKey: "wiggle")

        let drain = CABasicAnimation(keyPath: "transform.scale.x")
        drain.fromValue = 1
        drain.toValue = 0
        drain.duration = Self.comboTimeout
        drain.fillMode = .forwards
        drain.isRemovedOnCompletion = false
        timer.add(drain, forKey: "drain")
    }

    private func scheduleComboReset() {
        self.resetWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.resetCombo()
            }
        }
        self.resetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.comboTimeout, execute: workItem)
    }

    private func resetCombo() {
        self.combo = 0
        self.stopFever()
        for layer in [self.comboLayer, self.comboTimerLayer].compactMap({ $0 }) {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = layer.opacity
            fade.toValue = 0
            fade.duration = 0.35
            layer.opacity = 0
            layer.add(fade, forKey: "fadeOut")
        }
    }

    private func showMilestone(rank: Rank, in root: CALayer) {
        let title = switch self.combo {
        case 100...: "GODLIKE x\(self.combo)"
        case 50...: "UNSTOPPABLE x\(self.combo)"
        case 30...: "ON FIRE x\(self.combo)"
        default: "COMBO x\(self.combo)"
        }
        let colors: [NSColor] = [.effectHex(0x5CFF8F), .effectHex(0xFFE45C), .effectHex(0xFF9F1C), .effectHex(0xFF4D6D)]
        // 入力中の文字を隠さないよう、節目の見出しは画面右上に出す
        let center = CGPoint(x: root.bounds.maxX - 280, y: root.bounds.maxY - 120)
        // 後から追加したレイヤーほど手前に描かれるため、見出しは最後に重ねる
        self.flashScreen(in: root)
        self.emitConfetti(at: center, colors: colors + rank.colors, in: root)
        // 画面のあちこちで花火を連発する
        let area = root.bounds.insetBy(dx: root.bounds.width * 0.12, dy: root.bounds.height * 0.15)
        for index in 0..<(self.combo >= 50 ? 8 : 5) {
            let point = CGPoint(x: CGFloat.random(in: area.minX...area.maxX), y: CGFloat.random(in: area.minY...area.maxY))
            self.fireworks(at: point, colors: (colors + rank.colors).shuffled(), delay: Double(index) * 0.14, in: root)
        }
        self.flashEdges(color: rank.colors[rank.colors.count / 2], in: root)
        self.showBanner(title, colors: colors, fontSize: 52, center: center, in: root)
    }

    // MARK: - Keyword effects

    private func playKeywordEffect(_ effect: KeywordEffect, near point: CGPoint, in root: CALayer) {
        if let tint = effect.tint {
            self.tintScreen(tint, in: root)
        }
        if effect.rockets {
            self.launchRockets(in: root)
        }
        self.emitEmoji(effect.emoji, at: point, in: root)
        self.shockwave(at: point, color: effect.colors[0], in: root)
        self.flashEdges(color: effect.colors[0], in: root)
        self.showBanner(effect.title, colors: effect.colors, fontSize: 58, center: CGPoint(x: point.x + 60, y: point.y + 110), in: root)
    }

    // MARK: - Building blocks

    /// 大きなタイトルを弾ませて表示し、拡大しながら消す
    private func showBanner(_ text: String, colors: [NSColor], fontSize: CGFloat, center: CGPoint, in root: CALayer) {
        guard let image = self.renderTitle(text, fontSize: fontSize, colors: colors, glow: colors[0]) else {
            return
        }
        let layer = CALayer()
        layer.contents = image
        layer.contentsScale = self.backingScale
        layer.bounds = CGRect(x: 0, y: 0, width: CGFloat(image.width) / self.backingScale, height: CGFloat(image.height) / self.backingScale)
        layer.position = self.clamped(center, size: layer.bounds.size, in: root.bounds)
        layer.opacity = 0
        root.addSublayer(layer)

        let keyTimes: [NSNumber] = [0, 0.1, 0.17, 0.24, 0.78, 1]
        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [2.8, 0.88, 1.08, 1.0, 1.0, 1.35]
        scale.keyTimes = keyTimes
        let rotation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        rotation.values = [-0.25, 0.04, -0.02, 0, 0, 0.05]
        rotation.keyTimes = keyTimes
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0, 1, 1, 1, 1, 0]
        opacity.keyTimes = keyTimes
        let group = CAAnimationGroup()
        group.animations = [scale, rotation, opacity]
        group.duration = 1.7
        layer.addEffectAnimation(group, removeAfter: true)
    }

    private func showFloatingText(_ text: String, colors: [NSColor], fontSize: CGFloat = 24, at point: CGPoint, in root: CALayer) {
        guard let image = self.renderTitle(text, fontSize: fontSize, colors: colors, glow: colors[0]) else {
            return
        }
        let layer = CALayer()
        layer.contents = image
        layer.contentsScale = self.backingScale
        layer.bounds = CGRect(x: 0, y: 0, width: CGFloat(image.width) / self.backingScale, height: CGFloat(image.height) / self.backingScale)
        layer.position = self.clamped(CGPoint(x: point.x + 20, y: point.y + 20), size: layer.bounds.size, in: root.bounds)
        layer.opacity = 0
        root.addSublayer(layer)

        let rise = CABasicAnimation(keyPath: "position.y")
        rise.byValue = 48
        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [0.4, 1.2, 1.0, 0.9]
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0, 1, 1, 0]
        let group = CAAnimationGroup()
        group.animations = [rise, scale, opacity]
        group.duration = 0.8
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.addEffectAnimation(group, removeAfter: true)
    }

    /// 打鍵した位置から放射状に伸びる集中線
    private func emitSpeedLines(at point: CGPoint, color: NSColor, in root: CALayer) {
        let lines = CAShapeLayer()
        lines.bounds = CGRect(x: -40, y: -40, width: 80, height: 80)
        lines.position = point
        let path = CGMutablePath()
        let offset = CGFloat.random(in: 0..<(.pi / 5))
        for index in 0..<10 {
            let angle = offset + CGFloat(index) * .pi / 5
            path.move(to: CGPoint(x: cos(angle) * 12, y: sin(angle) * 12))
            path.addLine(to: CGPoint(x: cos(angle) * CGFloat.random(in: 26...38), y: sin(angle) * CGFloat.random(in: 26...38)))
        }
        lines.path = path
        lines.strokeColor = NSColor.white.cgColor
        lines.lineWidth = 2
        lines.lineCap = .round
        lines.shadowColor = color.cgColor
        lines.shadowOffset = .zero
        lines.shadowRadius = 4
        lines.shadowOpacity = 1
        lines.opacity = 0
        root.addSublayer(lines)
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.5
        scale.toValue = 1.7
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 0.28
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        lines.addEffectAnimation(group, removeAfter: true)
    }

    private func pulseRing(at point: CGPoint, color: NSColor, in root: CALayer) {
        let ring = CAShapeLayer()
        ring.bounds = CGRect(x: 0, y: 0, width: 24, height: 24)
        ring.position = point
        ring.path = CGPath(ellipseIn: ring.bounds, transform: nil)
        ring.fillColor = nil
        ring.strokeColor = color.cgColor
        ring.lineWidth = 2.5
        ring.shadowColor = color.cgColor
        ring.shadowOffset = .zero
        ring.shadowRadius = 6
        ring.shadowOpacity = 1
        ring.opacity = 0
        root.addSublayer(ring)
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1
        scale.toValue = 3.5
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.9
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 0.4
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ring.addEffectAnimation(group, removeAfter: true)
    }

    /// 絵文字を1つ、回転させながら弧を描いて飛ばす
    private func popEmoji(_ emoji: String, at point: CGPoint, in root: CALayer) {
        guard let image = self.emojiImage(emoji) else {
            return
        }
        let size = CGFloat.random(in: 28...44)
        let layer = CALayer()
        layer.contents = image
        layer.contentsScale = self.backingScale
        layer.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        layer.position = point
        layer.opacity = 0
        root.addSublayer(layer)
        let end = CGPoint(x: point.x + CGFloat.random(in: -70...70), y: point.y + CGFloat.random(in: 70...140))
        let control = CGPoint(x: (point.x + end.x) / 2 + CGFloat.random(in: -40...40), y: end.y + 40)
        let path = CGMutablePath()
        path.move(to: point)
        path.addQuadCurve(to: end, control: control)
        let move = CAKeyframeAnimation(keyPath: "position")
        move.path = path
        move.timingFunction = CAMediaTimingFunction(name: .easeOut)
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.toValue = CGFloat.random(in: -1.2...1.2)
        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [0.3, 1.25, 1, 0.8]
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0]
        fade.keyTimes = [0, 0.1, 0.65, 1]
        let group = CAAnimationGroup()
        group.animations = [move, spin, scale, fade]
        group.duration = 0.9
        layer.addEffectAnimation(group, removeAfter: true)
    }

    /// 一点から全方向に弾けて重力で垂れる花火
    private func fireworks(at point: CGPoint, colors: [NSColor], delay: TimeInterval, in root: CALayer) {
        guard let spark = self.sparkImage(), let star = self.starImage() else {
            return
        }
        let cells = colors.prefix(3).map { color in
            let cell = self.makeCell(image: Bool.random() ? spark : star, color: color, birthRate: 380, velocity: 230, lifetime: 1.2, scale: 0.4, yAcceleration: -150, spin: 2)
            cell.velocityRange = 40
            return cell
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak root] in
            MainActor.assumeIsolated {
                guard let self, let root else {
                    return
                }
                self.burst(cells: Array(cells), at: point, renderMode: .additive, emitDuration: 0.05, in: root)
                self.pulseRing(at: point, color: colors.first ?? .white, in: root)
            }
        }
    }

    /// 確定した文字列から星を吹き上げる
    private func emitStarShower(at point: CGPoint, in root: CALayer) {
        guard let star = self.starImage() else {
            return
        }
        let cells = [NSColor.effectHex(0xFFE45C), .effectHex(0xFFFFFF), .effectHex(0xFF9ECF)].map { color in
            let cell = self.makeCell(image: star, color: color, birthRate: 90, velocity: 260, lifetime: 1.3, scale: 0.45, yAcceleration: -380, spin: 4)
            cell.emissionLongitude = .pi / 2
            cell.emissionRange = .pi / 3
            return cell
        }
        self.burst(cells: cells, at: point, renderMode: .additive, emitDuration: 0.15, in: root)
    }

    /// 画面全体が一瞬白く光る
    private func flashScreen(in root: CALayer) {
        let flash = CALayer()
        flash.frame = root.bounds
        flash.backgroundColor = NSColor.white.withAlphaComponent(0.3).cgColor
        flash.opacity = 0
        root.insertSublayer(flash, at: 0)
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 0]
        fade.keyTimes = [0, 0.15, 1]
        fade.duration = 0.35
        flash.addEffectAnimation(fade, removeAfter: true)
    }

    /// フィーバー中は画面の縁に虹色の光を回し、上から紙吹雪を降らせ続ける
    private func startFever(in root: CALayer) {
        guard self.feverLayers.isEmpty, let confetti = self.confettiImage(), let star = self.starImage() else {
            return
        }
        let bounds = root.bounds
        let border = CALayer()
        border.frame = bounds
        let gradient = CAGradientLayer()
        gradient.type = .conic
        gradient.colors = [0xFF4D6D, 0xFFE45C, 0x5CFF8F, 0x5CF2FF, 0xB45CFF, 0xFF4D6D].map { NSColor.effectHex($0).cgColor }
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 0.5, y: 0)
        let side = hypot(bounds.width, bounds.height)
        gradient.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        gradient.position = CGPoint(x: bounds.midX, y: bounds.midY)
        let mask = CAShapeLayer()
        mask.frame = bounds
        mask.path = CGPath(rect: bounds.insetBy(dx: 6, dy: 6), transform: nil)
        mask.fillColor = nil
        mask.strokeColor = NSColor.white.cgColor
        mask.lineWidth = 12
        mask.shadowColor = NSColor.white.cgColor
        mask.shadowOffset = .zero
        mask.shadowRadius = 10
        mask.shadowOpacity = 1
        border.mask = mask
        border.addSublayer(gradient)
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = -2 * CGFloat.pi
        spin.duration = 2
        spin.repeatCount = .infinity
        gradient.add(spin, forKey: "spin")
        let breathe = CABasicAnimation(keyPath: "opacity")
        breathe.fromValue = 0.55
        breathe.toValue = 1
        breathe.duration = 0.45
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        border.add(breathe, forKey: "breathe")
        root.insertSublayer(border, at: 0)

        let rain = CAEmitterLayer()
        rain.frame = bounds
        rain.emitterShape = .line
        rain.emitterPosition = CGPoint(x: bounds.midX, y: bounds.maxY + 10)
        rain.emitterSize = CGSize(width: bounds.width, height: 1)
        rain.beginTime = CACurrentMediaTime()
        rain.emitterCells = [0xFF4D6D, 0xFFE45C, 0x5CFF8F, 0x5CF2FF, 0xB45CFF].map { hex in
            let cell = self.makeCell(image: Bool.random() ? confetti : star, color: .effectHex(UInt32(hex)), birthRate: 14, velocity: 140, lifetime: 7, scale: 0.55, yAcceleration: -60, spin: 4)
            cell.emissionLongitude = -.pi / 2
            cell.emissionRange = .pi / 6
            cell.alphaSpeed = -0.1
            cell.scaleSpeed = 0
            return cell
        }
        root.insertSublayer(rain, above: border)
        self.feverLayers = [border, rain]
        self.showBanner("FEVER!!", colors: [.effectHex(0xFF4D6D), .effectHex(0xFFE45C), .effectHex(0x5CF2FF)], fontSize: 72, center: CGPoint(x: bounds.midX, y: bounds.maxY - 160), in: root)
    }

    private func stopFever() {
        for layer in self.feverLayers {
            (layer as? CAEmitterLayer)?.birthRate = 0
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = layer.presentation()?.opacity ?? layer.opacity
            fade.toValue = 0
            fade.duration = 0.6
            layer.opacity = 0
            layer.addEffectAnimation(fade, removeAfter: true)
        }
        self.feverLayers = []
    }

    private func emitSparks(at point: CGPoint, colors: [NSColor], intensity: CGFloat, in root: CALayer) {
        guard let spark = self.sparkImage(), let star = self.starImage() else {
            return
        }
        let cells = colors.map { color in
            self.makeCell(
                image: Bool.random() ? spark : star,
                color: color,
                birthRate: Float(90 * intensity) / Float(colors.count) * 3,
                velocity: 140 * intensity,
                lifetime: 0.7,
                scale: 0.35,
                yAcceleration: -260
            )
        }
        self.burst(cells: cells, at: point, renderMode: .additive, emitDuration: 0.05, in: root)
    }

    private func emitConfetti(at point: CGPoint, colors: [NSColor], in root: CALayer) {
        guard let confetti = self.confettiImage(), let star = self.starImage() else {
            return
        }
        let cells = colors.flatMap { color in
            [
                self.makeCell(image: confetti, color: color, birthRate: 120, velocity: 520, lifetime: 2.2, scale: 0.6, yAcceleration: -520, spin: 6),
                self.makeCell(image: star, color: color, birthRate: 40, velocity: 380, lifetime: 1.6, scale: 0.5, yAcceleration: -300, spin: 3)
            ]
        }
        self.burst(cells: cells, at: point, renderMode: .unordered, emitDuration: 0.12, in: root)
    }

    private func emitEmoji(_ emoji: [String], at point: CGPoint, in root: CALayer) {
        let cells = emoji.compactMap { self.emojiImage($0) }.map { image in
            let cell = self.makeCell(image: image, color: nil, birthRate: 40, velocity: 420, lifetime: 2.4, scale: 0.55, yAcceleration: -380, spin: 1.5)
            // 上方向に吹き上げる
            cell.emissionLongitude = .pi / 2
            cell.emissionRange = .pi / 2.5
            return cell
        }
        self.burst(cells: cells, at: point, renderMode: .unordered, emitDuration: 0.35, in: root)
    }

    private func burst(cells: [CAEmitterCell], at point: CGPoint, renderMode: CAEmitterLayerRenderMode, emitDuration: TimeInterval, in root: CALayer) {
        let emitter = CAEmitterLayer()
        emitter.frame = root.bounds
        emitter.emitterPosition = point
        emitter.emitterShape = .point
        emitter.renderMode = renderMode
        emitter.emitterCells = cells
        // beginTime を揃えないと粒子が寿命の途中から描かれる
        emitter.beginTime = CACurrentMediaTime()
        root.addSublayer(emitter)
        let maxLifetime = cells.map { TimeInterval($0.lifetime + $0.lifetimeRange) }.max() ?? 1
        DispatchQueue.main.asyncAfter(deadline: .now() + emitDuration) {
            emitter.birthRate = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + emitDuration + maxLifetime) {
            emitter.removeFromSuperlayer()
        }
    }

    // swiftlint:disable:next function_parameter_count
    private func makeCell(
        image: CGImage,
        color: NSColor?,
        birthRate: Float,
        velocity: CGFloat,
        lifetime: Float,
        scale: CGFloat,
        yAcceleration: CGFloat,
        spin: CGFloat = 0
    ) -> CAEmitterCell {
        let cell = CAEmitterCell()
        cell.contents = image
        if let color {
            cell.color = color.cgColor
        }
        cell.birthRate = birthRate
        cell.lifetime = lifetime
        cell.lifetimeRange = lifetime * 0.3
        cell.velocity = velocity
        cell.velocityRange = velocity * 0.6
        cell.emissionRange = .pi * 2
        cell.yAcceleration = yAcceleration
        cell.scale = scale
        cell.scaleRange = scale * 0.5
        cell.scaleSpeed = -scale / CGFloat(lifetime) * 0.5
        cell.alphaSpeed = -1 / lifetime
        cell.spin = spin
        cell.spinRange = spin * 2
        return cell
    }

    private func shockwave(at point: CGPoint, color: NSColor, in root: CALayer) {
        let radius: CGFloat = 60
        let ring = CAShapeLayer()
        ring.bounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
        ring.position = point
        ring.path = CGPath(ellipseIn: ring.bounds, transform: nil)
        ring.fillColor = nil
        ring.strokeColor = color.cgColor
        ring.lineWidth = 5
        ring.shadowColor = color.cgColor
        ring.shadowOffset = .zero
        ring.shadowRadius = 12
        ring.shadowOpacity = 1
        ring.opacity = 0
        root.addSublayer(ring)

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.1
        scale.toValue = 6
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 1
        opacity.toValue = 0
        let width = CABasicAnimation(keyPath: "lineWidth")
        width.fromValue = 10
        width.toValue = 0.5
        let group = CAAnimationGroup()
        group.animations = [scale, opacity, width]
        group.duration = 0.75
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ring.addEffectAnimation(group, removeAfter: true)
    }

    private func flashEdges(color: NSColor, in root: CALayer) {
        let border = CALayer()
        border.frame = root.bounds
        border.borderColor = color.cgColor
        border.borderWidth = 6
        border.shadowColor = color.cgColor
        border.shadowOffset = .zero
        border.shadowRadius = 24
        border.shadowOpacity = 1
        border.opacity = 0
        root.addSublayer(border)

        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0, 0.7, 0.35, 0]
        opacity.keyTimes = [0, 0.1, 0.4, 1]
        opacity.duration = 0.8
        border.addEffectAnimation(opacity, removeAfter: true)
    }

    private func tintScreen(_ color: NSColor, in root: CALayer) {
        let tint = CALayer()
        tint.frame = root.bounds
        tint.backgroundColor = color.withAlphaComponent(0.22).cgColor
        tint.opacity = 0
        root.insertSublayer(tint, at: 0)

        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0, 1, 1, 0]
        opacity.keyTimes = [0, 0.15, 0.6, 1]
        opacity.duration = 1.4
        tint.addEffectAnimation(opacity, removeAfter: true)
    }

    private func launchRockets(in root: CALayer) {
        guard let rocket = self.emojiImage("🚀") else {
            return
        }
        let bounds = root.bounds
        for index in 0..<10 {
            let layer = CALayer()
            let size = CGFloat.random(in: 34...60)
            layer.contents = rocket
            layer.contentsScale = self.backingScale
            layer.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            layer.shadowColor = NSColor.effectHex(0xFF9F1C).cgColor
            layer.shadowOffset = .zero
            layer.shadowRadius = 10
            layer.shadowOpacity = 0.9
            layer.opacity = 0
            root.addSublayer(layer)

            // 🚀 は右上を向いているので左下から右上へ斜めに飛ばす
            let start = CGPoint(x: CGFloat.random(in: -bounds.height * 0.6...bounds.width * 0.7), y: -80)
            let travel = bounds.height + 240
            let end = CGPoint(x: start.x + travel, y: start.y + travel)
            let move = CAKeyframeAnimation(keyPath: "position")
            move.values = [start, end].map { NSValue(point: $0) }
            move.timingFunction = CAMediaTimingFunction(name: .easeIn)
            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = [1, 1]
            let group = CAAnimationGroup()
            group.animations = [move, opacity]
            group.duration = .random(in: 0.9...1.5)
            group.beginTime = CACurrentMediaTime() + Double(index) * 0.07
            group.fillMode = .backwards
            layer.addEffectAnimation(group, removeAfter: true)
        }
    }

    private func clamped(_ center: CGPoint, size: CGSize, in bounds: CGRect) -> CGPoint {
        let margin: CGFloat = 12
        let minX = bounds.minX + size.width / 2 + margin
        let maxX = bounds.maxX - size.width / 2 - margin
        let minY = bounds.minY + size.height / 2 + margin
        let maxY = bounds.maxY - size.height / 2 - margin
        return CGPoint(
            x: minX < maxX ? min(max(center.x, minX), maxX) : bounds.midX,
            y: minY < maxY ? min(max(center.y, minY), maxY) : bounds.midY
        )
    }

    // MARK: - Image rendering

    /// グラデーション塗り・黒縁・グロー付きの見出し文字を描く（ASCII 前提）
    private func renderTitle(_ text: String, fontSize: CGFloat, colors: [NSColor], glow: NSColor) -> CGImage? {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .black)
        let path = Self.textPath(text, font: font)
        let textBounds = path.boundingBoxOfPath
        let padding = fontSize * 0.45
        let scale = self.backingScale
        let size = CGSize(width: textBounds.width + padding * 2, height: textBounds.height + padding * 2)
        guard let context = Self.makeContext(size: size, scale: scale) else {
            return nil
        }
        context.translateBy(x: padding - textBounds.minX, y: padding - textBounds.minY)

        // グローと黒縁
        context.saveGState()
        context.setShadow(offset: .zero, blur: fontSize * 0.4, color: glow.cgColor)
        context.addPath(path)
        context.setLineWidth(fontSize * 0.18)
        context.setLineJoin(.round)
        context.replacePathWithStrokedPath()
        context.addPath(path)
        context.setFillColor(NSColor(white: 0.04, alpha: 1).cgColor)
        context.fillPath()
        context.restoreGState()

        // 本体のグラデーション
        context.saveGState()
        context.addPath(path)
        context.clip()
        let gradientColors = (colors.count == 1 ? colors + colors : colors).map(\.cgColor) as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: gradientColors, locations: nil) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: textBounds.minX, y: textBounds.maxY),
                end: CGPoint(x: textBounds.maxX, y: textBounds.minY),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
        // 上半分のハイライト
        context.setFillColor(NSColor(white: 1, alpha: 0.28).cgColor)
        context.fill(CGRect(x: textBounds.minX, y: textBounds.midY + textBounds.height * 0.08, width: textBounds.width, height: textBounds.height))
        context.restoreGState()
        return context.makeImage()
    }

    private func emojiImage(_ emoji: String) -> CGImage? {
        self.cachedImage("emoji:\(emoji)") {
            let font = NSFont.systemFont(ofSize: 64)
            let string = NSAttributedString(string: emoji, attributes: [.font: font])
            let size = string.size()
            guard let context = Self.makeContext(size: size, scale: 2) else {
                return nil
            }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            string.draw(at: .zero)
            NSGraphicsContext.restoreGraphicsState()
            return context.makeImage()
        }
    }

    private func sparkImage() -> CGImage? {
        self.cachedImage("spark") {
            let size = CGSize(width: 24, height: 24)
            guard let context = Self.makeContext(size: size, scale: 2),
                  let gradient = CGGradient(
                    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                    colors: [NSColor.white.cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray,
                    locations: [0, 1]
                  ) else {
                return nil
            }
            let center = CGPoint(x: 12, y: 12)
            context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: 12, options: [])
            return context.makeImage()
        }
    }

    private func starImage() -> CGImage? {
        self.cachedImage("star") {
            let size = CGSize(width: 32, height: 32)
            guard let context = Self.makeContext(size: size, scale: 2) else {
                return nil
            }
            // 4 方向に尖ったきらめき
            let path = CGMutablePath()
            let center = CGPoint(x: 16, y: 16)
            for index in 0..<8 {
                let angle = CGFloat(index) * .pi / 4
                let radius: CGFloat = index.isMultiple(of: 2) ? 16 : 4
                let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            path.closeSubpath()
            context.addPath(path)
            context.setFillColor(NSColor.white.cgColor)
            context.fillPath()
            return context.makeImage()
        }
    }

    private func confettiImage() -> CGImage? {
        self.cachedImage("confetti") {
            let size = CGSize(width: 14, height: 7)
            guard let context = Self.makeContext(size: size, scale: 2) else {
                return nil
            }
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(origin: .zero, size: size))
            return context.makeImage()
        }
    }

    private func cachedImage(_ key: String, render: () -> CGImage?) -> CGImage? {
        if let image = self.imageCache[key] {
            return image
        }
        let image = render()
        self.imageCache[key] = image
        return image
    }

    private static func makeContext(size: CGSize, scale: CGFloat) -> CGContext? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: max(1, Int(ceil(size.width * scale))),
                height: max(1, Int(ceil(size.height * scale))),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }
        context.scaleBy(x: scale, y: scale)
        return context
    }

    private static func textPath(_ text: String, font: NSFont) -> CGPath {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        let path = CGMutablePath()
        // italic 指定だと Black のウェイトが落ちるため、グリフを傾けて斜体にする
        let shear = CGAffineTransform(a: 1, b: 0, c: 0.22, d: 1, tx: 0, ty: 0)
        let runs = (CTLineGetGlyphRuns(line) as? [CTRun]) ?? []
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            for (glyph, position) in zip(glyphs, positions) {
                if let glyphPath = CTFontCreatePathForGlyph(font as CTFont, glyph, nil) {
                    path.addPath(glyphPath, transform: shear.concatenating(CGAffineTransform(translationX: position.x, y: position.y)))
                }
            }
        }
        return path
    }
}
