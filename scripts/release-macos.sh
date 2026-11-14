#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${JIANFAN_DEVELOPER_ID:?Set the Developer ID Application signing identity}"
: "${JIANFAN_NOTARY_PROFILE:?Set an existing notarytool keychain profile}"
if [[ "$JIANFAN_DEVELOPER_ID" != "Developer ID Application:"* ]]; then
    printf '%s\n' 'A Developer ID Application identity is required.' >&2
    exit 1
fi
bash scripts/build-local.sh > build/logs/notarized-build.log 2>&1
products="$PWD/build/DerivedData/Build/Products/Release"
main="$products/JianfanZhuyin.app"
installer="$products/JianfanZhuyinInstaller.app"
payload="$installer/Contents/Resources/JianfanZhuyin.app"
test -d "$payload"
sign_bundle() {
    local bundle="$1"
    while IFS= read -r -d '' library; do
        codesign --force --sign "$JIANFAN_DEVELOPER_ID" --options runtime --timestamp "$library"
    done < <(if [[ -d "$bundle/Contents/Frameworks" ]]; then find "$bundle/Contents/Frameworks" -type f -name '*.dylib' -print0; fi)
    codesign --force --sign "$JIANFAN_DEVELOPER_ID" --options runtime --timestamp "$bundle"
    codesign --verify --deep --strict "$bundle"
}
sign_bundle "$main"
sign_bundle "$payload"
sign_bundle "$installer"
ditto -c -k --keepParent "$installer" build/Jianfan-notary.zip
xcrun notarytool submit build/Jianfan-notary.zip --keychain-profile "$JIANFAN_NOTARY_PROFILE" \
    --wait --output-format json > build/logs/notary-app-result.json
python3 - <<'PY'
import json
assert json.load(open('build/logs/notary-app-result.json'))['status'] == 'Accepted', 'Apple did not accept the notarization submission'
PY
xcrun stapler staple "$main"
xcrun stapler staple "$payload"
xcrun stapler staple "$installer"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$main/Contents/Info.plist")"
stage="$(mktemp -d "$PWD/build/notarized-dmg.XXXXXX")"
ditto "$installer" "$stage/安裝簡繁注音.app"
cp README.md "$stage/使用說明.md"
cp LICENSE "$stage/LICENSE.txt"
cp THIRD_PARTY.md "$stage/第三方來源.md"
dmg="$PWD/dist/JianfanZhuyin-$version-arm64-notarized.dmg"
hdiutil create -volname "簡繁注音 $version" -srcfolder "$stage" -format UDZO -ov "$dmg"
codesign --force --sign "$JIANFAN_DEVELOPER_ID" --timestamp "$dmg"
xcrun notarytool submit "$dmg" --keychain-profile "$JIANFAN_NOTARY_PROFILE" \
    --wait --output-format json > build/logs/notary-dmg-result.json
python3 - <<'PY'
import json
assert json.load(open('build/logs/notary-dmg-result.json'))['status'] == 'Accepted', 'Apple did not accept the disk image'
PY
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
spctl --assess --type execute --verbose "$installer"
(cd dist && shasum -a 256 "$(basename "$dmg")" > SHA256SUMS-macOS-notarized.txt)
printf 'Notarized installer: %s\n' "$dmg"
