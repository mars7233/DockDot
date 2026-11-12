#!/bin/bash
# 编译并打包成 build/DockDot.app
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP=build/DockDot.app
rm -rf "$APP"
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
codesign --force --sign - "$APP"
echo "Built $APP"
