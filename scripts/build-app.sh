#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release
app="$PWD/dist/Popaste.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/Popaste "$app/Contents/MacOS/Popaste"
rm -rf "$app/Contents/Resources/Popaste_Popaste.bundle"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>app.popaste.mac</string>
<key>CFBundleName</key><string>Popaste</string>
<key>CFBundleExecutable</key><string>Popaste</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - --identifier app.popaste.mac --requirements '=designated => identifier "app.popaste.mac"' "$app"
printf '%s\n' "Built: $app"
