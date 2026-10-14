# Learnings（ハマりどころ・繰り返す注意点）

- 新しい知見は日付付きで追記。毎回必要なものは CLAUDE.md / `.claude/rules/` に昇格する。

## 2026-10-14
- SwiftPM のリソースは `Bundle.module` 経由。.app 化では `DocPreview_DocPreview.bundle` を `Contents/Resources` にコピーする必要がある（`scripts/build-app.sh`）。
- 開発環境ではスクリーンショットが撮れず（`screencapture` 失敗）、UI の動作は未検証。実機で選択→コメント→cmux 起動を確認すること。
- cmux の `new-workspace --command` の挙動（入力として送られるか直接実行か）は実機での確認が必要。
