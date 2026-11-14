#!/bin/bash
set -euo pipefail
JF_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$JF_ROOT"
JF_PROFILE="JianfanZhuyin-Tests-$(uuidgen)"
JF_DD="$JF_ROOT/build/DerivedData"
mkdir -p build/logs
JF_ARGS=(-project Vendor/McBopomofo/McBopomofo.xcodeproj -scheme McBopomofo -configuration Debug
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$JF_DD" -parallel-testing-enabled NO
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual CODE_SIGNING_REQUIRED=NO ONLY_ACTIVE_ARCH=YES
  COMPILER_INDEX_STORE_ENABLE=NO MACOSX_DEPLOYMENT_TARGET=14.0 "JF_DATA_FOLDER_NAME=$JF_PROFILE")
JF_PCH="$JF_DD/Build/Intermediates.noindex/PrecompiledHeaders"
if [[ -d "$JF_PCH" ]]; then /bin/rm -rf -- "$JF_PCH"; fi
xcodebuild "${JF_ARGS[@]}" build-for-testing > build/logs/v02-build-tests.log 2>&1
python3 scripts/assert-test-profile.py "$JF_DD/Build/Products/Debug/JianfanZhuyin.app"
if [[ $# -gt 0 ]]; then
  xcodebuild "${JF_ARGS[@]}" test-without-building "-only-testing:$1" > build/logs/v02-focused-macos-test.log 2>&1
  exit 0
fi
xcodebuild "${JF_ARGS[@]}" test-without-building \
  -only-testing:McBopomofoTests/OfflinePersonalizationTests/test01WritesChoiceForProcessRestart \
  > build/logs/v02-write-process.log 2>&1
xcodebuild "${JF_ARGS[@]}" test-without-building \
  -only-testing:McBopomofoTests/OfflinePersonalizationTests/test02RestoresChoiceWithoutSelectingAgain \
  > build/logs/v02-read-process.log 2>&1
xcodebuild "${JF_ARGS[@]}" test-without-building > build/logs/v02-all-macos-tests.log 2>&1
printf 'Verified independent write/read processes and the full Mac regression suite\n'
