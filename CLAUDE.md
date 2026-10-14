# DocPreview

macOS 向けの Markdown / HTML プレビューア。ツリー表示、選択範囲へのコメント、cmux 経由で Claude Code を起動してコメントに対応させる。

## 技術スタック
- Swift (SwiftPM, macOS 13+) + WKWebView。UI は `Sources/DocPreview/Resources/ui` の素の HTML/JS/CSS（ビルド不要）。
- Markdown 描画は vendored の `marked.min.js`。ターミナルは cmux、AI agent は Claude Code。

## コマンド
- ビルド: `swift build` / 実行: `swift run DocPreview <path>`
- .app 作成: `scripts/build-app.sh`（`build/DocPreview.app`）

## ルール・ドキュメント
- 詳細な設計: `docs/architecture.md`
- ハマりどころ・繰り返す注意点: `docs/learnings.md`（困ったこと・繰り返したことが出たら追記する）
- AI に毎回効かせたい規約は `.claude/rules/` に置く。

## 運用方針
- 作業中に繰り返しや困りごとがあれば `docs/learnings.md` に残す。毎回のコンテキストとして必要なものは本ファイルか `.claude/rules/` に昇格させる。
- `gh` を使う前にアカウント切替が必要（ユーザー共通 CLAUDE.md 参照）。

## ブランチ運用
- `main` へ直接コミットしない。main から `feature/<内容>` `fix/<内容>` などのブランチを切って開発し、PR 経由でマージする。
- 初回コミット（雛形）のみ例外として main に直接入れている。
