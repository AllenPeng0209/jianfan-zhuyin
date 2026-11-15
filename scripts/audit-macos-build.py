#!/usr/bin/env python3
"""Verify the installable payload itself, including apps nested in Resources."""
import argparse
import hashlib
import json
import pathlib
import plistlib
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("products", type=pathlib.Path)
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[1]
main = args.products / "JianfanZhuyin.app"
installer = args.products / "JianfanZhuyinInstaller.app"
payload = installer / "Contents/Resources/JianfanZhuyin.app"

def information(bundle):
    return plistlib.loads((bundle / "Contents/Info.plist").read_bytes())

expected = information(main)
for bundle in [main, installer, payload]:
    info = information(bundle)
    if bundle == payload:
        for key in ["CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion"]:
            assert info[key] == expected[key], f"Payload mismatch: {key}"
    result = subprocess.run(["codesign", "--verify", "--deep", "--strict", str(bundle)], capture_output=True, text=True)
    if result.returncode:
        raise SystemExit(f"Invalid installable bundle: {bundle.name}\n{result.stderr.strip()}")
    executable = bundle / "Contents/MacOS" / info["CFBundleExecutable"]
    architecture = subprocess.check_output(["lipo", "-archs", str(executable)], text=True).split()
    assert architecture == ["arm64"], f"Unexpected architecture: {architecture}"
    dependencies = subprocess.check_output(["otool", "-L", str(executable)], text=True).splitlines()[1:]
    assert not any(prefix in line for line in dependencies for prefix in ["/Users/", "/opt/homebrew/", "/usr/local/"]), "Build-machine dependency in package"
    assert not list(bundle.rglob("*.xctest")), "Test bundle in release payload"
    assert (bundle / "Contents/Resources/ThirdPartyNotices.txt").stat().st_size > 1000

for name in ["data.txt", "associated-phrases-v2.txt"]:
    source = root / "Vendor/McBopomofo/Source/Data" / name
    digest = hashlib.sha256(source.read_bytes()).digest()
    for bundle in [main, payload]:
        assert hashlib.sha256((bundle / "Contents/Resources" / name).read_bytes()).digest() == digest, f"Dictionary mismatch: {name}"

print(json.dumps({"version": expected["CFBundleShortVersionString"], "build": expected["CFBundleVersion"],
                  "architecture": "arm64", "mainAndPayloadSignatureIntegrity": "valid",
                  "dictionaryCopies": "match", "notarization": "not checked"}))
