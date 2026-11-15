#!/bin/bash
set -euo pipefail

JF_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JF_BUILD="$JF_ROOT/build"
JF_PRODUCTS="$JF_BUILD/DerivedData/Build/Products/Release"
JF_DIST="$JF_ROOT/dist"
JF_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$JF_ROOT/Vendor/McBopomofo/Source/McBopomofo-Info.plist")"
JF_PACKAGE="JianfanZhuyin-$JF_VERSION-arm64.dmg"
mkdir -p "$JF_BUILD/logs" "$JF_DIST"

# Xcode can retain a prefix header after a local package's module map changes.
JF_PCH="$JF_BUILD/DerivedData/Build/Intermediates.noindex/PrecompiledHeaders"
if [[ -d "$JF_PCH" ]]; then
  /bin/rm -rf -- "$JF_PCH"
fi

if ! xcodebuild \
  -project "$JF_ROOT/Vendor/McBopomofo/McBopomofo.xcodeproj" \
  -scheme McBopomofoInstaller -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$JF_BUILD/DerivedData" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual CODE_SIGNING_REQUIRED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO build > "$JF_BUILD/logs/build-release.log" 2>&1; then
  tail -n 60 "$JF_BUILD/logs/build-release.log"
  exit 1
fi

/usr/bin/swift "$JF_ROOT/scripts/localize.swift" \
  "$JF_ROOT/Vendor/McBopomofo" \
  "$JF_PRODUCTS/JianfanZhuyin.app" \
  "$JF_PRODUCTS/JianfanZhuyinInstaller.app"

/usr/bin/codesign --force --deep --sign - --timestamp=none "$JF_PRODUCTS/JianfanZhuyin.app"
# Resources contains a separate installable app; sign it before sealing the installer.
/usr/bin/codesign --force --deep --sign - --timestamp=none "$JF_PRODUCTS/JianfanZhuyinInstaller.app/Contents/Resources/JianfanZhuyin.app"
/usr/bin/codesign --force --deep --sign - --timestamp=none "$JF_PRODUCTS/JianfanZhuyinInstaller.app"
/usr/bin/codesign --verify --deep --strict "$JF_PRODUCTS/JianfanZhuyinInstaller.app"
/usr/bin/python3 "$JF_ROOT/scripts/audit-macos-build.py" "$JF_PRODUCTS"

JF_STAGE="$JF_BUILD/dmg-stage"
mkdir -p "$JF_STAGE"
/usr/bin/ditto "$JF_PRODUCTS/JianfanZhuyinInstaller.app" "$JF_STAGE/安装简繁注音.app"
/bin/cp "$JF_ROOT/README.md" "$JF_STAGE/使用说明.md"
/bin/cp "$JF_ROOT/THIRD_PARTY.md" "$JF_STAGE/第三方来源.md"
/usr/bin/hdiutil create -volname "简繁注音 $JF_VERSION" -srcfolder "$JF_STAGE" \
  -format UDZO -ov "$JF_DIST/$JF_PACKAGE"
(
  cd "$JF_DIST"
  /usr/bin/shasum -a 256 "$JF_PACKAGE" > SHA256SUMS.txt
)
printf 'Built %s\n' "$JF_DIST/$JF_PACKAGE"
