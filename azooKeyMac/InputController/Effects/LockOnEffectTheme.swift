import AppKit
import QuartzCore

/// Ghostty・Neovim の lock-on HUD と同じ動きの言葉。
/// アクセント1色と白のフラッシュ、加速しながら吸い付くホーミング、着弾後の減衰する揺れ、四隅のブラケット、広がる波紋を使う。
enum HUDStyle {
    static let accent = NSColor.effectHex(0x7AA2F7)
    static let flash = NSColor.white

    /// 目標へ加速しながら吸い付くホーミングの時間曲線（t² に近い ease-in）
    static let homing = CAMediaTimingFunction(controlPoints: 0.55, 0, 1, 0.45)
    static let easeOut = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.3, 1)

    /// 着弾後に一度振れて減衰する拡大率の揺れ
    static func wobble(amount: CGFloat, duration: CFTimeInterval, frequency: Double = 42, damping: Double = 14) -> CAKeyframeAnimation {
        let steps = 24
        let animation = CAKeyframeAnimation(keyPath: "transform.scale")
        animation.values = (0...steps).map { step in
            let t = Double(step) / Double(steps) * duration
            return 1 + amount * CGFloat(sin(t * frequency) * exp(-t * damping))
        }
        animation.duration = duration
        return animation
    }

    /// `size` の矩形の四隅に置く L 字ブラケット
    static func bracketPath(size: CGSize, arm: CGFloat) -> CGPath {
        let width = size.width
        let height = size.height
        let arm = min(arm, width / 2, height / 2)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: arm))
        path.addLine(to: .zero)
        path.addLine(to: CGPoint(x: arm, y: 0))
        path.move(to: CGPoint(x: width - arm, y: 0))
        path.addLine(to: CGPoint(x: width, y: 0))
        path.addLine(to: CGPoint(x: width, y: arm))
        path.move(to: CGPoint(x: width, y: height - arm))
        path.addLine(to: CGPoint(x: width, y: height))
        path.addLine(to: CGPoint(x: width - arm, y: height))
        path.move(to: CGPoint(x: arm, y: height))
        path.addLine(to: CGPoint(x: 0, y: height))
        path.addLine(to: CGPoint(x: 0, y: height - arm))
        return path
    }

    static func makeBrackets(size: CGSize, arm: CGFloat, lineWidth: CGFloat = 2) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.bounds = CGRect(origin: .zero, size: size)
        layer.path = self.bracketPath(size: size, arm: arm)
        layer.fillColor = nil
        layer.strokeColor = self.accent.cgColor
        layer.lineWidth = lineWidth
        layer.lineCap = .square
        layer.shadowColor = self.accent.cgColor
        layer.shadowOffset = .zero
        layer.shadowRadius = 5
        layer.shadowOpacity = 0.9
        return layer
    }

    /// 確定した文字列の幅は分からないため、行の高さから推定したフォントで測った枠
    static func committedTextBox(_ text: String, caret: CGRect) -> CGRect {
        let height = max(caret.height, 12)
        let font = NSFont.systemFont(ofSize: height * 0.78)
        let width = min(max(NSAttributedString(string: text, attributes: [.font: font]).size().width, height), 640)
        return CGRect(x: caret.minX - width, y: caret.minY, width: width, height: height).insetBy(dx: -4, dy: -3)
    }

    /// 白で点いてアクセントへ冷める色の変化
    static func cooling(keyPath: String, duration: CFTimeInterval) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = self.flash.cgColor
        animation.toValue = self.accent.cgColor
        animation.duration = duration
        animation.timingFunction = self.easeOut
        return animation
    }
}

@MainActor
final class LockOnEffectTheme: EffectTheme {
    let id = "lockon"
    let title = "ロックオン"

    /// 打鍵の残光。Ghostty の typing ignite と同じ長さにする
    private static let igniteDuration: CFTimeInterval = 0.42
    /// 確定は Enter の直後に手応えが欲しいので、ブラケットは短い距離を一瞬で吸い付かせる
    private static let lockTime: CFTimeInterval = 0.08
    private static let lockDuration: CFTimeInterval = 0.7

