# dpgk-IME

[azooKey-Desktop](https://github.com/azooKey/azooKey-Desktop) に、打鍵・確定・候補ウィンドウの演出を足した非公式フォークです。公式の azooKey とは関係ありません。不具合は本家ではなくこのフォークに報告してください。

ベースは azooKey-Desktop の main（`bd90b7b`、v0.1.5-beta.1 より新しい開発版）です。

## できること

入力メニュー（メニューバーの azooKey）の「演出テーマ」から切り替えます。設定画面の「演出テーマ」でも選べます。

| テーマ | 内容 |
| --- | --- |
| なし | 演出なし（本家と同じ見た目） |
| 波紋 | 打鍵で小さな波紋、確定で文字列が光って大きな波紋が広がる。候補ウィンドウは選択行から波紋 |
| ロックオン | 確定した文字列に四隅のブラケットが吸い付く。候補ウィンドウの選択行にもブラケット |
| ドーパミン | コンボ数とランク表示、10コンボごとの花火、30コンボでフィーバー、キーワード（リリース・好き・最強など）で専用演出、確定の長さで NICE〜PERFECT |

本家 main に対して次の修正も入っています。

- 入力中に入力ソースを切り替えても、入力中の文字が消えない
- 変換に1秒以上かかったときに、再接続を繰り返して入力が止まらない
- 入力先のアプリへの位置の問い合わせを入力開始時の1回にまとめ、応答の遅いアプリで数秒詰まらない
- Ghostty などのターミナルで、入力を始めた1文字目の英字がそのまま入らない
- 候補ウィンドウの選択表示が1つ前の候補に残らない
- 遅い打鍵の内訳を `log show --predicate 'subsystem == "dev.ensan.inputmethod.azooKeyMac" AND category == "latency"'` で確認できる

## 動作環境

- Apple Silicon の Mac（arm64 のみ）
- macOS 15 以降を想定（作者は macOS 26 で使用）

## インストール

1. [Releases](../../releases) から `dpgk-IME-*.zip` をダウンロードして展開する
2. ターミナルで展開したフォルダに入り、`./install.sh` を実行する（管理者パスワードを1回聞かれます）
3. 初めて入れた場合は、ログアウトしてログインし直し、「システム設定 > キーボード > 入力ソース」で azooKey（日本語・英語）を追加する

ビルド済みの app は Apple の開発者証明書ではなく ad-hoc 署名です。`install.sh` がダウンロード時の隔離属性を外してから入れます。

公式の azooKey と同じ bundle ID（`dev.ensan.inputmethod.azooKeyMac`）を使うので、公式版が入っている場合は置き換わります。設定と学習データは公式版と共通です。

## アンインストール

展開したフォルダで `./uninstall.sh` を実行します。設定と学習データ（`~/Library/Group Containers/group.dev.ensan.inputmethod.azooKeyMac`）は残ります。公式版に戻す場合は、そのあと公式のインストーラを入れ直してください。

## ソースからビルドする

本家の [README](README.md) の「開発版のビルド・デバッグ」の手順（Git LFS・署名の設定・`install.sh`）がそのまま使えます。このフォークの変更は `dpgk-IME` ブランチにあり、追加したファイルは主に `azooKeyMac/InputController/Effects/` です。

## ライセンス

コードは本家と同じ MIT License です（[LICENSE](LICENSE)）。app に同梱している Zenzai の重み（zenz-v3.2-small-gguf）は Apache-2.0、言語モデル（base_n5_lm）を含むそのほかの同梱データは、それぞれの配布元の条件に従います。
