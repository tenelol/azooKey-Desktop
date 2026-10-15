import Cocoa
import Core
import InputMethodKit

extension azooKeyMacInputController {
    // MARK: - Settings and Menu Items

    func setupMenu() {
        self.appMenu.autoenablesItems = true
        self.liveConversionToggleMenuItem = NSMenuItem(title: "ライブ変換", action: #selector(self.toggleLiveConversion(_:)), keyEquivalent: "")
        self.appMenu.addItem(self.liveConversionToggleMenuItem)
        self.transformSelectedTextMenuItem = NSMenuItem(title: TransformMenuTitle.normal, action: #selector(self.performTransformSelectedText(_:)), keyEquivalent: "s")
        self.transformSelectedTextMenuItem.keyEquivalentModifierMask = [.control]
        self.transformSelectedTextMenuItem.target = self
        self.appMenu.addItem(self.transformSelectedTextMenuItem)
        self.appMenu.addItem(NSMenuItem.separator())
        self.addEffectThemeMenuItems()
        self.appMenu.addItem(NSMenuItem.separator())
        self.appMenu.addItem(NSMenuItem(title: "設定…", action: #selector(self.openConfigWindow(_:)), keyEquivalent: ""))
        self.appMenu.addItem(NSMenuItem(title: "View on GitHub…", action: #selector(self.openGitHubRepository(_:)), keyEquivalent: ""))
        self.updateTransformSelectedTextMenuItemEnabledState()
    }

    @objc func toggleLiveConversion(_ sender: Any) {
        self.appendDebugMessage("\(#line): toggleLiveConversion")
        let config = Config.LiveConversion()
        config.value = !self.liveConversionEnabled
        self.updateLiveConversionToggleMenuItem(newValue: config.value)
    }

    func updateLiveConversionToggleMenuItem(newValue: Bool) {
        self.liveConversionToggleMenuItem.state = newValue ? .on : .off
        self.liveConversionToggleMenuItem.title = "ライブ変換"
    }

    // MARK: - Effect Theme

    /// 入力メニューにテーマを並べ、選ぶとその場で切り替える
    private func addEffectThemeMenuItems() {
        let header = NSMenuItem(title: "演出テーマ", action: nil, keyEquivalent: "")
        header.isEnabled = false
        self.appMenu.addItem(header)
        // setupMenu は IMK から main thread で呼ばれる
        let themes = MainActor.assumeIsolated { EffectThemes.all.map { (id: $0.id, title: $0.title) } }
        for theme in themes {
            let item = NSMenuItem(title: theme.title, action: #selector(self.selectEffectTheme(_:)), keyEquivalent: "")
            item.representedObject = theme.id
            item.indentationLevel = 1
            self.appMenu.addItem(item)
        }
        self.updateEffectThemeMenuItems()
    }

    @objc func selectEffectTheme(_ sender: Any) {
        // IMK はメニュー項目を kIMKCommandMenuItemName に入れた辞書を sender として渡す
        let item = (sender as? NSMenuItem) ?? ((sender as? [AnyHashable: Any])?[kIMKCommandMenuItemName] as? NSMenuItem)
        guard let id = item?.representedObject as? String else {
            return
        }
        Config.EffectTheme().value = id
        self.updateEffectThemeMenuItems()
    }

    func updateEffectThemeMenuItems() {
        let current = Config.EffectTheme().value
        for item in self.appMenu.items where item.action == #selector(self.selectEffectTheme(_:)) {
            item.state = item.representedObject as? String == current ? .on : .off
        }
    }

    private enum TransformMenuTitle {
        static let normal = "いい感じ変換"
        static let noBackend = "いい感じ変換（無効/バックエンドなし）"
    }

    @MainActor @objc func performTransformSelectedText(_ sender: Any) {
        let aiBackendEnabled = Config.AIBackendPreference().value != .off
        self.updateTransformSelectedTextMenuItemTitle(aiBackendEnabled: aiBackendEnabled)
        guard aiBackendEnabled else {
            return
        }
        guard !self.isPromptWindowVisible else {
            return
        }
        guard let client = self.client() else {
            return
        }
        let hasSelection = client.selectedRange().length > 0
        if hasSelection {
            self.showPromptInputWindow()
            return
        }
        _ = self.requestPredictiveSuggestionWithConverterServer(client: client)
    }

    @MainActor @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem == self.transformSelectedTextMenuItem else {
            return true
        }
        let aiBackendEnabled = Config.AIBackendPreference().value != .off
        self.updateTransformSelectedTextMenuItemTitle(aiBackendEnabled: aiBackendEnabled)
        return self.canPerformTransformSelectedText(client: self.client())
    }

    func updateTransformSelectedTextMenuItemEnabledState() {
        let aiBackendEnabled = Config.AIBackendPreference().value != .off
        self.updateTransformSelectedTextMenuItemTitle(aiBackendEnabled: aiBackendEnabled)
        self.transformSelectedTextMenuItem.isEnabled = self.canPerformTransformSelectedText(client: self.client())
    }

    private func canPerformTransformSelectedText(client: IMKTextInput?) -> Bool {
        guard !self.isPromptWindowVisible else {
            return false
        }
        guard let client else {
            return false
        }
        let hasSelection = client.selectedRange().length > 0
        return hasSelection || self.inputState == .composing || self.inputState == .replaceSuggestion || self.inputState == .none
    }

    private func updateTransformSelectedTextMenuItemTitle(aiBackendEnabled: Bool) {
        self.transformSelectedTextMenuItem.title = aiBackendEnabled ? TransformMenuTitle.normal : TransformMenuTitle.noBackend
    }

    @objc func openGitHubRepository(_ sender: Any) {
        guard let url = URL(string: "https://github.com/azooKey/azooKey-Desktop") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc func openConfigWindow(_ sender: Any) {
        (NSApplication.shared.delegate as? AppDelegate)!.openConfigWindow()
    }

}