    func keystroke(at caret: CGRect) {
        guard let (root, local) = EffectOverlayWindow.shared.prepareRoot(for: caret) else {
            return
        }
        let height = max(local.height, 12)

        // キャレット位置に白く点いてアクセントへ冷める縦の残光
        let ignite = CALayer()
        ignite.bounds = CGRect(x: 0, y: 0, width: 2, height: height * 0.8)
        ignite.position = CGPoint(x: local.minX, y: local.midY)
        ignite.backgroundColor = HUDStyle.accent.cgColor
        ignite.shadowColor = HUDStyle.accent.cgColor
        ignite.shadowOffset = .zero
        ignite.shadowRadius = 6
        ignite.shadowOpacity = 1
        ignite.opacity = 0
        root.addSublayer(ignite)
        ignite.addEffectAnimation(self.fadingGroup(
            [HUDStyle.cooling(keyPath: "backgroundColor", duration: 0.24)],
            duration: Self.igniteDuration
        ), removeAfter: true)

        // ベースラインから左右へ広がる細い走査線
        let scan = CAGradientLayer()
        scan.colors = [NSColor.clear.cgColor, HUDStyle.accent.cgColor, HUDStyle.flash.cgColor, HUDStyle.accent.cgColor, NSColor.clear.cgColor]
        scan.locations = [0, 0.3, 0.5, 0.7, 1]
        scan.startPoint = CGPoint(x: 0, y: 0.5)
        scan.endPoint = CGPoint(x: 1, y: 0.5)
        scan.bounds = CGRect(x: 0, y: 0, width: height * 3.2, height: 1.5)
        scan.position = CGPoint(x: local.minX - height * 0.3, y: local.minY + 1)
        scan.shadowColor = HUDStyle.accent.cgColor
        scan.shadowOffset = .zero
        scan.shadowRadius = 3
        scan.shadowOpacity = 0.8
        scan.opacity = 0
        root.addSublayer(scan)
        let spread = CABasicAnimation(keyPath: "transform.scale.x")
        spread.fromValue = 0.15
        spread.toValue = 1
        spread.duration = Self.igniteDuration
        spread.timingFunction = HUDStyle.easeOut
        scan.addEffectAnimation(self.fadingGroup([spread], duration: Self.igniteDuration, peak: 0.55), removeAfter: true)
    }

