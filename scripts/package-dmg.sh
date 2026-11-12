#!/bin/bash
# 打包发布用的 DMG：Apple 芯片 + Intel 通用版，输出到 dist/DockDot-<版本>.dmg
# 用法：VERSION=1.0.0 scripts/package-dmg.sh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
export VERSION
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

STAGE="$WORK/DockDot"
mkdir -p "$STAGE"
./scripts/make-app.sh "$STAGE" --universal >/dev/null
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/安装说明.txt" <<'EOF'
DockDot 安装说明

1. 把 DockDot 拖到旁边的「Applications（应用程序）」文件夹。
2. 在「应用程序」里打开 DockDot。
   第一次打开时，macOS 可能提示「无法验证开发者」或「Apple 无法检查其是否包含恶意软件」：
   这是因为 DockDot 没有付费的 Apple 开发者签名。处理方法：
   打开 系统设置 → 隐私与安全性，在页面下方找到 DockDot，点「仍要打开」。
3. 按提示授权「辅助功能」（系统设置 → 隐私与安全性 → 辅助功能，打开 DockDot），
   然后从菜单栏退出 DockDot 再重新打开。⌥⌘ 快捷键需要这个权限。

使用：点屏幕边缘的小圆点，或单按一下 ⌥⌘，打开 App 圆盘。
系统要求：macOS 26 或更高版本。
项目主页：https://github.com/mars7233/DockDot
EOF

mkdir -p dist
DMG="dist/DockDot-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "DockDot $VERSION" -srcfolder "$STAGE" -ov -format UDZO -fs HFS+ "$DMG" >/dev/null
echo "$DMG"
