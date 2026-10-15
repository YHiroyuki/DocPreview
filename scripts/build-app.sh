#!/bin/bash
# DocPreview.app を build/ に作る。使い方: scripts/build-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BIN=$(swift build -c release --show-bin-path)
APP=build/DocPreview.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/DocPreview" "$APP/Contents/MacOS/"
# SwiftPM のリソースバンドルは Bundle.module が Contents/Resources から探す
cp -R "$BIN/DocPreview_DocPreview.bundle" "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>DocPreview</string>
<key>CFBundleIdentifier</key><string>com.yhiroyuki.DocPreview</string>
<key>CFBundleExecutable</key><string>DocPreview</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>0.1.0</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleDocumentTypes</key><array>
<dict>
<key>CFBundleTypeName</key><string>Markdown / HTML</string>
<key>CFBundleTypeRole</key><string>Viewer</string>
<key>LSHandlerRank</key><string>Alternate</string>
<key>CFBundleTypeExtensions</key><array><string>md</string><string>markdown</string><string>html</string><string>htm</string></array>
</dict>
<dict>
<key>CFBundleTypeName</key><string>Folder</string>
<key>CFBundleTypeRole</key><string>Viewer</string>
<key>LSHandlerRank</key><string>Alternate</string>
<key>LSItemContentTypes</key><array><string>public.folder</string></array>
</dict>
</array>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "built: $APP  (使い方: open -a $APP --args <path>)"
