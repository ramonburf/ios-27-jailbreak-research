#!/bin/bash
# Build AGXProbe v99 (race harness) for the iPhone 13 Pro.
cd ~/agx-probe-project || exit 1
DEV=${DEV:-00008150-00095CD93444C01C}
security unlock-keychain -p 3854 "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k 3854 "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1
xcodebuild -project AGXProbe.xcodeproj -scheme AGXProbe -configuration Debug \
  -destination "id=$DEV" -derivedDataPath .build13 -allowProvisioningUpdates build > /tmp/br99.log 2>&1
echo BUILD_EXIT=$?
grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" /tmp/br99.log | head -40
