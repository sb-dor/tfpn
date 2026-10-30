#!/usr/bin/env bash
# Print the FCM token the running app logged.
#   tool/push/get_token.sh android   # first adb device / emulator
#   tool/push/get_token.sh ios       # booted iOS simulator
# The app logs "[push] FCM token: ..." on every launch. If the log was cleared
# since then, relaunch the app (or copy the token from its home screen).
set -uo pipefail

case "${1:-}" in
  android)
    ADB="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"
    command -v adb >/dev/null && ADB=adb
    token=$("$ADB" logcat -d -s flutter | grep -o 'FCM token: .*' | tail -1 | sed 's/FCM token: //')
    ;;
  ios)
    token=$(xcrun simctl spawn booted log show --last 1h --style compact \
      --predicate 'process == "Runner" AND eventMessage CONTAINS "FCM token"' 2>/dev/null \
      | grep -o 'FCM token: .*' | tail -1 | sed 's/FCM token: //')
    ;;
  *)
    echo "usage: $0 android|ios" >&2
    exit 1
    ;;
esac

if [ -z "$token" ]; then
  echo "No FCM token in the $1 log. Relaunch the app, or copy the token from its home screen." >&2
  exit 1
fi
echo "$token"
