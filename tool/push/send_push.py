#!/usr/bin/env python3
"""Send a test push through FCM (HTTP v1), the same API Laravel/Go backends use.

Works for Android and iOS devices (iOS needs the APNs key uploaded in Firebase).

Auth, pick one:
  * default: your Firebase CLI login (`firebase login`)
  * --service-account key.json (or GOOGLE_APPLICATION_CREDENTIALS): exactly what
    a backend does with the Admin SDK key. Needs `openssl` on PATH.

Examples:
  python3 tool/push/send_push.py --token <FCM token>
  python3 tool/push/send_push.py --token <FCM token> --data route=/orders/42
  python3 tool/push/send_push.py --token <FCM token> --type data --data screen=chat id=9
  python3 tool/push/send_push.py --token <FCM token> --sound default
  python3 tool/push/send_push.py --topic all --title "Hello everyone"
  python3 tool/push/send_push.py --token <FCM token> --dry-run
"""
import argparse
import base64
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
# Android channels and sound file, see lib/notifications/local_notifications.dart
CHANNELS = {"chime": "chime_channel", "default": "high_importance_channel"}
APNS_SOUNDS = {"chime": "chime.wav", "default": "default"}


def main():
    args = parse_args()
    if args.token is not None and not args.token.strip():
        sys.exit("--token is empty. Copy it from the app screen, or relaunch the app and run get_token.sh again.")
    sa = load_service_account(args.service_account)
    project = args.project or (sa or {}).get("project_id") or project_from_firebase_json()
    if not project:
        sys.exit("Could not find the Firebase project id. Pass --project <id>.")

    body = {"message": build_message(args)}
    if args.dry_run:
        body["validate_only"] = True

    print(f"project: {project}")
    print(json.dumps(body, indent=2))

    access_token = token_from_service_account(sa) if sa else token_from_firebase_cli()
    req = urllib.request.Request(
        f"https://fcm.googleapis.com/v1/projects/{project}/messages:send",
        data=json.dumps(body).encode(),
        headers={
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json",
            "x-goog-user-project": project,
        },
    )
    try:
        result = json.loads(urllib.request.urlopen(req).read())
        print(("validated (not sent): " if args.dry_run else "sent: ") + result["name"])
    except urllib.error.HTTPError as e:
        print(f"FCM error {e.code}: {e.read().decode()}", file=sys.stderr)
        sys.exit(1)


def parse_args():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    target = p.add_mutually_exclusive_group(required=True)
    target.add_argument("--token", help="device FCM token (shown in the app and in its logs)")
    target.add_argument("--topic", help="send to a topic instead, e.g. 'all'")
    p.add_argument("--type", choices=["notification", "data"], default="notification",
                   help="notification = like the Firebase console; data = data-only, like many backends")
    p.add_argument("--title", default="Test push")
    p.add_argument("--body", default=None)
    p.add_argument("--data", nargs="*", default=[], metavar="KEY=VALUE",
                   help="extra data, e.g. route=/orders/42, or screen=chat id=9 to open a screen on tap")
    p.add_argument("--sound", choices=["chime", "default"], default="chime",
                   help="chime = the app's custom sound (default); default = the phone's system sound")
    p.add_argument("--project", help="Firebase project id (default: from firebase.json or the key)")
    p.add_argument("--service-account", default=os.environ.get("GOOGLE_APPLICATION_CREDENTIALS"),
                   help="Firebase Admin service-account JSON")
    p.add_argument("--dry-run", action="store_true", help="validate with FCM without delivering")
    return p.parse_args()


def build_message(args):
    body = args.body or f"{args.type} payload sent at {time.strftime('%H:%M:%S')}"
    data = {}
    for pair in args.data:
        key, sep, value = pair.partition("=")
        if not sep:
            sys.exit(f"--data expects KEY=VALUE, got '{pair}'")
        data[key] = value  # FCM data values must be strings

    message = {"token": args.token} if args.token else {"topic": args.topic}
    if args.type == "notification":
        message["notification"] = {"title": args.title, "body": body}
        # Android 8+ plays the channel's sound; iOS plays aps.sound (no sound if omitted).
        message["android"] = {"notification": {"channel_id": CHANNELS[args.sound]}}
        message["apns"] = {"payload": {"aps": {"sound": APNS_SOUNDS[args.sound]}}}
    else:
        # Title/body/sound travel inside data; the app builds the notification itself.
        data = {"title": args.title, "body": body, "sound": args.sound, **data}
        message["android"] = {"priority": "high"}
        message["apns"] = {
            "headers": {"apns-push-type": "background", "apns-priority": "5"},
            "payload": {"aps": {"content-available": 1}},
        }
    if data:
        message["data"] = data
    return message


def project_from_firebase_json():
    try:
        with open(os.path.join(ROOT, "firebase.json")) as f:
            platforms = json.load(f)["flutter"]["platforms"]
        return next(iter(platforms["android"].values()))["projectId"]
    except (OSError, KeyError, StopIteration, ValueError):
        return None


def load_service_account(path):
    if not path:
        return None
    with open(path) as f:
        return json.load(f)


def token_from_firebase_cli():
    store = os.path.expanduser("~/.config/configstore/firebase-tools.json")
    tokens = read_cli_tokens(store)
    if not tokens or tokens.get("expires_at", 0) / 1000 - time.time() < 120:
        # Any authenticated CLI command refreshes the stored access token.
        subprocess.run(["firebase", "projects:list"], capture_output=True)
        tokens = read_cli_tokens(store)
    if not tokens or "access_token" not in tokens:
        sys.exit("No Firebase CLI login found. Run `firebase login` or pass --service-account.")
    return tokens["access_token"]


def read_cli_tokens(path):
    try:
        with open(path) as f:
            return json.load(f).get("tokens")
    except (OSError, ValueError):
        return None


def token_from_service_account(sa):
    now = int(time.time())
    header = {"alg": "RS256", "typ": "JWT"}
    claims = {
        "iss": sa["client_email"],
        "scope": "https://www.googleapis.com/auth/firebase.messaging",
        "aud": sa["token_uri"],
        "iat": now,
        "exp": now + 3600,
    }
    signing_input = f"{b64(json.dumps(header))}.{b64(json.dumps(claims))}"
    with tempfile.NamedTemporaryFile("w", suffix=".pem") as key:
        key.write(sa["private_key"])
        key.flush()
        signature = subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", key.name],
            input=signing_input.encode(), capture_output=True, check=True,
        ).stdout
    jwt = f"{signing_input}.{b64(signature)}"
    form = urllib.parse.urlencode({
        "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
        "assertion": jwt,
    }).encode()
    return json.loads(urllib.request.urlopen(sa["token_uri"], data=form).read())["access_token"]


def b64(value):
    raw = value.encode() if isinstance(value, str) else value
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


if __name__ == "__main__":
    main()
