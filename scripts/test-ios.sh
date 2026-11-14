#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/logs build/tools
if [[ ! -f Vendor/McBopomofo/Source/Data/data.txt ]]; then
    python3 scripts/generate-data.py > build/logs/ios-data.log 2>&1
fi
python3 scripts/prepare-ios.py
generator="${XCODEGEN_BIN:-$PWD/build/tools/xcodegen/bin/xcodegen}"
if [[ ! -x "$generator" ]]; then
    curl --fail --location --retry 3 --output build/tools/xcodegen.zip \
        https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip
    python3 - <<'PY'
import hashlib, pathlib
path = pathlib.Path('build/tools/xcodegen.zip')
assert hashlib.sha256(path.read_bytes()).hexdigest() == '4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806', 'XcodeGen checksum mismatch'
PY
    unzip -qo build/tools/xcodegen.zip -d build/tools
fi
"$generator" generate --spec platforms/ios/project.yml
simulator="${JIANFAN_IOS_SIMULATOR:-$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); phones=[v["udid"] for k,vs in d["devices"].items() if "iOS" in k for v in vs if "iPhone" in v["name"]]; assert phones, "Install an iOS simulator runtime in Xcode"; print(phones[-1])')}"
xcodebuild -project platforms/ios/Jianfan.xcodeproj -scheme Jianfan -configuration Debug \
    -destination "platform=iOS Simulator,id=$simulator" -derivedDataPath build/iOSDerived \
    CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES test > build/logs/ios-tests.log 2>&1
tail -24 build/logs/ios-tests.log
