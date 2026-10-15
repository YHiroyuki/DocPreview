# Learnings（ハマりどころ・繰り返す注意点）

- 新しい知見は日付付きで追記。毎回必要なものは CLAUDE.md / `.claude/rules/` に昇格する。

## 2026-10-14
- SwiftPM のリソースは `Bundle.module` 経由。.app 化では `DocPreview_DocPreview.bundle` を `Contents/Resources` にコピーする必要がある（`scripts/build-app.sh`）。
- 開発環境ではスクリーンショットが撮れず（`screencapture` 失敗）、UI の動作は未検証。実機で選択→コメント→cmux 起動を確認すること。
- cmux の `new-workspace --command` の挙動（入力として送られるか直接実行か）は実機での確認が必要。

## 2026-10-14（描画まわり）
- `[hidden]` は作者 CSS の `display:flex` に負ける。`[hidden]{display:none!important}` を入れる。これを忘れると全面オーバーレイ（#empty）がスクロールやクリックを奪った。
- Markdown は iframe 内で非同期に描画する（CSS/JS を動的ロード）ため、iframe の `load` では描画前。`markdown-view.js` が終了時に `parent.dpDocReady()` を呼び、コメントのハイライトはそこで適用する。
- GitHub 風表示は vendored の github-markdown-css(light/dark) + highlight.js + mermaid(動的ロード)。テーマは親の `dpSettings` を iframe 側が同期参照して決める。設定変更時は iframe をリロードする。
- 動作検証: `screencapture` が使えないため、環境変数 `DOCPREVIEW_EVAL`（JS 評価）/ `DOCPREVIEW_SNAPSHOT`（PNG 保存）/ `DOCPREVIEW_DELAY` を用意した。例: `DOCPREVIEW_SNAPSHOT=/tmp/x.png build/DocPreview.app/Contents/MacOS/DocPreview <path>`。検証で設定（UserDefaults）やコメントが残る点に注意。
- 設定（背景: 白/黒/システム、フォントサイズ）は ⌘, で開く。フォントサイズは Markdown のみ対象。HTML ドキュメントは元のスタイルのまま。

## 2026-10-14（ペイン幅）
- 縦の仕切りのドラッグは `setPointerCapture` を使う。iframe 上にカーソルが出ても pointermove を受け取れる（mouse イベントだと iframe に奪われる）。幅は UserDefaults(leftWidth/rightWidth) に保存し、ダブルクリックで既定値に戻す。
- 合成イベントでのテストでは `setPointerCapture`/`hasPointerCapture` を差し替えないと動かない（実ポインタが無いため）。

## 2026-10-14（Tokyo Night テーマ）
- github-markdown-css は色が CSS 変数でなく HEX 直書きのため、`scripts/gen-tokyonight-css.py` で HEX を置換して `vendor/tokyonight-{light,dark}.css` を生成している。元の `github-markdown-{light,dark}.css` は生成元として vendor に残す。色を調整するときはスクリプトの対応表を直して再生成する。
- アプリ UI の色は `app.css` の CSS 変数、コードは `tokyonight-hljs-*.css`、mermaid は `markdown-view.js` の `themeVariables`、コメントのハイライトは `app.js` の `onDocLoaded` で、テーマごとに別々に定義している。配色を変えるときは 4 箇所を揃える。
- HTML ドキュメントは元のスタイルのため、テーマの影響を受けない（背景は白のまま）。

## 2026-10-14（ファイル内検索）
- ⌘F / ⌘G / ⇧⌘G はネイティブのメニュー項目（`BlockItem`）から `openFind()` などの JS を呼ぶ。キー入力を WKWebView 側で拾うより確実。
- 検索は iframe 内の描画後テキストを `buildIndex` で連結して正規表現で走査し、`<mark class="dp-find">` でラップする（コメントのハイライトと同じ方式で、複数ノードにまたがるマッチも可）。後ろのマッチから順にラップするとオフセットが崩れない。
- 単純検索は正規表現にエスケープして同じ経路で処理する。空マッチは無視し、上限 5000 件。

## 2026-10-15（ツリーのアイコンと git ルート）
- git ルートは `.git`（worktree/submodule ではファイル）を上に辿って探す。`git` コマンドは呼ばない（GUI アプリの PATH に依存しないため）。シンボリックリンクは解決せず、渡されたパス表記のまま辿る。
- ルートが変わるとコメントの保存先（ルートのパスのハッシュ）も変わる。非 git → git の切替前に付けたコメントは新しいルートでは見えない。
- ツリーのアイコンは JS 内のインライン SVG（`ICONS`）。色は `currentColor` / `--accent` で、テーマに追従する。

## 2026-10-15（大きなリポジトリで重い問題）
- 症状: spark-server（追跡外含め約 13 万ファイル）を開くと固まった。原因は (1) 全ディレクトリを `FileManager` で再帰走査していた、(2) その走査を UI スレッド上で、しかも poll（1.5 秒ごと）のたびにもう一度実行していた。
- 対策: git 管理下は `git ls-files --cached --others --exclude-standard` で一覧を取る（.gitignore を尊重し、約 0.15 秒）。非 git は `enumerator` で重いディレクトリ（vendor/node_modules 等）を `skipDescendants` する。走査は `TreeCache` でバックグラウンド実行・キャッシュし、poll は `cachedSignature` を返すだけにする（3 秒以上経っていれば裏で再走査）。
- 教訓: UI スレッド（`userContentController`）で I/O の重い処理をしない。poll で毎回ツリーを作らない。
- 実測: spark-server の ADR を開いて 0.7 秒で描画完了（ツリー 933 ファイル）。
