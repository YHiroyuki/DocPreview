# アーキテクチャ

## 構成
- `AppDelegate`: メニューと、開いているタブ（`DocWindow`）の管理。パスを渡されると新しいタブで開く（同じ対象が開いていればそのタブを前面に）。
- `DocWindow`: 1 タブ分（NSWindow + WKWebView + `SchemeHandler` + `TreeCache` + `Workspace`）。JS ブリッジ（init / tree / poll / saveComments / title / launchClaude / openPanel）もここ。`DropWebView` がファイル/フォルダのドロップを受ける。
- `Workspace`: パス→ルート決定。git 管理下なら git ルート、そうでなければディレクトリ自体（ファイル指定なら親）。ディレクトリ指定時は `initialDir` を展開して配下の最初のファイルを開く。md/html のツリー生成（git 管理下は `git ls-files`、それ以外は走査）。`TreeCache` がバックグラウンドで走査してキャッシュする。`.` 始まりのフォルダは既定で非表示。サイドバーの目アイコンで表示すると遅延ロード用ノード（`lazy`）になり、展開時に `children` アクションで中身を読む。
- `SchemeHandler`: `docpreview://app/ui/*`（UI）と `/doc/*`（ドキュメント）を配信。Markdown は HTML に整形して返す（`?raw` で生ファイル）。
- `CommentStore`: コメントを `~/Library/Application Support/DocPreview/comments/<rootハッシュ>.json` に保存。
- `ClaudeLauncher`: `cmux new-workspace --cwd <root> --command 'claude "$(cat prompt.md)"'` を実行。

## コメント
- 選択範囲を「描画後テキスト」上の quote + 前後30文字(prefix/suffix) として保存し、表示時にテキスト検索で再配置（`<mark>` でハイライト）。ソース行番号は使わない。
- 本文が変わって見つからないコメントは「orphan」と表示。
- 「Claude Code に依頼」は現在のファイルの未送信コメントを 1 つのプロンプトにまとめ、送信後 `sent` にする。

## 自動リロード
1.5 秒ごとに mtime とツリー署名を poll し、Claude Code の編集をプレビューに反映する。

## タブとドロップ
- タブは macOS ネイティブのウィンドウタブ（`tabbingIdentifier` 共通、`addTabbedWindow`）。タブごとにルート・ツリー・コメントが独立する。
- ⌘O、`open` コマンド、Dock へのドロップ、ウィンドウへのドロップはいずれも新しいタブで開く。ドロップは md/markdown/html/htm とフォルダのみ受け付ける。
- タブ名は開いているファイル名（JS が `title` アクションで通知）。
