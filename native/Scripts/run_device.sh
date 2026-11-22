#!/bin/bash
# Install the signed app and companion in place, retaining their data.
set -euo pipefail
: "${WASHMYCAR_TEAM_ID:?Set WASHMYCAR_TEAM_ID to your Apple Development Team ID}"
: "${WASHMYCAR_DEVICE_ID:?Set WASHMYCAR_DEVICE_ID to your connected device ID}"
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_build="${WASHMYCAR_BUILD_DIR:-$task_root/DerivedData-DevicePreview}"
xcodebuild -project "$task_root/WashMyCar.xcodeproj" -scheme WashMyCar \
  -configuration Debug -destination "id=$WASHMYCAR_DEVICE_ID" \
  -derivedDataPath "$task_build" DEVELOPMENT_TEAM="$WASHMYCAR_TEAM_ID" \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
task_verify_args=("$task_build/Build/Products/Debug-iphoneos/WashMyCar.app")
if [[ -n "${WASHMYCAR_PAIRED_WATCH_ID:-}" ]]; then
  task_verify_args+=(--watch-id "$WASHMYCAR_PAIRED_WATCH_ID")
fi
python3 "$task_root/Scripts/verify_companion.py" "${task_verify_args[@]}"
xcrun devicectl device install app --device "$WASHMYCAR_DEVICE_ID" \
  "$task_build/Build/Products/Debug-iphoneos/WashMyCar.app"
xcrun devicectl device process launch --device "$WASHMYCAR_DEVICE_ID" com.yimtinyan.WashMyCar