    func commit(_ text: String, at caret: CGRect) {
        // 英字は1文字ずつ確定されるため、打鍵の残光だけにしてロックオンは出さない
        guard text.count >= 2 || !text.allSatisfy(\.isASCII), let (root, local) = EffectOverlayWindow.shared.prepareRoot(for: caret) else {
            return
        }
        let box = HUDStyle.committedTextBox(text, caret: local)

        // 四隅のブラケットが広い枠から回り込みつつ加速して吸い付く
        let brackets = HUDStyle.makeBrackets(size: box.size, arm: min(box.height * 0.45, 12))
        brackets.position = CGPoint(x: box.midX, y: box.midY)
        brackets.opacity = 0
        root.addSublayer(brackets)
        let approachScale = CABasicAnimation(keyPath: "transform.scale")
        approachScale.fromValue = 1.5
        approachScale.toValue = 1
        approachScale.duration = Self.lockTime
        approachScale.timingFunction = HUDStyle.homing
        let approachTurn = CABasicAnimation(keyPath: "transform.rotation.z")
        approachTurn.fromValue = 0.3
        approachTurn.toValue = 0
        approachTurn.duration = Self.lockTime
        approachTurn.timingFunction = HUDStyle.homing
        let wobble = HUDStyle.wobble(amount: 0.12, duration: 0.36)
        wobble.beginTime = Self.lockTime
        let color = HUDStyle.cooling(keyPath: "strokeColor", duration: 0.3)
        color.beginTime = Self.lockTime
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        // 確定した瞬間から見えているよう、最初のフレームから不透明にする
        opacity.values = [1, 1, 0]
        opacity.keyTimes = [0, 0.6, 1]
        let group = CAAnimationGroup()
        group.animations = [approachScale, approachTurn, wobble, color, opacity]
        group.duration = Self.lockDuration
        brackets.addEffectAnimation(group, removeAfter: true)

        // 吸い付いた瞬間に文字列の上を白く光らせ、細い衝撃波を外へ転がす
        let flash = CALayer()
        flash.frame = box
        flash.cornerRadius = 3
        flash.backgroundColor = HUDStyle.flash.withAlphaComponent(0.28).cgColor
        flash.opacity = 0
        root.addSublayer(flash)
        let flashOpacity = CAKeyframeAnimation(keyPath: "opacity")
        flashOpacity.values = [0, 1, 0]
        flashOpacity.keyTimes = [0, 0.1, 1]
        flashOpacity.duration = 0.3
        flashOpacity.beginTime = CACurrentMediaTime() + Self.lockTime
        flashOpacity.fillMode = .backwards
        flash.addEffectAnimation(flashOpacity, removeAfter: true)

        let wave = CAShapeLayer()
        wave.bounds = CGRect(origin: .zero, size: box.size)
        wave.position = CGPoint(x: box.midX, y: box.midY)
        wave.path = CGPath(roundedRect: wave.bounds, cornerWidth: 4, cornerHeight: 4, transform: nil)
        wave.fillColor = nil
        wave.strokeColor = HUDStyle.accent.cgColor
        wave.lineWidth = 1
        wave.opacity = 0
        root.addSublayer(wave)
        let waveScale = CABasicAnimation(keyPath: "transform.scale")
        waveScale.fromValue = 1
        waveScale.toValue = 1.35
        waveScale.timingFunction = HUDStyle.easeOut
        let waveOpacity = CABasicAnimation(keyPath: "opacity")
        waveOpacity.fromValue = 0.6
        waveOpacity.toValue = 0
        let waveGroup = CAAnimationGroup()
        waveGroup.animations = [waveScale, waveOpacity]
        waveGroup.duration = 0.48
        waveGroup.beginTime = CACurrentMediaTime() + Self.lockTime
        wave.addEffectAnimation(waveGroup, removeAfter: true)
    }

    func makeCandidateDecoration() -> (any CandidateDecoration)? {
        HUDCandidateDecoration(showsBrackets: true)
    }

    /// 一瞬で点いて二乗で消える不透明度を付けたグループ
    private func fadingGroup(_ animations: [CAAnimation], duration: CFTimeInterval, peak: Float = 1) -> CAAnimationGroup {
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0, peak, peak * 0.56, peak * 0.25, 0]
        opacity.keyTimes = [0, 0.05, 0.25, 0.5, 1]
        let group = CAAnimationGroup()
        group.animations = animations + [opacity]
        group.duration = duration
        return group
    }
}

/// 候補ウィンドウの細いアクセント枠と選択行のハイライト。
/// ブラケットありならロックオン、なしなら着いた行から波紋を広げる
@MainActor
final class HUDCandidateDecoration: CandidateDecoration {
    private static let cornerRadius: CGFloat = 16
    private static let moveDuration: CFTimeInterval = 0.14
    private static let restingFill = HUDStyle.accent.withAlphaComponent(0.22)

    private let border = CAShapeLayer()
    private let windowBrackets = CAShapeLayer()
    private let selection = CALayer()
    private let selectionFill = CALayer()
    private let selectionBrackets = CAShapeLayer()
    private weak var tableView: NSTableView?
    private var selectionVisible = false
    private var lastScrollOffset: CGFloat = 0
    private let showsBrackets: Bool

    init(showsBrackets: Bool) {
        self.showsBrackets = showsBrackets
    }

