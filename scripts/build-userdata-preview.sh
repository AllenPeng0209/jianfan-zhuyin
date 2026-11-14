#!/bin/bash
set -euo pipefail
JF_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$JF_ROOT"
swift build --package-path Vendor/McBopomofo/Packages/JianfanUserData --scratch-path build/UserDataTests
JF_PRODUCTS="$JF_ROOT/build/UserDataTests/out/Products/Debug"
JF_APP="$JF_ROOT/build/UserDataPreview.app"
mkdir -p "$JF_APP/Contents/MacOS" "$JF_APP/Contents/Resources"
swiftc -parse-as-library -target arm64-apple-macos13.0 -I "$JF_PRODUCTS" -L "$JF_PRODUCTS" \
  -lJianfanUserData Tools/UserDataPreview.swift -framework AppKit \
  -o "$JF_APP/Contents/MacOS/JianfanPhrasePreview"
ditto "$JF_PRODUCTS/JianfanUserData_JianfanUserData.bundle" "$JF_APP/Contents/Resources/JianfanUserData_JianfanUserData.bundle"
python3 - "$JF_APP" <<'PY'
import plistlib
import sys
from pathlib import Path
p=Path(sys.argv[1])/'Contents/Info.plist'
p.write_bytes(plistlib.dumps({'CFBundleIdentifier':'com.local.JianfanZhuyin.UserDataPreview','CFBundleName':'Jianfan Phrase Preview','CFBundleExecutable':'JianfanPhrasePreview','CFBundlePackageType':'APPL','CFBundleVersion':'1','NSPrincipalClass':'NSApplication','CFBundleDevelopmentRegion':'en','CFBundleAllowMixedLocalizations':True,'CFBundleLocalizations':['zh-Hant','zh-Hans','en']}))
PY
codesign --force --deep --sign - "$JF_APP"
