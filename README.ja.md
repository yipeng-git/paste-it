# Paste It

[English](README.md) | [中文](README.zh-CN.md) | **日本語** | [한국어](README.ko.md)

ローカル完結の macOS クリップボードマネージャー — ネイティブ SwiftUI、Liquid Glass、エージェント向け MCP。

**ウェブサイト：** [paste-it.app](https://paste-it.app)

![Paste It timeline panel](docs/screenshots/paste-it-history-panel.png)

- **完全ローカル** — アカウント不要、クラウド同期なし。履歴はこの Mac にだけ残ります。
- **ネイティブ SwiftUI** — AppKit のフローティングパネルと SwiftUI のタイムライン。**macOS 26+ は Liquid Glass**（それ以前はマテリアルにフォールバック）。
- **AI 向け** — ローカルの **MCP**（任意）で、エージェントが履歴の参照・検索（OCR 含む）、一時的なタイムライン画像の生成ができます。
- **画像の中身も検索** — Vision OCR がコピーした画像やスクリーンショットをインデックス。テキスト、リッチテキスト、HTML、ファイル、リンクも対象です。

![Search clipboard history including OCR](docs/screenshots/paste-it-ocr-search.png)

スクリーンショットや画像の中の文字も探せます — プレーンテキストだけではありません。

## 機能

- フローティングタイムライン（**Shift + Command + V**）— カードとプレビューを眺める。
- Pinboard：ドラッグ＆ドロップでピン留め、永久保存も可。
- Paste Stack（**Shift + Command + C**）— 集めて並べ替え、順番にペーストする準備。
- Quick Copy：**Command + 1…9**、プレーンテキストでペースト、複数項目のテキストコピー。
- プライバシー：キャプチャ一時停止、アプリや pasteboard タイプの除外、保持期間、ストレージ整理。
- 匿名の利用統計（PostHog・任意）— クリップボード内容は**送りません**。[`docs/analytics.md`](docs/analytics.md) と [`docs/analytics-dashboard.md`](docs/analytics-dashboard.md)。設定 → プライバシーで切り替え。
- Sparkle によるアプリ内アップデート。

クリップを選ぶとシステムペーストボードに載ります（アクセシビリティ不要）。Paste Stack の「Paste Next」は必要なら **Command + V** を自動入力し、そのときはアクセシビリティが必要です。

## プライバシーと分析

クリップボード履歴は **この Mac だけ**。公式ビルドでは PostHog がデフォルトでオンで、パネルの開閉、ペースト準備、オンボーディング、アップデートまわりなどの匿名イベントだけ送ります — テキスト、OCR、パス、検索語は**含みません**。イベント一覧：[`docs/analytics.md`](docs/analytics.md)。ダッシュボードの作り方：[`docs/analytics-dashboard.md`](docs/analytics-dashboard.md)。**設定 → プライバシー** でいつでもオフにできます。

## エージェント向け MCP

ローカルの [Model Context Protocol](https://modelcontextprotocol.io) サーバー（任意）— **デフォルトはオフ**。Paste It 起動中にメニューバーの **MCP** から有効化します。

- URL：`http://127.0.0.1:17321/mcp`（ループバックのみ、Stateless HTTP）
- 読み取り専用：list、get、search（元アプリ、OCR、アプリと同じクエリ）
- カード内容から一時的なタイムライン画像を生成（本履歴には書き込まない）

ツール、curl 例、クライアント設定は [`docs/mcp.md`](docs/mcp.md)（英語）。

## 動作環境

- macOS 14+
- Xcode / Swift 6.2 ツールチェーン

## 実行

```sh
swift run PasteIt
```

最小構成の `.app` を作る（更新チェック用に Sparkle を埋め込み）：

```sh
./scripts/run-app.sh
```

このフォルダを Xcode で開けば、Swift Package として実行・デバッグできます。

## アップデート

自動更新は Sparkle。フィードは [`Info.plist`](Info.plist) の `SUFeedURL`（GitHub Pages）。詳しくは [`docs/mac-updates.md`](docs/mac-updates.md)。署名付きリリースは [`scripts/package-release.sh`](scripts/package-release.sh) — 手順は [`docs/mac-packaging.md`](docs/mac-packaging.md)。

## ライセンス

[PolyForm Noncommercial License 1.0.0](LICENSE) — 個人・教育・研究・趣味など非商用は無料。**商用は著作権者との別契約が必要**です。

このライセンス変更より前に MIT で出したバージョンは、そのリリースに限りこれまでどおり MIT で使えます。
