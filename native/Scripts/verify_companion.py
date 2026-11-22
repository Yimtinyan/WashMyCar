#!/usr/bin/env python3
"""Check the embedded companion before installing an iPhone development build."""
import argparse
import fnmatch
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
widget = phone / "PlugIns" / "WashWidgets.appex"
with (widget / "Info.plist").open("rb") as f:
    widget_info = plistlib.load(f)
group = pi.get("WashWidgetAccessGroup")
if not group or group != widget_info.get("WashWidgetAccessGroup"):
    raise SystemExit("Phone and widget must use the same keychain access group.")
for target in (phone, widget):
    signed = plistlib.loads(subprocess.check_output(["codesign", "-d", "--entitlements", "-", "--xml", str(target)], stderr=subprocess.DEVNULL))
    allowed = plistlib.loads(subprocess.check_output(["security", "cms", "-D", "-i", str(target / "embedded.mobileprovision")]))["Entitlements"]
    if group not in signed.get("keychain-access-groups", []) or not any(fnmatch.fnmatchcase(group, pattern) for pattern in allowed.get("keychain-access-groups", [])):
        raise SystemExit("Widget summary sharing missing from signature or provisioning profile.")
    if target == phone and (not pi.get("NSHealthShareUsageDescription") or
                            not signed.get("com.apple.developer.healthkit") or not allowed.get("com.apple.developer.healthkit")):
        raise SystemExit("Phone build lacks HealthKit read configuration.")
print("Companion bundle IDs, versions and signatures verified." + (" Embedded profile covers the Watch." if args.watch_id else " Watch UDID coverage not checked; pass --watch-id to check it."))
