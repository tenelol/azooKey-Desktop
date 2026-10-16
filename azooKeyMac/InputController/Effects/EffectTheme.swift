import AppKit
import Core
import os
import QuartzCore

/// 打鍵・確定・候補ウィンドウに重ねる演出の一式。入力メニューと設定画面から切り替える。
@MainActor
protocol EffectTheme: AnyObject {
    var id: String { get }
    var title: String { get }
    /// 文字を打つたびに呼ばれる。`caret` はスクリーン座標（左下原点）のキャレット行の矩形
    func keystroke(at caret: CGRect)
    /// 確定した文字列ごとに呼ばれる。`caret` は確定後のキャレット行の矩形
    func commit(_ text: String, at caret: CGRect)
    /// 候補ウィンドウの装飾。nil ならシステム標準の見た目のまま
    func makeCandidateDecoration() -> (any CandidateDecoration)?
}

/// 候補ウィンドウ1枚ぶんの装飾。テーマが切り替わると外して作り直す
@MainActor
protocol CandidateDecoration: AnyObject {
    func install(in container: NSView, tableView: NSTableView)
    func uninstall()
    func layout(in bounds: CGRect)
    func moveSelection(toRow row: Int?)
    /// 一覧のリサイズやスクロールが反映されたあとに、選択の装飾が行からずれていれば合わせ直す
    func alignSelection(toRow row: Int)
    func playAppear(on layer: CALayer?)
}

/// 候補ウィンドウの位置ずれを調べるためのログ。入力内容は残さない
enum EffectLog {
    static let candidate = Logger(subsystem: "dev.ensan.inputmethod.azooKeyMac", category: "candidate")
}

@MainActor
enum EffectThemes {
    static let off = OffEffectTheme()
    static let all: [any EffectTheme] = [off, RippleEffectTheme(), LockOnEffectTheme(), DopamineEffectTheme()]

    static var current: any EffectTheme {
        let id = Config.EffectTheme().value
        return all.first { $0.id == id } ?? off
    }

    static var isActive: Bool {
        current !== off
    }
}

final class OffEffectTheme: EffectTheme {
    let id = "off"
    let title = "なし"
    func keystroke(at caret: CGRect) {}
    func commit(_ text: String, at caret: CGRect) {}
    func makeCandidateDecoration() -> (any CandidateDecoration)? {
        nil
    }
}

/// 装飾がハイライトを描くテーマでは、システムの選択ハイライトを描かない行ビュー
final class EffectCandidateRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard !EffectThemes.isActive else {
            return
        }
        super.drawSelection(in: dirtyRect)
    }
}

/// 演出を描く全画面の透明パネル。全テーマで共有し、演出がない間は画面から外す
@MainActor
final class EffectOverlayWindow {
    static let shared = EffectOverlayWindow()

    /// 最も長い演出（粒子の寿命）が終わるまで待ってからウィンドウを隠す
    private static let idleHideDelay: TimeInterval = 5.0

    private var window: NSPanel?
    private var rootLayer: CALayer?
    private var hideWorkItem: DispatchWorkItem?

    private init() {}

    var backingScale: CGFloat {
        self.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    /// `rect` を含むスクリーンへウィンドウを合わせて前面に出し、描画先のレイヤーとローカル座標の矩形を返す
    func prepareRoot(for rect: CGRect) -> (CALayer, CGRect)? {
        let point = CGPoint(x: rect.minX, y: rect.midY)
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
        self.scheduleHide()
        guard let root = self.rootLayer else {
            return nil
        }
        return (root, rect.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY))
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

    /// 透明でも全画面ウィンドウが前面に残ると他のツールやウィンドウマネージャから見えるため、
    /// 演出がない間は画面から外す
    private func scheduleHide() {
        self.hideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.window?.orderOut(nil)
            }
        }
        self.hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.idleHideDelay, execute: workItem)
    }
}

extension CALayer {
    /// アニメーションを付け、`removeAfter` なら終わったときにレイヤーごと外す
    func addEffectAnimation(_ animation: CAAnimation, removeAfter: Bool) {
        CATransaction.begin()
        if removeAfter {
            CATransaction.setCompletionBlock { [weak self] in
                self?.removeFromSuperlayer()
            }
        }
        self.add(animation, forKey: nil)
        CATransaction.commit()
    }
}

extension NSColor {
    static func effectHex(_ value: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
