#!/bin/bash
# Compiles TransponoGecko.framework against the engine kit and embeds Gecko
# into a built Runner.app. Usage: embed-gecko.sh <engine-kit> <Runner.app>
set -euo pipefail

KIT="$(cd "$1" && pwd)"
APP="$(cd "$2" && pwd)"
SRC="$(cd "$(dirname "$0")/../../apps/mobile/ios/gecko" && pwd)"
WORK="$(mktemp -d)"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"

FW="$WORK/TransponoGecko.framework"
mkdir -p "$FW"
xcrun --sdk iphoneos swiftc \
  -target arm64-apple-ios15.0 -sdk "$SDK" -O -parse-as-library \
  -module-name TransponoGecko -emit-library \
  -F "$KIT/Frameworks" -framework GeckoView \
  -Xcc -I"$KIT/headers" -Xcc -I"$KIT/include" -Xcc -I"$KIT/include/GeckoView" \
  -import-objc-header "$SRC/TransponoGecko-Bridging.h" \
  -Xlinker -install_name -Xlinker @rpath/TransponoGecko.framework/TransponoGecko \
  -Xlinker -rpath -Xlinker @executable_path/Frameworks \
  -Xlinker -rpath -Xlinker @loader_path/.. \
  -Xlinker "$KIT/Frameworks/XUL" \
  "$SRC/TransponoGeckoBridge.swift" -o "$FW/TransponoGecko"
cat > "$FW/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>TransponoGecko</string>
  <key>CFBundleIdentifier</key><string>app.transpono.gecko</string>
  <key>CFBundleName</key><string>TransponoGecko</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>MinimumOSVersion</key><string>15.0</string>
  <key>CFBundleSupportedPlatforms</key><array><string>iPhoneOS</string></array>
</dict>
</plist>
EOF
nm -gU "$FW/TransponoGecko" | grep -q '_transpono_gecko_main'

mkdir -p "$APP/Frameworks" "$APP/PlugIns"
cp -R "$KIT/Frameworks/GeckoView.framework" "$APP/Frameworks/"
cp -f "$KIT/Frameworks/XUL" "$KIT/Frameworks/"*.dylib "$APP/Frameworks/"
cp -R "$FW" "$APP/Frameworks/"
# Reynard's Gecko only lets GeckoView install built-in extensions from
# resource://android/... or exactly resource://app/extensions/readerview/
# (patches/mobile/shared/modules/geckoview/GeckoViewWebExtension.sys.mjs.patch).
# Transpono does not use Reynard's reader view, so its relay takes that slot.
EXT="$APP/Frameworks/GeckoView.framework/Frameworks/extensions/readerview"
rm -rf "$EXT" "$APP/Frameworks/GeckoView.framework/Frameworks/extensions/transpono"
mkdir -p "$EXT"
cp -f "$SRC/extension/"* "$EXT/"

APP_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"
# Keep Reynard's folder name: Gecko (NSExtensionUtils.mm in Reynard's patches)
# finds the content-process extension at PlugIns/"Reynard Helper.appex" and
# reads its bundle id from there. Any other name means no content process and
# a blank (black) view. The bundle id itself may change.
HELPER="$APP/PlugIns/Reynard Helper.appex"
rm -rf "$APP/PlugIns/Transpono Helper.appex"
rm -rf "$HELPER"
cp -R "$KIT/PlugIns/Reynard Helper.appex" "$HELPER"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${APP_ID}.Helper" "$HELPER/Info.plist"

find "$APP/Frameworks" -maxdepth 1 | sort
du -sh "$APP"
rm -rf "$WORK"
