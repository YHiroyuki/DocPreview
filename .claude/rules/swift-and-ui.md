# 実装規約
- UI（`Resources/ui`）はバンドラ無しの素の JS。依存を増やす場合は vendored ファイルとして置き、ネットワーク取得に依存しない。
- ドキュメントと UI は同一オリジン `docpreview://app` で配信する（iframe の DOM をコメント機能が操作するため）。`file://` 直読みに変えない。
- ファイル配信は必ずルート配下かを検証する（`SchemeHandler.inside`）。
- Swift ⇄ JS の通信は `native` メッセージハンドラ（`AppDelegate.userContentController`）に action を足す形で拡張する。
- cmux 連携は `ClaudeLauncher` に集約する。プロンプトはファイル経由で渡す（シェルのエスケープ事故を避ける）。
- Package は tools-version 5.9（Swift 5 言語モード）を維持する。
