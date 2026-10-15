import AppKit
import Core
import CoreText
import QuartzCore

/// 打鍵・確定に合わせて画面全体へコンボ演出を重ねるオーバーレイ。
/// IMKInputController はクライアントごとに生成されるため、演出状態は共有インスタンスで保持する。
@MainActor
final class DopamineEffectOverlay {
    static let shared = DopamineEffectOverlay()

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
            colors: [.hex(0xB45CFF), .hex(0x5CF2FF), .hex(0x5CFF8F)],
            emoji: ["🚀", "✨"],
            tint: nil,
            rockets: true
        ),
        .init(
            keywords: ["好き", "すき", "愛", "love", "かわいい", "可愛い"],
            title: "LOVE",
            colors: [.hex(0xFF4D6D), .hex(0xFF9ECF), .hex(0xFFD1E8)],
            emoji: ["💖", "💕", "😍"],
            tint: .hex(0xFF2D6F)
        ),
        .init(
            keywords: ["最強", "天才", "完璧", "最高", "critical"],
            title: "CRITICAL!!",
            colors: [.hex(0xFFE45C), .hex(0xFF9F1C), .hex(0xFF4D6D)],
            emoji: ["💎", "✨", "⭐️"],
            tint: .hex(0xFFB020)
        ),
        .init(
            keywords: ["ドーパミン", "ドパ", "やばい", "ヤバい", "すごい", "凄い"],
            title: "MEGA HIT",
            colors: [.hex(0x5CF2FF), .hex(0x8F7BFF), .hex(0xFF5CF2)],
            emoji: ["⚡️", "🔥", "💥"],
            tint: .hex(0x7B5CFF)
        ),
        .init(
            keywords: ["ありがとう", "感謝", "thanks", "thank you"],
            title: "THANKS!!",
            colors: [.hex(0x5CFF8F), .hex(0xFFE45C)],
            emoji: ["🙏", "🌸", "🎉"],
            tint: nil
        ),
        .init(
            keywords: ["バグ", "bug", "エラー", "error"],
            title: "BUG?!",
            colors: [.hex(0xA3FF5C), .hex(0x2EC27E)],
            emoji: ["🐛", "💥", "🪲"],
            tint: .hex(0x2EC27E)
        )
    ]

    private var window: NSPanel?
    private var rootLayer: CALayer?
    private var comboLayer: CALayer?
    private var comboTimerLayer: CALayer?
    private var combo = 0
    private var resetWorkItem: DispatchWorkItem?
    private var recentCommittedText = ""
    private var imageCache: [String: CGImage] = [:]

    private init() {}

    private var isEnabled: Bool {
        Config.DopamineEffects().value
    }

    // MARK: - Public entry points

    /// 文字入力の打鍵ごとに呼ぶ。`point` はスクリーン座標（左下原点）のキャレット位置。
    func registerKeystroke(at point: CGPoint) {
        guard self.isEnabled, let (root, local) = self.prepareRoot(for: point) else {
            return
        }
        self.combo += 1
        let rank = Self.rank(for: self.combo)

        self.showComboLabel(rank: rank, near: local, in: root)
        self.emitSparks(at: local, colors: rank.colors, intensity: min(1 + CGFloat(self.combo) / 25, 3), in: root)
        if self.combo % 10 == 0 {
            self.showMilestone(rank: rank, near: local, in: root)
        }
        self.scheduleComboReset()
    }

    /// 確定文字列ごとに呼ぶ。キーワードを含む場合は専用の演出を出す。
    func registerCommit(_ text: String, at point: CGPoint) {
        guard self.isEnabled, let (root, local) = self.prepareRoot(for: point) else {
            return
        }
        // 英字入力は1文字ずつ確定されるため、直近の確定文字列をまとめてキーワード判定する
        self.recentCommittedText = String((self.recentCommittedText + text).suffix(Self.keywordBufferLength))
        let haystack = self.recentCommittedText.lowercased()
        if let effect = Self.keywordEffects.first(where: { $0.keywords.contains(where: haystack.contains) }) {
            self.recentCommittedText = ""
            self.playKeywordEffect(effect, near: local, in: root)
        } else if text.count >= 2 {
            self.showFloatingText("NICE!", colors: [.hex(0x5CF2FF), .hex(0xFFFFFF)], at: local, in: root)
        }
    }

    // MARK: - Window

    private func prepareRoot(for point: CGPoint) -> (CALayer, CGPoint)? {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) ?? NSScreen.main else {
            return nil
        }
        let window = self.window ?? self.makeWindow()
        if window.frame != screen.frame {
            window.setFrame(screen.frame, display: false)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.rootLayer?.frame = CGRect(origin: .zero, size: screen.frame.size)
            CATransaction.commit()
        }
        window.orderFrontRegardless()
        guard let root = self.rootLayer else {
            return nil
        }
        let local = CGPoint(x: point.x - screen.frame.minX, y: point.y - screen.frame.minY)
        return (root, local)
    }

    private func makeWindow() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        // 候補ウィンドウ（popUpMenu）やメニューバーより上に描く
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let view = NSView()
        view.wantsLayer = true
        let root = CALayer()
        root.masksToBounds = false
        view.layer = root
        panel.contentView = view

        self.window = panel
        self.rootLayer = root
        return panel
    }

    private var backingScale: CGFloat {
        self.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    // MARK: - Combo

    private static func rank(for combo: Int) -> Rank {
        switch combo {
        case ..<10:
            Rank(letter: "C", colors: [.hex(0x5CF2FF), .hex(0x3B82F6)])
        case ..<20:
            Rank(letter: "B", colors: [.hex(0xFFE45C), .hex(0xFF9F1C)])
        case ..<30:
            Rank(letter: "A", colors: [.hex(0xFFB020), .hex(0xFF4D6D)])
        default:
            Rank(letter: "S", colors: [.hex(0xFF4D6D), .hex(0xFFE45C), .hex(0x5CFF8F), .hex(0x5CF2FF), .hex(0xB45CFF)])
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
        for layer in [self.comboLayer, self.comboTimerLayer].compactMap({ $0 }) {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = layer.opacity
            fade.toValue = 0
            fade.duration = 0.35
            layer.opacity = 0
            layer.add(fade, forKey: "fadeOut")
        }
    }

    private func showMilestone(rank: Rank, near point: CGPoint, in root: CALayer) {
        let title = switch self.combo {
        case 100...: "GODLIKE x\(self.combo)"
        case 50...: "UNSTOPPABLE x\(self.combo)"
        case 30...: "ON FIRE x\(self.combo)"
        default: "COMBO x\(self.combo)"
        }
        let colors: [NSColor] = [.hex(0x5CFF8F), .hex(0xFFE45C), .hex(0xFF9F1C), .hex(0xFF4D6D)]
        // 後から追加したレイヤーほど手前に描かれるため、見出しは最後に重ねる
        self.emitConfetti(at: point, colors: colors + rank.colors, in: root)
        self.shockwave(at: point, color: rank.colors[0], in: root)
        self.flashEdges(color: rank.colors[rank.colors.count / 2], in: root)
        self.showBanner(title, colors: colors, fontSize: 64, center: CGPoint(x: point.x + 120, y: point.y - 70), in: root)
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
        self.run(group, on: layer, removeAfter: true)
    }

    private func showFloatingText(_ text: String, colors: [NSColor], at point: CGPoint, in root: CALayer) {
        guard let image = self.renderTitle(text, fontSize: 24, colors: colors, glow: colors[0]) else {
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
        self.run(group, on: layer, removeAfter: true)
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
                self.makeCell(image: confetti, color: color, birthRate: 220, velocity: 520, lifetime: 2.2, scale: 0.6, yAcceleration: -520, spin: 6),
                self.makeCell(image: star, color: color, birthRate: 60, velocity: 380, lifetime: 1.6, scale: 0.5, yAcceleration: -300, spin: 3)
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
        self.run(group, on: ring, removeAfter: true)
    }

    private func flashEdges(color: NSColor, in root: CALayer) {
        let border = CALayer()
        border.frame = root.bounds
        border.borderColor = color.cgColor
        border.borderWidth = 10
        border.shadowColor = color.cgColor
        border.shadowOffset = .zero
        border.shadowRadius = 24
        border.shadowOpacity = 1
        border.opacity = 0
        root.addSublayer(border)

        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0, 1, 0.6, 0]
        opacity.keyTimes = [0, 0.1, 0.4, 1]
        opacity.duration = 0.9
        self.run(opacity, on: border, removeAfter: true)
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
        self.run(opacity, on: tint, removeAfter: true)
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
            layer.shadowColor = NSColor.hex(0xFF9F1C).cgColor
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
            self.run(group, on: layer, removeAfter: true)
        }
    }

    private func run(_ animation: CAAnimation, on layer: CALayer, removeAfter: Bool) {
        CATransaction.begin()
        if removeAfter {
            CATransaction.setCompletionBlock {
                layer.removeFromSuperlayer()
            }
        }
        layer.add(animation, forKey: nil)
        CATransaction.commit()
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

private extension NSColor {
    static func hex(_ value: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
