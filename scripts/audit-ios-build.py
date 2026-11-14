#!/usr/bin/env python3
import argparse
import hashlib
import pathlib
import plistlib
import subprocess
import struct

parser = argparse.ArgumentParser()
parser.add_argument("bundle", type=pathlib.Path)
parser.add_argument("--signed", action="store_true")
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[1]
app = args.bundle
keyboard = app / "PlugIns/JianfanKeyboard.appex"
with (app / "Info.plist").open("rb") as file:
    info = plistlib.load(file)
with (keyboard / "Info.plist").open("rb") as file:
    extension = plistlib.load(file)
assert extension["CFBundleIdentifier"].startswith(info["CFBundleIdentifier"] + ".")
attributes = extension["NSExtension"]["NSExtensionAttributes"]
assert attributes["RequestsOpenAccess"] is False
assert attributes["IsASCIICapable"] is True
assert extension["NSExtension"]["NSExtensionPointIdentifier"] == "com.apple.keyboard-service"
assert info["ITSAppUsesNonExemptEncryption"] is False
for bundle in [app, keyboard]:
    privacy = plistlib.loads((bundle / "PrivacyInfo.xcprivacy").read_bytes())
    assert privacy["NSPrivacyTracking"] is False
    assert privacy["NSPrivacyCollectedDataTypes"] == []
    for name in ["data.txt", "associated-phrases-v2.txt"]:
        data = (bundle / "Dictionaries" / name).read_bytes()
        assert data.startswith(b"# format org.openvanilla.mcbopomofo.sorted\n")
        source = (root / "Vendor/McBopomofo/Source/Data" / name).read_bytes()
        assert hashlib.sha256(data).digest() == hashlib.sha256(source).digest()
    assert (bundle / "Dictionaries/ThirdPartyNotices.txt").stat().st_size > 1000
    if args.signed:
        subprocess.run(["codesign", "--verify", "--strict", str(bundle)], check=True, capture_output=True)
if args.signed:
    entitlements = []
    for bundle in [app, keyboard]:
        result = subprocess.run(["codesign", "-d", "--entitlements", ":-", str(bundle)], check=True, capture_output=True)
        values = plistlib.loads(result.stdout)
        bundle_info = plistlib.loads((bundle / "Info.plist").read_bytes())
        if bundle_info.get("DTSDKName", "").startswith("iphonesimulator"):
            # Xcode embeds simulator entitlements in Mach-O, outside the code signature.
            binary = (bundle / bundle_info["CFBundleExecutable"]).read_bytes()
            assert struct.unpack_from("<I", binary)[0] == 0xFEEDFACF
            command = 32
            for _ in range(struct.unpack_from("<I", binary, 16)[0]):
                kind, size = struct.unpack_from("<II", binary, command)
                if kind == 0x19:
                    for section in range(struct.unpack_from("<I", binary, command + 64)[0]):
                        offset = command + 72 + section * 80
                        name = binary[offset:offset+16].rstrip(b"\0")
                        if name == b"__entitlements":
                            length = struct.unpack_from("<Q", binary, offset + 40)[0]
                            start = struct.unpack_from("<I", binary, offset + 48)[0]
                            values = plistlib.loads(binary[start:start+length].rstrip(b"\0"))
                command += size
        entitlements.append(values["com.apple.security.application-groups"])
    assert entitlements[0] == entitlements[1] == ["group.com.allenpeng.jianfan.zhuyin"]
print("Built app and keyboard: offline access, matching dictionaries and privacy manifest verified.")
print("Signed build app group verified." if args.signed else "Unsigned archive: signing entitlements require a signed build.")