    func install(in container: NSView, tableView: NSTableView) {
        container.wantsLayer = true
        tableView.wantsLayer = true
        self.tableView = tableView

        self.border.fillColor = nil
        self.border.strokeColor = HUDStyle.accent.withAlphaComponent(0.45).cgColor
        self.border.lineWidth = 1
        self.border.zPosition = 100
        self.windowBrackets.fillColor = nil
        self.windowBrackets.strokeColor = HUDStyle.accent.cgColor
        self.windowBrackets.lineWidth = 2
        self.windowBrackets.lineCap = .square
        self.windowBrackets.zPosition = 101

        self.selectionFill.cornerRadius = 6
        self.selectionFill.backgroundColor = Self.restingFill.cgColor
        self.selectionBrackets.fillColor = nil
        self.selectionBrackets.strokeColor = HUDStyle.accent.cgColor
        self.selectionBrackets.lineWidth = 1.5
        self.selectionBrackets.lineCap = .square
        self.selectionBrackets.shadowColor = HUDStyle.accent.cgColor
        self.selectionBrackets.shadowOffset = .zero
        self.selectionBrackets.shadowRadius = 4
        self.selectionBrackets.shadowOpacity = 0.8
        self.selection.addSublayer(self.selectionFill)
        self.selection.addSublayer(self.selectionBrackets)
        self.selection.opacity = 0
        self.windowBrackets.isHidden = !self.showsBrackets
        self.selectionBrackets.isHidden = !self.showsBrackets

        container.layer?.addSublayer(self.border)
        container.layer?.addSublayer(self.windowBrackets)
        tableView.layer?.insertSublayer(self.selection, at: 0)
    }

    func uninstall() {
        self.border.removeFromSuperlayer()
        self.windowBrackets.removeFromSuperlayer()
        self.selection.removeFromSuperlayer()
    }

