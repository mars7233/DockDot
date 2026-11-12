#!/bin/bash
# 本地开发：编译本机架构、签名，并安装到 ~/Applications/DockDot.app
# （在临时目录里打包签名：Documents 在 iCloud 同步，会给文件加属性导致 codesign 拒绝）
set -euo pipefail
cd "$(dirname "$0")"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
./scripts/make-app.sh "$WORK" >/dev/null

DEST="$HOME/Applications/DockDot.app"
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
ditto "$WORK/DockDot.app" "$DEST"
echo "Installed $DEST"
