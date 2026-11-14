#!/usr/bin/env python3
"""Refuse to launch app-host tests with the daily input method's identity."""
import plistlib
import sys
from pathlib import Path

app = Path(sys.argv[1])
info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
identifier = info["CFBundleIdentifier"]
folder = info.get("JianfanDataFolderName", "")
connection = info["InputMethodConnectionName"]
if not identifier.startswith("com.local.inputmethod.JianfanZhuyin.Development"):
    raise SystemExit("Unsafe app-host identity; the installed input method must stay isolated")
if not folder.startswith("JianfanZhuyin-Tests-"):
    raise SystemExit("Unsafe app-host data directory; use a fresh test profile")
if connection != identifier + "_Connection":
    raise SystemExit("The test IMK connection is not isolated")
print("Verified isolated test application, IMK connection and data directory")
