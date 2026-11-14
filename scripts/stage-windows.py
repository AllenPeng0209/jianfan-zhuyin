#!/usr/bin/env python3
"""Stage only release binaries, bundled dictionaries and redistribution notices."""
import argparse
import hashlib
import pathlib
import shutil
import struct

parser = argparse.ArgumentParser()
parser.add_argument("--build", type=pathlib.Path, required=True)
parser.add_argument("--arch", choices=["x64", "x86"], required=True)
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[1]
destination = root / "dist/windows-stage"
binary = args.build / "platforms/windows/Release"
target = destination / args.arch
target.mkdir(parents=True, exist_ok=True)
expected = {"x64": 0x8664, "x86": 0x14C}[args.arch]
for name in ["JianfanIME.dll", "JianfanSettings.exe"]:
    source = binary / name
    data = source.read_bytes()
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    assert data[pe:pe+4] == b"PE\0\0", f"Invalid PE binary: {name}"
    assert struct.unpack_from("<H", data, pe+4)[0] == expected, f"Wrong architecture: {name}"
    shutil.copyfile(source, target / name)
data_folder = destination / "Data"
data_folder.mkdir(exist_ok=True)
for name in ["data.txt", "associated-phrases-v2.txt"]:
    source = root / "Vendor/McBopomofo/Source/Data" / name
    assert b"\r\n" not in source.read_bytes(), "Dictionary must use LF"
    shutil.copyfile(source, data_folder / name)
for name in ["TSCharacters", "TSPhrases", "STCharacters", "STPhrases"]:
    source = root / "Vendor/Dependencies/SwiftyOpenCC/Sources/OpenCC/Dictionary" / (name + ".ocd2")
    shutil.copyfile(source, data_folder / source.name)
notices = [root / "LICENSE", root / "Vendor/McBopomofo/LICENSE.txt",
           root / "Vendor/Dependencies/SwiftyOpenCC/LICENSE", root / "Vendor/Dependencies/SwiftyOpenCC/OpenCC/LICENSE",
           root / "Vendor/Dependencies/SwiftyOpenCC/OpenCC/deps/marisa-0.2.6/COPYING.md", root / "Vendor/nlohmann/LICENSE.MIT",
           *sorted((root / "licenses").glob("*"))]
(destination / "ThirdPartyNotices.txt").write_text("\n\n".join(p.read_text(encoding="utf-8") for p in notices), encoding="utf-8")
shutil.copyfile(root / "docs/WINDOWS.md", destination / "README-Windows.txt")
files = sorted(p for p in destination.rglob("*") if p.is_file() and p.name != "SHA256SUMS.txt")
(destination / "SHA256SUMS.txt").write_text("".join(f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(destination).as_posix()}\n" for p in files), encoding="utf-8")
