#!/usr/bin/env python3
import json
import pathlib

root = pathlib.Path(__file__).resolve().parents[1]
data = json.loads((root / "distribution/ios/app-store-metadata.json").read_text())
for locale, item in data["localizations"].items():
    assert len(item["name"]) <= 30, (locale, "name")
    assert len(item["subtitle"]) <= 30, (locale, "subtitle")
    assert len(item["keywords"].encode("utf-8")) <= 100, (locale, "keywords")
    assert len(item["description"]) <= 4000, (locale, "description")
assert data["requestsFullAccess"] is False
print("Store metadata lengths and offline declaration verified.")
