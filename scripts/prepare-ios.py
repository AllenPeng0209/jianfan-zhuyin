#!/usr/bin/env python3
import pathlib
import shutil

root = pathlib.Path(__file__).resolve().parents[1]
destination = root / "platforms/ios/Dictionaries"
destination.mkdir(parents=True, exist_ok=True)
data = root / "Vendor/McBopomofo/Source/Data"
for name in ["data.txt", "associated-phrases-v2.txt"]:
    shutil.copyfile(data / name, destination / name)
dictionary = root / "Vendor/Dependencies/SwiftyOpenCC/Sources/OpenCC/Dictionary"
for name in ["TSPhrases", "TSCharacters", "STPhrases", "STCharacters"]:
    shutil.copyfile(dictionary / (name + ".ocd2"), destination / (name + ".ocd2"))
notices = [root / "LICENSE", root / "Vendor/McBopomofo/LICENSE.txt", root / "Vendor/Dependencies/SwiftyOpenCC/OpenCC/LICENSE",
           root / "Vendor/Dependencies/SwiftyOpenCC/OpenCC/deps/marisa-0.2.6/COPYING.md", *sorted((root / "licenses").glob("*"))]
(destination / "ThirdPartyNotices.txt").write_text("\n\n".join(path.read_text() for path in notices), encoding="utf-8")
