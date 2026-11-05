#!/bin/bash
# Builds the Transpono Gecko engine kit into ./engine-kit without compiling Gecko:
#   - Gecko headers via `mach build pre-export export` for the Firefox release
#     Reynard $REYNARD_TAG uses, with Reynard's patches applied;
#   - XUL, dylibs and Gecko resources from the official Reynard IPA (SHA-256
#     pinned in $REYNARD_IPA_SHA256);
#   - Reynard's GeckoView Swift wrapper (GPL-3.0) and Helper extension,
#     compiled here against those headers and binaries.
# Output layout:
#   engine-kit/Frameworks/{GeckoView.framework,XUL,*.dylib}
#   engine-kit/PlugIns/Reynard Helper.appex
#   engine-kit/include/            (Gecko dist/include)
#   engine-kit/headers/            (wrapper headers, flat)
set -euo pipefail

: "${REYNARD_TAG:?}" "${REYNARD_IPA_SHA256:?}"
ROOT="$PWD"
KIT="$ROOT/engine-kit"
WORK="$ROOT/.gecko-work"
rm -rf "$KIT" "$WORK"
mkdir -p "$WORK"
cd "$WORK"

git clone --depth 1 --branch "$REYNARD_TAG" https://github.com/minh-ton/reynard-browser.git reynard
FIREFOX_TAG="$(tr -d '\r\n ' < reynard/engine/release.txt)"
echo "Firefox tag: $FIREFOX_TAG"
git clone --depth 1 --branch "$FIREFOX_TAG" https://github.com/mozilla-firefox/firefox.git reynard/engine/firefox

count=0
while IFS= read -r patch; do
  git -C reynard/engine/firefox apply --whitespace=nowarn "$WORK/reynard/$patch"
  count=$((count + 1))
done < <(cd reynard && find patches -name '*.patch' | sort)
echo "Applied $count Reynard patches"

GECKO="$WORK/reynard/engine/firefox"
DIST="$GECKO/obj-aarch64-apple-ios/dist"
(
  cd "$GECKO"
  cat > .mozconfig <<'EOF'
ac_add_options --enable-application=mobile/ios
ac_add_options --target=aarch64-apple-ios
ac_add_options --enable-ios-target=13.0
ac_add_options --enable-optimize
ac_add_options --enable-release
ac_add_options --disable-debug
ac_add_options --disable-tests
ac_add_options --enable-bootstrap
EOF
  CC=clang CXX=clang++ LD=ld64.lld MOZ_NOSPAM=1 ./mach configure
  CC=clang CXX=clang++ LD=ld64.lld MOZ_NOSPAM=1 ./mach build pre-export export
)
test -f "$DIST/include/mozilla-config.h"

curl -sSL -o Reynard.ipa \
  "https://github.com/minh-ton/reynard-browser/releases/download/${REYNARD_TAG}/Reynard.ipa"
echo "${REYNARD_IPA_SHA256}  Reynard.ipa" | shasum -a 256 -c -
unzip -q Reynard.ipa -d reynard-ipa
APP="$WORK/reynard-ipa/Payload/Reynard.app"
mkdir -p "$DIST/bin"
cp -fL "$APP/Frameworks/XUL" "$DIST/bin/XUL"
cp -fL "$APP/Frameworks/"*.dylib "$DIST/bin/"
rm -f "$DIST/bin/libswift_Concurrency.dylib"
rsync -a "$APP/Frameworks/GeckoView.framework/Frameworks/" "$DIST/bin/"

(
  cd reynard/browser
  common=(
    -project Reynard.xcodeproj
    -sdk iphoneos -arch arm64 -configuration Release
    -xcconfig Configuration/Reynard.xcconfig
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
    SYMROOT="$PWD/build"
  )
  xcodebuild build -target GeckoView "${common[@]}"
  xcodebuild build -target "Reynard Helper" "${common[@]}"
)
OUT="$WORK/reynard/browser/build/Release-iphoneos"
ls "$OUT/GeckoView.framework/Modules/GeckoView.swiftmodule"

mkdir -p "$KIT/Frameworks" "$KIT/PlugIns" "$KIT/headers"
cp -R "$OUT/GeckoView.framework" "$KIT/Frameworks/"
mkdir -p "$KIT/Frameworks/GeckoView.framework/Frameworks"
rsync -a --exclude XUL --exclude '*.dylib' "$DIST/bin/" "$KIT/Frameworks/GeckoView.framework/Frameworks/"
mkdir -p "$KIT/Frameworks/GeckoView.framework/Frameworks/default-theme"
cp -RfL "$GECKO/toolkit/mozapps/extensions/default-theme/" \
  "$KIT/Frameworks/GeckoView.framework/Frameworks/default-theme/"
grep -q 'resource default-theme' "$KIT/Frameworks/GeckoView.framework/Frameworks/chrome.manifest" ||
  echo "resource default-theme file:default-theme/" >> "$KIT/Frameworks/GeckoView.framework/Frameworks/chrome.manifest"
cp -fL "$DIST/bin/XUL" "$DIST/bin/"*.dylib "$KIT/Frameworks/"
cp -R "$OUT/Reynard Helper.appex" "$KIT/PlugIns/"
rsync -aL "$DIST/include/" "$KIT/include/"
find "$WORK/reynard/browser" -name '*.h' -not -path '*/build/*' -exec cp -f {} "$KIT/headers/" \;
cp reynard/LICENSE "$KIT/LICENSE-Reynard-GPL-3.0"
cp reynard/LICENSE.firefox "$KIT/LICENSE-Firefox-MPL-2.0"
printf 'reynard=%s\nfirefox=%s\nipa_sha256=%s\nxcode=%s\n' \
  "$REYNARD_TAG" "$FIREFOX_TAG" "$REYNARD_IPA_SHA256" "$(xcodebuild -version | head -1)" > "$KIT/VERSIONS.txt"
du -sh "$KIT" "$KIT"/*
cd "$ROOT"
rm -rf "$WORK"
