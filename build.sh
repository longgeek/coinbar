#!/bin/bash
# 构建 CoinBar.app —— 编译 release 二进制并打包成菜单栏 .app(LSUIElement,无 Dock 图标)。
set -euo pipefail
cd "$(dirname "$0")"

APP="CoinBar"
VERSION="0.1.1"
BUNDLE_ID="com.longgeek.coinbar"

echo "==> swift build (release)"
swift build -c release

BIN="$(swift build -c release --show-bin-path)/$APP"
OUT="build/$APP.app"
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$BIN" "$OUT/Contents/MacOS/$APP"

# 嵌入 Sparkle.framework(放在图标渲染之前:渲染时二进制需能加载到 Sparkle)
echo "==> 嵌入 Sparkle.framework"
SPARKLE_FW="$(find .build/artifacts -path '*Sparkle.xcframework/macos-arm64*/Sparkle.framework' -type d | head -1)"
mkdir -p "$OUT/Contents/Frameworks"
cp -R "$SPARKLE_FW" "$OUT/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$OUT/Contents/MacOS/$APP" 2>/dev/null || true

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
  <key>SUFeedURL</key><string>https://raw.githubusercontent.com/longgeek/coinbar/main/appcast.xml</string>
  <key>SUPublicEDKey</key><string>mKu4XA/+8v0bafx8MWcMS9j9Df3t4AjoJ31KQ3reIS0=</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUScheduledCheckInterval</key><integer>86400</integer>
</dict>
</plist>
PLIST

# 临时 ad-hoc 签名(先签 Sparkle.framework,再签整个 app;分发版后续换正式签名/公证)。
codesign --force --deep --sign - "$OUT/Contents/Frameworks/Sparkle.framework" 2>/dev/null || true
codesign --force --deep --sign - "$OUT" 2>/dev/null || true

echo "==> Built $OUT"

# 构建后自动重启:退掉旧实例再打开新版(菜单栏常驻应用,open 不会自动换上新二进制)。
# 发布/CI 等不想自动启动时,加 `--no-open` 跳过。
if [[ " $* " != *" --no-open "* ]]; then
  echo "==> 重启 $APP"
  killall "$APP" 2>/dev/null || true
  for _ in 1 2 3 4 5; do pgrep -x "$APP" >/dev/null || break; sleep 0.3; done
  open "$OUT"
fi