    func layout(in bounds: CGRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.border.frame = bounds
        self.border.path = CGPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            cornerWidth: Self.cornerRadius - 0.5,
            cornerHeight: Self.cornerRadius - 0.5,
            transform: nil
        )
        // 角丸の内側に収まるよう少し内側へ置く
        let frame = bounds.insetBy(dx: 5, dy: 5)
        self.windowBrackets.frame = frame
        self.windowBrackets.path = HUDStyle.bracketPath(size: frame.size, arm: 12)
        CATransaction.commit()
    }

    func alignSelection(toRow row: Int) {
        guard self.selectionVisible,
              let target = self.tableView?.effectRect(ofRow: row, inset: CGSize(width: 5, height: 2)),
              abs(target.minY - self.selection.frame.minY) > 1 else {
            return
        }
        EffectLog.candidate.notice(
            "realigned row \(row, privacy: .public) from y=\(Int(self.selection.frame.minY), privacy: .public) to y=\(Int(target.minY), privacy: .public)"
        )
        self.moveSelection(toRow: row)
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
        self.selectionFill.frame = CGRect(origin: .zero, size: target.size)
        self.selectionBrackets.frame = CGRect(origin: .zero, size: target.size)
        self.selectionBrackets.path = HUDStyle.bracketPath(size: target.size, arm: 7)
        self.selection.opacity = 1
        CATransaction.commit()

        var lockDelay: CFTimeInterval = 0
        if !self.selectionVisible {
            guard self.showsBrackets else {
                // 波紋は最初の行でもその場で広げる
                return self.finishSelection(at: target, in: tableView, lockDelay: 0)
            }
            // 初回は少し広い枠から吸い付く
            let approach = CABasicAnimation(keyPath: "transform.scale")
            approach.fromValue = 1.25
            approach.toValue = 1
            approach.duration = Self.moveDuration
            approach.timingFunction = HUDStyle.homing
            self.selectionBrackets.add(approach, forKey: "approach")
            lockDelay = Self.moveDuration
        } else if previous.origin != target.origin {
            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = NSValue(point: CGPoint(x: previous.midX, y: previous.midY))
            move.toValue = NSValue(point: CGPoint(x: target.midX, y: target.midY))
            move.duration = Self.moveDuration
            move.timingFunction = HUDStyle.homing
            self.selection.add(move, forKey: "move")
            lockDelay = Self.moveDuration
        }
        self.finishSelection(at: target, in: tableView, lockDelay: lockDelay)
    }

    private func finishSelection(at target: CGRect, in tableView: NSTableView, lockDelay: CFTimeInterval) {
        self.selectionVisible = true

        // 着いた瞬間に白く点いてアクセントへ冷め、ブラケットが一度揺れるか、行の縁から波紋が広がる
        let now = CACurrentMediaTime()
        if self.showsBrackets {
            let wobble = HUDStyle.wobble(amount: 0.08, duration: 0.3)
            wobble.beginTime = now + lockDelay
            self.selectionBrackets.add(wobble, forKey: "wobble")
            let cool = HUDStyle.cooling(keyPath: "strokeColor", duration: 0.28)
            cool.beginTime = now + lockDelay
            self.selectionBrackets.add(cool, forKey: "cool")
        } else {
            self.emitRowRipple(around: target, in: tableView, delay: lockDelay)
        }
        let flash = CABasicAnimation(keyPath: "backgroundColor")
        flash.fromValue = HUDStyle.flash.withAlphaComponent(0.45).cgColor
        flash.toValue = Self.restingFill.cgColor
        flash.duration = 0.28
        flash.timingFunction = HUDStyle.easeOut
        flash.beginTime = now + lockDelay
        self.selectionFill.add(flash, forKey: "flash")
    }

    /// 選択行の角丸の縁が外へ押し出されるように広がって消える
    private func emitRowRipple(around rect: CGRect, in tableView: NSTableView, delay: CFTimeInterval) {
        let ring = CAShapeLayer()
        ring.frame = tableView.bounds
        ring.fillColor = nil
        ring.strokeColor = HUDStyle.accent.cgColor
        ring.lineWidth = 1.5
        ring.shadowColor = HUDStyle.accent.cgColor
        ring.shadowOffset = .zero
        ring.shadowRadius = 4
        ring.shadowOpacity = 1
        ring.opacity = 0
        let from = CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6, transform: nil)
        let to = CGPath(roundedRect: rect.insetBy(dx: -10, dy: -7), cornerWidth: 12, cornerHeight: 12, transform: nil)
        ring.path = to
        tableView.layer?.insertSublayer(ring, above: self.selection)

        let grow = CABasicAnimation(keyPath: "path")
        grow.fromValue = from
        grow.toValue = to
        grow.timingFunction = HUDStyle.easeOut
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.8
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = 0.42
        group.beginTime = CACurrentMediaTime() + delay
        ring.addEffectAnimation(group, removeAfter: true)
    }

    /// ウィンドウが出たときに枠が一度光り、ブラケットありなら四隅へ外側から吸い付く
    func playAppear(on layer: CALayer?) {
        let flash = CAKeyframeAnimation(keyPath: "strokeColor")
        flash.values = [HUDStyle.accent.withAlphaComponent(0.45).cgColor, HUDStyle.flash.cgColor, HUDStyle.accent.withAlphaComponent(0.45).cgColor]
        flash.keyTimes = [0, 0.35, 1]
        flash.duration = 0.5
        self.border.add(flash, forKey: "flash")
        guard self.showsBrackets else {
            return
        }
        let approach = CABasicAnimation(keyPath: "transform.scale")
        approach.fromValue = 1.12
        approach.toValue = 1
        approach.duration = 0.2
        approach.timingFunction = HUDStyle.homing
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.12
        let group = CAAnimationGroup()
        group.animations = [approach, fade]
        group.duration = 0.2
        self.windowBrackets.add(group, forKey: "appear")
    }
}

extension NSTableView {
    /// 行の矩形を装飾レイヤーの座標で返す。実際に描かれている行ビューのレイヤーから変換し、
    /// 取れないときだけ行番号から計算した矩形を使う
    func effectRect(ofRow row: Int, inset: CGSize) -> CGRect? {
        guard row >= 0, row < self.numberOfRows else {
            return nil
        }
        var rect = self.rect(ofRow: row)
        self.layoutSubtreeIfNeeded()
        if let tableLayer = self.layer, let rowLayer = self.rowView(atRow: row, makeIfNecessary: false)?.layer {
            let drawn = tableLayer.convert(rowLayer.bounds, from: rowLayer)
            if abs(drawn.minY - rect.minY) > 1 {
                EffectLog.candidate.notice(
                    "row \(row, privacy: .public) is drawn at y=\(Int(drawn.minY), privacy: .public) but computed at y=\(Int(rect.minY), privacy: .public)"
                )
            }
            rect = drawn
        }
        return rect.insetBy(dx: inset.width, dy: inset.height)
    }

    var effectScrollOffset: CGFloat {
        self.enclosingScrollView?.contentView.bounds.minY ?? 0
    }
}
