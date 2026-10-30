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

## One-time setup outside the code

- **iOS:** upload an APNs auth key (`.p8`) in Firebase console → Project settings → Cloud Messaging. In Xcode, pick a signing team for Runner. Push Notifications and Background Modes are already set through `Runner.entitlements` and `Info.plist`. Test on a real device or on an Apple-silicon simulator.
- **Android 13+:** the app asks for the notification permission on first launch.
- **Fresh clone:** the Firebase config files are gitignored, so run `flutterfire configure` first.
