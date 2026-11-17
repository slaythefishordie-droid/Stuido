#!/usr/bin/env python3
"""Select an installed iPad on the required runtime; never download runtimes in CI."""
import json
import subprocess

data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "--json"]))
devices = data["devices"].get("com.apple.CoreSimulator.SimRuntime.iOS-26-2", [])
pads = sorted((d for d in devices if d["isAvailable"] and "iPad" in d["name"]), key=lambda d: d["name"])
if not pads:
    raise SystemExit("No iPad simulator with iOS 26.2 is installed on this runner; refusing a silent fallback.")
print(pads[0]["udid"])
