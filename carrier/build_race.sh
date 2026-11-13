#!/bin/bash
# Build the AGXProbe carrier.
# Usage: DEV=<device-udid> ./build_race.sh
cd ~/agx-probe-project || exit 1
if [ -z "$DEV" ]; then
  echo "set DEV=<device-udid> before running (see README.md)" >&2
  exit 1
fi
# Unlock the login keychain only if a password is supplied, so no credential lives in this file.
if [ -n "$KEYCHAIN_PW" ]; then
  security unlock-keychain -p "$KEYCHAIN_PW" "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PW" "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1
fi
xcodebuild -project AGXProbe.xcodeproj -scheme AGXProbe -configuration Debug \
  -destination "id=$DEV" -derivedDataPath .build13 -allowProvisioningUpdates build > /tmp/br99.log 2>&1
echo BUILD_EXIT=$?
grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" /tmp/br99.log | head -40
