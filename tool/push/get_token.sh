#!/usr/bin/env bash
# Print the FCM token the running app logged.
#   tool/push/get_token.sh android   # first adb device / emulator
#   tool/push/get_token.sh ios       # booted iOS simulator
# The app must have been launched at least once (it logs "[push] FCM token: ...").
set -euo pipefail

case "${1:-}" in
  android)
    ADB="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"
    command -v adb >/dev/null && ADB=adb
    "$ADB" logcat -d -s flutter | grep -o 'FCM token: .*' | tail -1 | sed 's/FCM token: //'
    ;;
  ios)
    xcrun simctl spawn booted log show --last 1h --style compact \
      --predicate 'process == "Runner" AND eventMessage CONTAINS "FCM token"' 2>/dev/null \
      | grep -o 'FCM token: .*' | tail -1 | sed 's/FCM token: //'
    ;;
  *)
    echo "usage: $0 android|ios" >&2
    exit 1
    ;;
esac
