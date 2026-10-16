#!/usr/bin/env bash
# dpgk-IME のビルド済み azooKeyMac.app を入れ、変換サーバーの LaunchAgent を登録する。
# 配布 zip を展開したフォルダの中で実行する（管理者パスワードを1回聞かれる）。
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_app="${here}/azooKeyMac.app"
install_app="/Library/Input Methods/azooKeyMac.app"
label="dev.ensan.inputmethod.azooKeyMac.ConverterServer"
agent="${HOME}/Library/LaunchAgents/${label}.plist"
domain="gui/$(id -u)"

if [ "$(uname -m)" != "arm64" ]; then
    echo "dpgk-IME は Apple Silicon の Mac 専用です" >&2
    exit 1
fi
if [ ! -d "${source_app}" ]; then
    echo "azooKeyMac.app が見つかりません: ${source_app}" >&2
    exit 1
fi

# ad-hoc 署名のため、ダウンロードで付いた隔離属性を外さないと起動を拒否される
xattr -dr com.apple.quarantine "${source_app}" 2>/dev/null || true
codesign --verify --deep --strict "${source_app}"

echo "azooKeyMac.app を ${install_app} に入れます"
sudo rm -rf "${install_app}"
sudo ditto "${source_app}" "${install_app}"

mkdir -p "$(dirname "${agent}")"
cat > "${agent}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${label}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${install_app}/Contents/Helpers/ConverterServer/ConverterServer</string>
    </array>
    <key>MachServices</key>
    <dict>
        <key>${label}</key>
        <true/>
    </dict>
    <key>KeepAlive</key>
    <true/>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
PLIST

launchctl bootout "${domain}/${label}" >/dev/null 2>&1 || true
launchctl bootstrap "${domain}" "${agent}"
# 起動中の IME は次の入力で新しい app から起動し直される
pkill -x azooKeyMac >/dev/null 2>&1 || true

cat <<'DONE'
インストールしました。
初めて入れた場合は、一度ログアウトしてログインし直してから
「システム設定 > キーボード > 入力ソース」で azooKey（日本語・英語）を追加してください。
演出は入力メニューの「演出テーマ」から切り替えられます。
DONE
