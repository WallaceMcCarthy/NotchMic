#!/bin/zsh
set -e
cd "$(dirname "$0")"
APP="${1:-$HOME/Applications/NotchMic.app}"   # optional: output path
mkdir -p "$APP/Contents/MacOS"
swiftc -O -target arm64-apple-macos13 main.swift -o "$APP/Contents/MacOS/NotchMic"   # every notched MacBook is Apple silicon
# App icon from icon/NotchMic_1024.png (redraw with: swift icon/draw_variants.swift, run inside icon/)
SET=$(mktemp -d)/AppIcon.iconset; mkdir -p "$SET" "$APP/Contents/Resources"
for s in 16 32 128 256 512; do
  sips -z $s $s icon/NotchMic_1024.png --out "$SET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) icon/NotchMic_1024.png --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.notchmic</string>
<key>CFBundleName</key><string>NotchMic</string>
<key>CFBundleExecutable</key><string>NotchMic</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
PL
codesign --force -s - "$APP"
echo built "$APP"
