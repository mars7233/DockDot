#!/bin/bash
# 编译、打包、签名，并安装到 ~/Applications/DockDot.app
# （在临时目录里打包签名：Documents 在 iCloud 同步，会给文件加属性导致 codesign 拒绝）
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
APP="$WORK/DockDot.app"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/DockDot "$APP/Contents/MacOS/DockDot"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>local.dockdot</string>
  <key>CFBundleName</key><string>DockDot</string>
  <key>CFBundleExecutable</key><string>DockDot</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
EOF
xattr -cr "$APP"

# 有本机自用证书「DockDot Local Signing」就用它签名：签名身份固定，
# 重新编译后「辅助功能」权限不会失效。没有的话退回 ad-hoc 签名（每次编译都要重新授权）。
ID=$(security find-identity -p codesigning 2>/dev/null | awk '/"DockDot Local Signing"/ {print $2; exit}')
if [ -n "$ID" ]; then
  codesign --force --sign "$ID" "$APP"
else
  echo "未找到 DockDot Local Signing 证书，使用 ad-hoc 签名"
  codesign --force --sign - "$APP"
fi

DEST="$HOME/Applications/DockDot.app"
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
ditto "$APP" "$DEST"
echo "Installed $DEST"
