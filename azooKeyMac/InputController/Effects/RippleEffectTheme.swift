import AppKit
import QuartzCore

/// Neovim を開いたときに Ghostty が出す衝撃波と同じ波紋。
/// 画面の裏側は読めないので屈折は再現せず、柔らかい帯と細い光る縁が広がって消える
@MainActor
final class RippleEffectTheme: EffectTheme {
    let id = "ripple"
    let title = "波紋"

    /// Ghostty の hudShockwave と同じ長さと届く距離（行の高さの倍数）
    private static let waveDuration: CFTimeInterval = 0.48
    private static let waveReach: CGFloat = 7
    /// 確定した文字列が光る時間（exp(-t * 10) が十分小さくなるまで）
    private static let flashDuration: CFTimeInterval = 0.3

    func keystroke(at caret: CGRect) {
        guard let (root, local) = EffectOverlayWindow.shared.prepareRoot(for: caret) else {
            return
        }
        let height = max(local.height, 12)
        self.emitRipple(
            in: root,
            center: CGPoint(x: local.minX, y: local.midY),
            radii: height * 0.3...height * 1.6,
            duration: 0.32,
            strength: 0.45
        )
    }

    func commit(_ text: String, at caret: CGRect) {
        // 英字は1文字ずつ確定されるため、打鍵の波紋だけにする
        guard text.count >= 2 || !text.allSatisfy(\.isASCII), let (root, local) = EffectOverlayWindow.shared.prepareRoot(for: caret) else {
            return
        }
        let box = HUDStyle.committedTextBox(text, caret: local)

        // 確定した文字列が白く光ってアクセントへ冷める
        let flash = CALayer()
        flash.frame = box
        flash.cornerRadius = 3
        flash.backgroundColor = HUDStyle.accent.withAlphaComponent(0.3).cgColor
        flash.opacity = 0
        root.addSublayer(flash)
        let cool = CABasicAnimation(keyPath: "backgroundColor")
        cool.fromValue = HUDStyle.flash.withAlphaComponent(0.6).cgColor
        cool.toValue = HUDStyle.accent.withAlphaComponent(0.3).cgColor
        cool.timingFunction = HUDStyle.easeOut
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 0.37, 0.14, 0]
        fade.keyTimes = [0, 0.33, 0.66, 1]
        let group = CAAnimationGroup()
        group.animations = [cool, fade]
        group.duration = Self.flashDuration
        flash.addEffectAnimation(group, removeAfter: true)

        self.emitRipple(
            in: root,
            center: CGPoint(x: box.midX, y: box.midY),
            radii: box.height * 0.5...box.height * Self.waveReach,
            duration: Self.waveDuration,
            strength: 1
        )
    }

    func makeCandidateDecoration() -> (any CandidateDecoration)? {
        HUDCandidateDecoration(showsBrackets: false)
    }

    /// 柔らかいアクセントの帯と細い白い縁を、ease-out で広げながら線形に消す
    private func emitRipple(in root: CALayer, center: CGPoint, radii: ClosedRange<CGFloat>, duration: CFTimeInterval, strength: Float) {
        let band = self.makeRing(color: HUDStyle.accent, lineWidth: 8, glow: 10)
        let edge = self.makeRing(color: HUDStyle.flash, lineWidth: 1.2, glow: 2)
        for (ring, peak, startWidth, endWidth) in [(band, 0.5 * strength, 12.0, 4.0), (edge, 0.85 * strength, 1.6, 0.8)] {
            ring.frame = root.bounds
            ring.path = Self.circle(center: center, radius: radii.upperBound)
            root.addSublayer(ring)
            let grow = CABasicAnimation(keyPath: "path")
            grow.fromValue = Self.circle(center: center, radius: radii.lowerBound)
            grow.toValue = ring.path
            grow.timingFunction = HUDStyle.easeOut
            let thin = CABasicAnimation(keyPath: "lineWidth")
            thin.fromValue = startWidth
            thin.toValue = endWidth
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = peak
            fade.toValue = 0
            let group = CAAnimationGroup()
            group.animations = [grow, thin, fade]
            group.duration = duration
            ring.addEffectAnimation(group, removeAfter: true)
        }
    }

    private func makeRing(color: NSColor, lineWidth: CGFloat, glow: CGFloat) -> CAShapeLayer {
        let ring = CAShapeLayer()
        ring.fillColor = nil
        ring.strokeColor = color.cgColor
        ring.lineWidth = lineWidth
        ring.shadowColor = color.cgColor
        ring.shadowOffset = .zero
        ring.shadowRadius = glow
        ring.shadowOpacity = 1
        ring.opacity = 0
        return ring
    }

    private static func circle(center: CGPoint, radius: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2), transform: nil)
    }
}
