#!/bin/bash
# Install directly to a Watch discovered and paired with Xcode. Keeps existing app data.
set -euo pipefail
: "${WASHMYCAR_TEAM_ID:?Set WASHMYCAR_TEAM_ID to your Apple Development Team ID}"
: "${WASHMYCAR_WATCH_ID:?Set WASHMYCAR_WATCH_ID to the Watch destination ID shown by Xcode}"
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_build="${WASHMYCAR_BUILD_DIR:-$task_root/DerivedData-WatchDevice}"
xcodebuild -project "$task_root/WashMyCar.xcodeproj" -scheme WashMyCarWatch \
  -configuration Debug -destination "id=$WASHMYCAR_WATCH_ID" \
  -derivedDataPath "$task_build" DEVELOPMENT_TEAM="$WASHMYCAR_TEAM_ID" \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
xcrun devicectl device install app --device "$WASHMYCAR_WATCH_ID" \
  "$task_build/Build/Products/Debug-watchos/WashMyCarWatch.app"
xcrun devicectl device process launch --device "$WASHMYCAR_WATCH_ID" \
  com.yimtinyan.WashMyCar.watchkitapp
