#!/usr/bin/env python3
import json
import subprocess

sdk = tuple(map(int, subprocess.check_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"], text=True).strip().split(".")))
devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"], text=True))["devices"]
choices = []
for runtime, values in devices.items():
    if "iOS-" not in runtime:
        continue
    version = tuple(map(int, runtime.split("iOS-")[-1].split("-")))
    if version > sdk:
        continue
    for device in values:
        if "iPhone" in device["name"] and "Duo" not in device["name"]:
            choices.append((version, "Pro Max" in device["name"], device["udid"]))
assert choices, "Install a compatible iPhone simulator runtime in Xcode"
print(max(choices)[2])
