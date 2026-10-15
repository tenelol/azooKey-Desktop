import AppKit
import Core
import QuartzCore

/// コンボ演出が有効なとき、システムの選択ハイライトを描かずに装飾側のハイライトへ任せる行ビュー
final class DopamineCandidateRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard !Config.DopamineEffects().value else {
            return
        }
        super.drawSelection(in: dirtyRect)
    }
}

/// 候補ウィンドウの縁を流れるネオン枠と、選択行へ滑って移動するハイライト
@MainActor
final class DopamineCandidateDecoration {
    private static let cornerRadius: CGFloat = 16
    private static let borderColors: [NSColor] = [
        .dopamineHex(0xFF4D6D), .dopamineHex(0xFFE45C), .dopamineHex(0x5CFF8F),
        .dopamineHex(0x5CF2FF), .dopamineHex(0xB45CFF), .dopamineHex(0xFF4D6D)
    ]
    private static let selectionColors: [NSColor] = [.dopamineHex(0xFF4D9D), .dopamineHex(0xB45CFF), .dopamineHex(0x5C8BFF)]

    private let borderContainer = CALayer()
    private let borderGradient = CAGradientLayer()
    private let borderMask = CAShapeLayer()
    private let selection = CAGradientLayer()
    private let sheen = CAGradientLayer()
    private var selectionVisible = false

    private var isEnabled: Bool {
        Config.DopamineEffects().value
    }

    func install(in container: NSView, tableView: NSTableView) {
        container.wantsLayer = true
        tableView.wantsLayer = true

        // 枠は回転する円錐グラデーションを細い角丸の線で切り抜いて作る
        self.borderGradient.type = .conic
        self.borderGradient.colors = Self.borderColors.map(\.cgColor)
        self.borderGradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        self.borderGradient.endPoint = CGPoint(x: 0.5, y: 0)
        self.borderMask.fillColor = nil
        self.borderMask.strokeColor = NSColor.white.cgColor
        self.borderMask.lineWidth = 2.5
        self.borderContainer.mask = self.borderMask
        self.borderContainer.addSublayer(self.borderGradient)
        self.borderContainer.zPosition = 100

        self.selection.colors = Self.selectionColors.map(\.cgColor)
        self.selection.startPoint = CGPoint(x: 0, y: 0.5)
        self.selection.endPoint = CGPoint(x: 1, y: 0.5)
        self.selection.cornerRadius = 9
        self.selection.shadowColor = Self.selectionColors[0].cgColor
        self.selection.shadowOffset = .zero
        self.selection.shadowRadius = 8
        self.selection.shadowOpacity = 0.9
        self.selection.opacity = 0
        self.selection.masksToBounds = false

        // 選択が動くたびに左から右へ走る光沢
        self.sheen.colors = [NSColor.white.withAlphaComponent(0).cgColor, NSColor.white.withAlphaComponent(0.55).cgColor, NSColor.white.withAlphaComponent(0).cgColor]
        self.sheen.startPoint = CGPoint(x: 0, y: 0.5)
        self.sheen.endPoint = CGPoint(x: 1, y: 0.5)
        self.sheen.opacity = 0
        let sheenClip = CALayer()
        sheenClip.masksToBounds = true
        sheenClip.cornerRadius = 9
        sheenClip.frame = .zero
        sheenClip.name = "sheenClip"
        sheenClip.addSublayer(self.sheen)
        self.selection.addSublayer(sheenClip)

        container.layer?.addSublayer(self.borderContainer)
        tableView.layer?.insertSublayer(self.selection, at: 0)
        self.applyEnabledState()
    }

