#!/bin/bash
# Secondary device probe — iPhone 13 Pro (iPhone14,2), iOS 27.0 dev beta 4
cd ~/agx-probe-project || exit 1
DEV=00008110-000E095936C1801E
BID=com.nianticlabs.pokemongo.4L9HF29JJU
APP=.build/Build/Products/Debug-iphoneos/AGXProbe.app
echo "=== kill resident AGXProbe on secondary device ==="
PID=$(xcrun devicectl device info processes --device "$DEV" --json-output - 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
for p in d.get('processes', []):
    if 'AGXProbe' in p.get('executablePath', ''):
        print(p.get('pid', ''))
" | head -1)
if [ -n "$PID" ]; then
    echo "killing PID $PID"
    xcrun devicectl device process terminate --device "$DEV" --pid "$PID" --kill 2>&1 | tail -2
    sleep 2
fi
echo "=== BUILD incremental (keychain unlock) ==="
security unlock-keychain -p '3854' "$HOME/Library/Keychains/login.keychain-db" || { echo UNLOCK_FAILED; exit 3; }
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k '3854' "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1
xcodebuild -project AGXProbe.xcodeproj -scheme AGXProbe -configuration Debug -destination 'id=00008110-000E095936C1801E' -derivedDataPath .build -allowProvisioningUpdates build > /tmp/build_sec.log 2>&1
echo "BUILD_RC=$?"
grep -nE 'error:' /tmp/build_sec.log | head -20
echo "=== install ==="
xcrun devicectl device install app --device "$DEV" "$APP" 2>&1 | tail -4
echo "=== launch --autorun ==="
xcrun devicectl device process launch --device "$DEV" --terminate-existing "$BID" --autorun 2>&1 | tail -4
echo "=== sleep 30 ==="
sleep 30
echo "=== copy log ==="
rm -f /tmp/reach_sec.log
xcrun devicectl device copy from --device "$DEV" --domain-type appDataContainer --domain-identifier "$BID" --source Documents/reach.log --destination /tmp/reach_sec.log 2>&1 | tail -4
echo "=== reach_sec.log ==="
if [ -f /tmp/reach_sec.log ]; then cat /tmp/reach_sec.log; else echo "NO LOG FILE"; fi
echo "=== SCRIPT END ==="
