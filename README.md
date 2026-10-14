# DocPreview
macOS 向け Markdown / HTML プレビューア。左にファイルツリー、本文を選択してコメント、ボタン一つで cmux 上の Claude Code にコメントへの対応を依頼できる。

```
scripts/build-app.sh
open build/DocPreview.app --args /path/to/dir-or-file
# 開発時: swift run DocPreview /path/to/dir-or-file
```
