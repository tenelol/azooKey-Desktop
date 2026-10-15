import AppKit
import QuartzCore

/// 候補ウィンドウの縁を流れるネオン枠と、選択行へ滑って移動するハイライト
@MainActor
final class DopamineCandidateDecoration: CandidateDecoration {
    private static let cornerRadius: CGFloat = 16
    private static let borderColors: [NSColor] = [
        .effectHex(0xFF4D6D), .effectHex(0xFFE45C), .effectHex(0x5CFF8F),
        .effectHex(0x5CF2FF), .effectHex(0xB45CFF), .effectHex(0xFF4D6D)
    ]
    private static let selectionColors: [NSColor] = [.effectHex(0xFF4D9D), .effectHex(0xB45CFF), .effectHex(0x5C8BFF)]

    private let borderContainer = CALayer()
    private let borderGradient = CAGradientLayer()
    private let borderMask = CAShapeLayer()
    private let selection = CAGradientLayer()
    private let sheen = CAGradientLayer()
    private var selectionVisible = false
    private var lastScrollOffset: CGFloat = 0
    private weak var tableView: NSTableView?

    func install(in container: NSView, tableView: NSTableView) {
        container.wantsLayer = true
        tableView.wantsLayer = true
        self.tableView = tableView

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

        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = -2 * CGFloat.pi
        spin.duration = 3
        spin.repeatCount = .infinity
        self.borderGradient.add(spin, forKey: "spin")
    }

    func uninstall() {
        self.borderContainer.removeFromSuperlayer()
        self.selection.removeFromSuperlayer()
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
    }

    func moveSelection(toRow row: Int?) {
        guard let row, let tableView = self.tableView, let target = tableView.effectRect(ofRow: row, inset: CGSize(width: 5, height: 2)) else {
            self.selection.opacity = 0
            self.selectionVisible = false
            return
        }
        // 選択に合わせて一覧がスクロールした分だけ開始位置をずらし、見た目の位置から動かす
        let scrollOffset = tableView.effectScrollOffset
        var previous = self.selection.presentation()?.frame ?? self.selection.frame
        previous.origin.y += scrollOffset - self.lastScrollOffset
        self.lastScrollOffset = scrollOffset

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.selection.frame = target
        if let clip = self.selection.sublayers?.first(where: { $0.name == "sheenClip" }) {
            clip.frame = self.selection.bounds
            self.sheen.frame = CGRect(x: -target.width * 0.4, y: 0, width: target.width * 0.4, height: target.height)
        }
        self.selection.opacity = 1
        CATransaction.commit()

        if !self.selectionVisible {
            let pop = CAKeyframeAnimation(keyPath: "transform.scale")
            pop.values = [0.85, 1.04, 1]
            pop.duration = 0.25
            self.selection.add(pop, forKey: "pop")
        } else if previous != target {
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
        guard let layer else {
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
}
