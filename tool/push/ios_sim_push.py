#!/usr/bin/env python3
"""Deliver a push to the iOS Simulator directly, without Firebase or APNs.

Builds the APNs payload FCM would deliver (including `gcm.message_id`, so the
app treats it as an FCM message) and hands it to `xcrun simctl push`. Useful
before an APNs key is uploaded to Firebase.

Only notification pushes work this way: the simulator does not pass injected
silent (data-only / content-available) pushes to the app. Test those with
send_push.py once the APNs key is set up.

Examples:
  python3 tool/push/ios_sim_push.py
  python3 tool/push/ios_sim_push.py --title "Order shipped" --data route=/orders/42
  python3 tool/push/ios_sim_push.py --data screen=chat id=9 --sound default
  python3 tool/push/ios_sim_push.py --device "iPhone 17"
"""
import argparse
import json
import subprocess
import sys
import tempfile
import time


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--device", default="booted", help="simulator name or UDID (default: booted)")
    p.add_argument("--bundle", default="com.example.tfpn")
    p.add_argument("--title", default="Test push")
    p.add_argument("--body", default=None)
    p.add_argument("--data", nargs="*", default=[], metavar="KEY=VALUE",
                   help="extra data, e.g. route=/orders/42, or screen=chat id=9 to open a screen on tap")
    p.add_argument("--sound", choices=["chime", "default"], default="chime",
                   help="chime = the app's custom sound (default); default = the system sound")
    args = p.parse_args()

    payload = {
        "aps": {
            "alert": {"title": args.title, "body": args.body or f"sent at {time.strftime('%H:%M:%S')}"},
            "sound": "chime.wav" if args.sound == "chime" else "default",
            "mutable-content": 1,
        },
        "gcm.message_id": str(int(time.time() * 1000)),
    }
    for pair in args.data:
        key, sep, value = pair.partition("=")
        if not sep:
            sys.exit(f"--data expects KEY=VALUE, got '{pair}'")
        payload[key] = value

    print(json.dumps(payload, indent=2))
    with tempfile.NamedTemporaryFile("w", suffix=".apns") as f:
        json.dump(payload, f)
        f.flush()
        result = subprocess.run(["xcrun", "simctl", "push", args.device, args.bundle, f.name],
                                capture_output=True, text=True)
    print(result.stdout.strip() or result.stderr.strip())
    sys.exit(result.returncode)


if __name__ == "__main__":
    main()
