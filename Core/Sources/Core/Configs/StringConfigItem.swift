//
//  StringConfigItem.swift
//  azooKeyMac
//
//  Created by miwa on 2024/04/27.
//

import Foundation

protocol StringConfigItem: ConfigItem<String> {}

extension StringConfigItem {
    public var value: String {
        get {
            Config.string(forKey: Self.key) ?? ""
        }
        nonmutating set {
            Config.set(newValue, forKey: Self.key)
        }
    }
}

extension Config {
    public struct ZenzaiProfile: StringConfigItem {
        public init() {}

        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.ZenzaiProfile"
    }
}

extension Config {
    /// OpenAIモデル名
    public struct OpenAiModelName: StringConfigItem {
        public init() {}

        public static let `default`: String = "gpt-4o-mini"
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.OpenAiModelName"
    }

    /// OpenAI API エンドポイント
    public struct OpenAiApiEndpoint: StringConfigItem {
        public init() {}

        public static let `default` = "https://api.openai.com/v1/chat/completions"
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.OpenAiApiEndpoint"

        public var value: String {
            get {
                let stored = Config.string(forKey: Self.key) ?? ""
                return stored.isEmpty ? Self.default : stored
            }
            nonmutating set {
                Config.set(newValue, forKey: Self.key)
            }
        }
    }

    /// プロンプト履歴（JSON形式で保存）
    public struct PromptHistory: StringConfigItem {
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.PromptHistory"
    }
}

extension Config {
    /// 打鍵・確定・候補ウィンドウの演出テーマのID
    public struct EffectTheme: ConfigItem {
        public init() {}

        static let `default` = "dopamine"
        /// テーマ選択の前に使っていた演出のオン・オフ設定
        static let legacyEnabledKey = "dev.ensan.inputmethod.azooKeyMac.preference.dopamineEffects"
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.effectTheme"

        public var value: String {
            get {
                if let value = Config.string(forKey: Self.key) {
                    return value
                }
                return Config.object(forKey: Self.legacyEnabledKey) as? Bool == false ? "off" : Self.default
            }
            nonmutating set {
                Config.set(newValue, forKey: Self.key)
            }
        }
    }
}
