#!/usr/bin/env python3
import json
import subprocess

def version(text):
    values = tuple(map(int, text.split(".")))
    return values + (0,) * (3 - len(values))

sdk = version(subprocess.check_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"], text=True).strip())
devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"], text=True))["devices"]
runtimes = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "runtimes", "-j"], text=True))["runtimes"]
versions = {item["identifier"]: version(item["version"]) for item in runtimes if item.get("isAvailable") and item["name"].startswith("iOS")}
choices = []
for runtime, values in devices.items():
    if runtime not in versions:
        continue
    runtime_version = versions[runtime]
    if runtime_version > sdk:
        continue
    for device in values:
        if "iPhone" in device["name"] and "Duo" not in device["name"]:
            choices.append((runtime_version, "Pro Max" in device["name"], device["udid"]))
assert choices, "Install a compatible iPhone simulator runtime in Xcode"
print(max(choices)[2])
