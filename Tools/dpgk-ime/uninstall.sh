#!/usr/bin/env bash
# install.sh で入れた azooKeyMac.app と変換サーバーの LaunchAgent を取り除く。
# 学習データと設定（~/Library/Group Containers/group.dev.ensan.inputmethod.azooKeyMac）は残す。
set -euo pipefail

install_app="/Library/Input Methods/azooKeyMac.app"
label="dev.ensan.inputmethod.azooKeyMac.ConverterServer"
agent="${HOME}/Library/LaunchAgents/${label}.plist"

launchctl bootout "gui/$(id -u)/${label}" >/dev/null 2>&1 || true
rm -f "${agent}"
pkill -x azooKeyMac >/dev/null 2>&1 || true
if [ -d "${install_app}" ]; then
    sudo rm -rf "${install_app}"
fi
echo "dpgk-IME を取り除きました。入力ソースの一覧に残っていれば、システム設定から削除してください。"
