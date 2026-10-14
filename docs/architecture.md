# アーキテクチャ

## 構成
- `AppDelegate`: ウィンドウ、メニュー、JS ブリッジ（init / tree / poll / saveComments / launchClaude / openPanel）。
- `Workspace`: パス→ルート決定（ディレクトリならそれ自体、ファイルなら親）。md/html のツリー生成（空ディレクトリ・node_modules 等は除外）。
- `SchemeHandler`: `docpreview://app/ui/*`（UI）と `/doc/*`（ドキュメント）を配信。Markdown は HTML に整形して返す（`?raw` で生ファイル）。
- `CommentStore`: コメントを `~/Library/Application Support/DocPreview/comments/<rootハッシュ>.json` に保存。
- `ClaudeLauncher`: `cmux new-workspace --cwd <root> --command 'claude "$(cat prompt.md)"'` を実行。

## コメント
- 選択範囲を「描画後テキスト」上の quote + 前後30文字(prefix/suffix) として保存し、表示時にテキスト検索で再配置（`<mark>` でハイライト）。ソース行番号は使わない。
- 本文が変わって見つからないコメントは「orphan」と表示。
- 「Claude Code に依頼」は現在のファイルの未送信コメントを 1 つのプロンプトにまとめ、送信後 `sent` にする。

## 自動リロード
1.5 秒ごとに mtime とツリー署名を poll し、Claude Code の編集をプレビューに反映する。
