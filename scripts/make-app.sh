#!/bin/bash
# 编译并组装、签名 DockDot.app
# 用法：scripts/make-app.sh <输出目录> [--universal]
#   --universal  同时编译 Apple 芯片和 Intel（发布用）；不加只编本机架构（本地开发更快）
# 版本号取自环境变量 VERSION（默认 1.0.0）。
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="$1"; shift || true
ARCH_FLAGS=()
[ "${1:-}" = "--universal" ] && ARCH_FLAGS=(--arch arm64 --arch x86_64)
VERSION="${VERSION:-1.0.0}"
BUILD_NUM=$(git rev-list --count HEAD 2>/dev/null || echo 1)

swift build -c release "${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}"
BIN="$(swift build -c release "${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}" --show-bin-path)/DockDot"

APP="$OUT/DockDot.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DockDot"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>local.dockdot</string>
  <key>CFBundleName</key><string>DockDot</string>
  <key>CFBundleDisplayName</key><string>DockDot</string>
  <key>CFBundleExecutable</key><string>DockDot</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUM</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>© 2026 Mason</string>
</dict>
</plist>
EOF
# 去掉扩展属性（iCloud 同步目录会加），否则 codesign 会拒绝
xattr -cr "$APP"

# 有本机自用证书「DockDot Local Signing」就用它签名：签名身份固定，
# 升级/重新编译后「辅助功能」权限不会失效。没有的话退回 ad-hoc 签名。
ID=$(security find-identity -p codesigning 2>/dev/null | awk '/"DockDot Local Signing"/ {print $2; exit}')
if [ -n "$ID" ]; then
  codesign --force --sign "$ID" "$APP"
else
  echo "未找到 DockDot Local Signing 证书，使用 ad-hoc 签名（每次更新后都要重新授权辅助功能）"
  codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"
echo "$APP"
