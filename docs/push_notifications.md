# Push notifications

Code: `lib/notifications/`. The app logs the FCM token on startup (`[push] FCM token: ...`) and shows it on the home screen with a copy button. Every device also subscribes to the `all` topic.

## Who draws the notification

| Payload | Foreground | Background | Terminated |
|---|---|---|---|
| `notification` (+ optional `data`): Firebase console, or a backend that sends it | Android: app shows a local notification. iOS: OS banner | OS shows it | OS shows it |
| `data` only: typical backend | App shows a local notification | Background handler shows a local notification | Same as background (Android needs high priority; iOS needs `content-available`) |

Tapping any of them opens `PushDetailsPage` (see `_openDetails` in `lib/main.dart`). Swap that out for real routing using `message.route`, which is read from the `route` / `screen` / `deeplink` / `link` / `url` data keys.

For data-only messages the app reads the title from `title` / `notification_title` / `headline` / `subject` and the body from `body` / `message` / `notification_body` / `text` / `content`. A JSON string under `payload`, `data`, `notification`, `extra` or `custom` is unpacked first.

## Backend examples (FCM HTTP v1 `message` object)

Notification message: same behaviour as the console.

```json
{
  "token": "<device token>",
  "notification": { "title": "Order shipped", "body": "Your order #7 is on its way" },
  "data": { "route": "/orders/7" },
  "android": { "notification": { "channel_id": "high_importance_channel" } }
}
```

Data-only message: the app builds the notification itself.

```json
{
  "token": "<device token>",
  "data": { "title": "Order shipped", "body": "Your order #7 is on its way", "route": "/orders/7" },
  "android": { "priority": "high" },
  "apns": {
    "headers": { "apns-push-type": "background", "apns-priority": "5" },
    "payload": { "aps": { "content-available": 1 } }
  }
}
```

All `data` values must be strings.

iOS limits for data-only messages: iOS throttles silent pushes and does not deliver them at all after the user force-quits the app from the app switcher. If a message has to show up reliably on iOS, send a `notification` message.

## Test from the command line

Scripts live in `tool/push/` (Python 3 standard library only). Launch the app once first so it logs its token.

```bash
# 1. Get the device token the app logged
tool/push/get_token.sh android
tool/push/get_token.sh ios

# 2. Send through FCM (Android, or iOS once the APNs key is uploaded)
python3 tool/push/send_push.py --token "$(tool/push/get_token.sh android)"
python3 tool/push/send_push.py --token "$(tool/push/get_token.sh android)" --type data --data route=/chat/3
python3 tool/push/send_push.py --topic all --title "Hello everyone"
python3 tool/push/send_push.py --token <token> --dry-run   # FCM validates, nothing is delivered

# 3. iOS Simulator without Firebase/APNs (notification pushes only)
python3 tool/push/ios_sim_push.py --title "Order shipped" --data route=/orders/7
```

`send_push.py` signs in with your Firebase CLI login. Pass `--service-account path/to/key.json` to sign in the way a backend does instead. It prints the exact JSON it sends, which your backend can copy.

To test the fully-closed state: on Android, swipe the app away in Recents (do not use Force stop, which blocks pushes until the app is opened again). On iOS, swipe it away or run `xcrun simctl terminate booted com.example.tfpn`. Then send and tap the notification.

## One-time setup outside the code

- **iOS:** upload an APNs auth key (`.p8`) in Firebase console → Project settings → Cloud Messaging. In Xcode, pick a signing team for Runner. Push Notifications and Background Modes are already set through `Runner.entitlements` and `Info.plist`. Test on a real device or on an Apple-silicon simulator.
- **Android 13+:** the app asks for the notification permission on first launch.
- **Fresh clone:** the Firebase config files are gitignored, so run `flutterfire configure` first.
