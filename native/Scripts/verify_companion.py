#!/usr/bin/env python3
"""Check the embedded companion before installing an iPhone development build."""
import argparse
import pathlib
import plistlib
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("phone_app", type=pathlib.Path)
parser.add_argument("--watch-id", help="Physical Apple Watch UDID, not the iPhone ID")
args = parser.parse_args()
phone = args.phone_app
watches = list((phone / "Watch").glob("*.app"))
if len(watches) != 1:
    raise SystemExit("Expected one embedded Watch app; installation cancelled.")
watch = watches[0]
with (phone / "Info.plist").open("rb") as f:
    pi = plistlib.load(f)
with (watch / "Info.plist").open("rb") as f:
    wi = plistlib.load(f)
checks = [
    (wi.get("WKCompanionAppBundleIdentifier") == pi["CFBundleIdentifier"], "Watch companion bundle ID mismatch"),
    (wi["CFBundleIdentifier"].startswith(pi["CFBundleIdentifier"] + "."), "Watch bundle ID prefix mismatch"),
    (wi.get("CFBundleVersion") == pi.get("CFBundleVersion"), "Phone/Watch build numbers differ"),
    (wi.get("CFBundleShortVersionString") == pi.get("CFBundleShortVersionString"), "Phone/Watch versions differ"),
    (wi.get("WKApplication") is True, "Missing single-target Watch app flag"),
]
for ok, message in checks:
    if not ok:
        raise SystemExit(message + "; installation cancelled.")
profiles = []
for app in (phone, watch):
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    profiles.append(plistlib.loads(subprocess.check_output(["security", "cms", "-D", "-i", str(app / "embedded.mobileprovision")])))
if profiles[0]["TeamIdentifier"] != profiles[1]["TeamIdentifier"]:
    raise SystemExit("Phone/Watch signing teams differ; installation cancelled.")
if args.watch_id and args.watch_id not in profiles[1].get("ProvisionedDevices", []):
    raise SystemExit("Embedded Watch profile does not cover this Watch. Register/build for the Watch first; installation cancelled.")
print("Companion bundle IDs, versions and signatures verified." + (" Embedded profile covers the Watch." if args.watch_id else " Watch UDID coverage not checked; pass --watch-id to check it."))
