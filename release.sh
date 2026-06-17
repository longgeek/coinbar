#!/bin/bash
# 发布一个版本：构建 → ditto 打包 zip → Sparkle EdDSA 签名 → 生成 appcast.xml。
# 跑完后：提交并推送 appcast.xml，再 gh release create 把 zip 传上去（命令会打印出来）。
set -euo pipefail
cd "$(dirname "$0")"

APP="CoinBar"
REPO="longgeek/coinbar"

./build.sh --no-open
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "build/$APP.app/Contents/Info.plist")"
ZIP="build/$APP-v$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "build/$APP.app" "$ZIP"

# Sparkle 用 Keychain 里的私钥签名（首次可能弹 Keychain 授权，点「始终允许」）。
SIGN_UPDATE="$(find .build/artifacts -path '*Sparkle/bin/sign_update' | head -1)"
SIGINFO="$("$SIGN_UPDATE" "$ZIP")"      # 形如：sparkle:edSignature="..." length="..."

URL="https://github.com/$REPO/releases/download/v$VERSION/$APP-v$VERSION.zip"
PUBDATE="$(date -u +'%a, %d %b %Y %H:%M:%S +0000')"
cat > appcast.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>CoinBar</title>
    <item>
      <title>$VERSION</title>
      <pubDate>$PUBDATE</pubDate>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <enclosure url="$URL" $SIGINFO type="application/octet-stream" />
    </item>
  </channel>
</rss>
EOF

echo "==> 已生成 $ZIP 与 appcast.xml（v$VERSION）"
echo "    下一步："
echo "    git add appcast.xml && git commit -m \"release: v$VERSION\" && git push"
echo "    gh release create v$VERSION \"$ZIP\" --title \"CoinBar v$VERSION\""
