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