    func layout(in bounds: CGRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.borderContainer.frame = bounds
        self.borderMask.frame = bounds
        let inset = self.borderMask.lineWidth / 2
        self.borderMask.path = CGPath(
            roundedRect: bounds.insetBy(dx: inset, dy: inset),
            cornerWidth: Self.cornerRadius - inset,
            cornerHeight: Self.cornerRadius - inset,
            transform: nil
        )
        // 回転しても四隅が欠けないよう、対角線長の正方形にして中央に置く
        let side = hypot(bounds.width, bounds.height)
        self.borderGradient.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        self.borderGradient.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
        self.applyEnabledState()
    }

    func moveSelection(to rowRect: CGRect?) {
        self.applyEnabledState()
        guard self.isEnabled, let rowRect, !rowRect.isEmpty else {
            self.selection.opacity = 0
            self.selectionVisible = false
            return
        }
        let target = rowRect.insetBy(dx: 5, dy: 2)
        let previous = self.selection.presentation()?.frame ?? self.selection.frame

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.selection.frame = target
        if let clip = self.selection.sublayers?.first(where: { $0.name == "sheenClip" }) {
            clip.frame = self.selection.bounds
            self.sheen.frame = CGRect(x: -target.width * 0.4, y: 0, width: target.width * 0.4, height: target.height)
        }
        self.selection.opacity = 1
        CATransaction.commit()

        if self.selectionVisible, previous != target {
            let move = CASpringAnimation(keyPath: "position")
            move.fromValue = NSValue(point: CGPoint(x: previous.midX, y: previous.midY))
            move.toValue = NSValue(point: CGPoint(x: target.midX, y: target.midY))
            move.damping = 18
            move.stiffness = 420
            move.duration = move.settlingDuration
            self.selection.add(move, forKey: "move")

            let size = CASpringAnimation(keyPath: "bounds.size")
            size.fromValue = NSValue(size: previous.size)
            size.toValue = NSValue(size: target.size)
            size.damping = 18
            size.stiffness = 420
            size.duration = size.settlingDuration
            self.selection.add(size, forKey: "size")
        } else {
            let pop = CAKeyframeAnimation(keyPath: "transform.scale")
            pop.values = [0.85, 1.04, 1]
            pop.duration = 0.25
            self.selection.add(pop, forKey: "pop")
        }

        let sweep = CABasicAnimation(keyPath: "position.x")
        sweep.fromValue = -target.width * 0.2
        sweep.toValue = target.width * 1.2
        sweep.duration = 0.45
        sweep.timingFunction = CAMediaTimingFunction(name: .easeOut)
        let sheenOpacity = CAKeyframeAnimation(keyPath: "opacity")
        sheenOpacity.values = [0, 1, 0]
        sheenOpacity.duration = 0.45
        self.sheen.add(sweep, forKey: "sweep")
        self.sheen.add(sheenOpacity, forKey: "sheenOpacity")
        self.selectionVisible = true
    }

    /// ウィンドウが表示されたときに下から浮き上がらせる
    func playAppear(on layer: CALayer?) {
        guard self.isEnabled, let layer else {
            return
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        let rise = CASpringAnimation(keyPath: "transform.translation.y")
        rise.fromValue = -10
        rise.toValue = 0
        rise.damping = 14
        rise.stiffness = 380
        let group = CAAnimationGroup()
        group.animations = [fade, rise]
        group.duration = rise.settlingDuration
        layer.add(group, forKey: "appear")
    }

    private func applyEnabledState() {
        let enabled = self.isEnabled
        self.borderContainer.isHidden = !enabled
        if enabled {
            if self.borderGradient.animation(forKey: "spin") == nil {
                let spin = CABasicAnimation(keyPath: "transform.rotation.z")
                spin.fromValue = 0
                spin.toValue = -2 * CGFloat.pi
                spin.duration = 3
                spin.repeatCount = .infinity
                self.borderGradient.add(spin, forKey: "spin")
            }
        } else {
            self.borderGradient.removeAnimation(forKey: "spin")
            self.selection.opacity = 0
            self.selectionVisible = false
        }
    }
}

extension NSColor {
    static func dopamineHex(_ value: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
