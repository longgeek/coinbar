#!/bin/bash
# 构建 CoinBar.app —— 编译 release 二进制并打包成菜单栏 .app(LSUIElement,无 Dock 图标)。
set -euo pipefail
cd "$(dirname "$0")"

APP="CoinBar"
VERSION="0.1.0"
BUNDLE_ID="com.longgeek.coinbar"

echo "==> swift build (release)"
swift build -c release

BIN="$(swift build -c release --show-bin-path)/$APP"
OUT="build/$APP.app"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$BIN" "$OUT/Contents/MacOS/$APP"

# 从 IconView(代码即唯一来源)渲染 1024 主图,再生成多尺寸 .icns
echo "==> 生成 app 图标"
TMP_ICON="$(mktemp -d)/icon1024.png"
"$OUT/Contents/MacOS/$APP" --render-icon "$TMP_ICON" >/dev/null 2>&1 || true
if [ -f "$TMP_ICON" ]; then
  ICONSET="$(mktemp -d)/AppIcon.iconset"; mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z "$s" "$s" "$TMP_ICON" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z "$((s * 2))" "$((s * 2))" "$TMP_ICON" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$OUT/Contents/Resources/AppIcon.icns"
fi

cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP</string>
  <key>CFBundleDisplayName</key><string>$APP</string>
  <key>CFBundleExecutable</key><string>$APP</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict>
</plist>
PLIST

# 临时 ad-hoc 签名,便于本机直接运行(分发版后续可换正式签名/公证)。
codesign --force --deep --sign - "$OUT" 2>/dev/null || true

echo "==> Built $OUT"
