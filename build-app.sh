#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

swift build -c release --disable-sandbox
BIN="$(swift build -c release --disable-sandbox --show-bin-path)/倒计时Timer"
APP="$ROOT/暮光计时.app"
ICONSET="$ROOT/AppIcon.iconset"
ICON="$ROOT/AppIcon.icns"

swift "$ROOT/generate-icon.swift" "$ICONSET" "$ICON"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/倒计时Timer"
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
mkdir -p "$APP/Contents/Resources/BuiltinSounds"
cp "$ROOT/内置铃声确认/"*.wav "$ROOT/内置铃声确认/"*.mp3 "$ROOT/内置铃声确认/"*.txt "$APP/Contents/Resources/BuiltinSounds/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>暮光计时</string>
<key>CFBundleDisplayName</key><string>暮光计时</string>
<key>CFBundleIdentifier</key><string>com.estella.twilight-timer.prototype</string>
<key>CFBundleExecutable</key><string>倒计时Timer</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.5.0</string>
<key>CFBundleVersion</key><string>11</string>
<key>NSRequiresAquaSystemAppearance</key><false/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "已生成：$APP"
