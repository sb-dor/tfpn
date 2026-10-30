# Push notifications

Code: `lib/notifications/`. The app logs the FCM token on startup (`[push] FCM token: ...`) and shows it on the home screen with a copy button. Every device also subscribes to the `all` topic.

## Who draws the notification

| Payload | Foreground | Background | Terminated |
|---|---|---|---|
| `notification` (+ optional `data`): Firebase console, or a backend that sends it | Android: app shows a local notification. iOS: OS banner | OS shows it | OS shows it |
| `data` only: typical backend | App shows a local notification | Background handler shows a local notification | Same as background (Android needs high priority; iOS needs `content-available`) |

Tapping any of them opens the screen named in the payload (see "Open a screen on tap" below), in every app state.

For data-only messages the app reads the title from `title` / `notification_title` / `headline` / `subject` and the body from `body` / `message` / `notification_body` / `text` / `content`. A JSON string under `payload`, `data`, `notification`, `extra` or `custom` is unpacked first.

## Open a screen on tap

Put the target screen in the message's `data`. Any one of these forms works:

| `data` | Opens |
|---|---|
| `"route": "/orders/42"` | `OrderScreen` for order 42 |
| `"screen": "order", "id": "42"` (or `"type"` instead of `"screen"`) | the same |
| `"deeplink": "myapp://orders/42"` or `"link": "https://example.com/orders/42"` | the same |
| `"route": "/chat/9"` or `"screen": "chat", "id": "9"` | `ChatScreen` for chat 9 |
| anything else, or nothing | `PushDetailsPage`, which shows the raw payload |

How it works:
- `PushMessage.route` (in `lib/notifications/push_message.dart`) turns the payload into a path such as `/orders/42`.
- `routeForPush` (in `lib/notifications/push_routes.dart`) maps that path to a screen.

The same code runs whether the tap happened with the app open, in the background, or fully closed.

To add a screen:
1. Create the screen widget in `lib/screens/`.
2. Add one line to the `switch` in `push_routes.dart`, for example: `'invoice' || 'invoices' when id != null => InvoiceScreen(invoiceId: id),`

`OrderScreen` and `ChatScreen` are placeholders. Replace their bodies with the real UI that loads the order or chat by its id.

## Notification sound

Notifications play a custom chime by default. The same file is in two places:
- Android: `android/app/src/main/res/raw/chime.wav`
- iOS: `ios/Runner/chime.wav` (added to the Runner target in Xcode)

A sender can ask for the phone's standard sound instead for a single message:

| Message type | Custom chime (default) | System sound |
|---|---|---|
| Notification, Android | `android.notification.channel_id: "chime_channel"` (or leave it out) | `android.notification.channel_id: "high_importance_channel"` |
| Notification, iOS | `apns.payload.aps.sound: "chime.wav"` | `apns.payload.aps.sound: "default"` |
| Data-only (both) | leave `sound` out | `data.sound: "default"` |

Why the sound is set this way on each platform:
- **Android 8+:** the sound belongs to a notification channel, and Android ignores a `sound` field on the message. The app creates two channels: `chime_channel` (the default, set in `AndroidManifest.xml`) and `high_importance_channel` (system sound). A channel's sound is locked once it exists on a device, so to change the sound later, give it a new channel id.
- **iOS:** a notification plays no sound at all unless the message includes `aps.sound`. The Firebase console's "Sound" option sends `"default"`; backends must set it themselves.

To use a different sound file:
1. Add the file to both places.
   - **Android:** `res/raw/`, with a lowercase name containing only letters, digits and `_`.
   - **iOS:** `ios/Runner/`, and add it to the Runner target in Xcode. Use `.wav`, `.caf` or `.aiff`, under 30 seconds.
2. Change `LocalNotifications.soundName`.
3. Give `chimeChannel` a new id. Use the new id in `AndroidManifest.xml` (`default_notification_channel_id`) and in `tool/push/send_push.py`.
4. Update `@raw/chime` in `android/app/src/main/res/raw/keep.xml`.

Android only creates the channels when the app first runs. A notification-type message that arrives before the app has ever been opened falls back to Android's generic channel, which plays the system sound.

## Backend examples (FCM HTTP v1 `message` object)

Notification message: same behaviour as the console, plus a screen to open and the custom sound.

```json
{
  "token": "<device token>",
  "notification": { "title": "Order shipped", "body": "Your order #42 is on its way" },
  "data": { "route": "/orders/42" },
  "android": { "notification": { "channel_id": "chime_channel" } },
  "apns": { "payload": { "aps": { "sound": "chime.wav" } } }
}
```

Data-only message: the app builds the notification itself.

```json
{
  "token": "<device token>",
  "data": { "title": "New message", "body": "Avaz: are you there?", "screen": "chat", "id": "9" },
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
python3 tool/push/send_push.py --token "$(tool/push/get_token.sh android)" --data route=/orders/42      # tap opens Order 42
python3 tool/push/send_push.py --token "$(tool/push/get_token.sh android)" --type data --data screen=chat id=9
python3 tool/push/send_push.py --token "$(tool/push/get_token.sh android)" --sound default             # system sound
python3 tool/push/send_push.py --topic all --title "Hello everyone"
python3 tool/push/send_push.py --token <token> --dry-run   # FCM validates, nothing is delivered

# 3. iOS Simulator without Firebase/APNs (notification pushes only)
python3 tool/push/ios_sim_push.py --title "Order shipped" --data route=/orders/42
python3 tool/push/ios_sim_push.py --data screen=chat id=9 --sound default
```

Both senders play the custom chime unless you pass `--sound default`.

`send_push.py` signs in with your Firebase CLI login. Pass `--service-account path/to/key.json` to sign in the way a backend does instead. It prints the exact JSON it sends, which your backend can copy.

To test the fully-closed state: on Android, swipe the app away in Recents (do not use Force stop, which blocks pushes until the app is opened again). On iOS, swipe it away or run `xcrun simctl terminate booted com.example.tfpn`. Then send and tap the notification.

## App and notification icons

### App icon (Android, iOS, macOS)

Source images are in `assets/icon/`, all 1024×1024 PNG. `flutter_launcher_icons.yaml` maps them to each platform.

| File | Used for | Rules |
|---|---|---|
| `app_icon.png` | iOS, macOS, Android before 8.0 | Full square, no transparency. iOS rounds the corners itself, so don't round them |
| `app_icon_background.png` | Android adaptive icon background | Full square. A plain colour or gradient works best |
| `app_icon_foreground.png` | Android adaptive icon foreground | Transparent background. The generator shrinks it by 16% on each side, so draw the artwork about 1.5× the size you want it to end up |
| `app_icon_monochrome.png` | Android 13+ themed icon | White shape on transparent. The system recolours it |
| `app_icon_ios_dark.png` | iOS 18+ dark icon | Transparent background. iOS adds the dark backdrop |
| `app_icon_ios_tinted.png` | iOS 18+ tinted icon | White shape on transparent |

To change the app icon:

1. Replace the PNGs, keeping the same names. At minimum replace `app_icon.png`; delete the other `adaptive_icon_*`/`image_path_ios_*` lines from the yaml if you don't have those layers.
2. Regenerate:
   ```bash
   dart run flutter_launcher_icons
   ```
3. The generator (v0.14.4) wrongly rewrites one unrelated Xcode setting. Put it back:
   ```bash
   sed -i '' 's/ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = AppIcon;/ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;/' ios/Runner.xcodeproj/project.pbxproj
   ```
4. Rebuild and reinstall the app.

### Android notification icon

Android shows its own small icon in the status bar and the notification shade, separate from the app icon. The system ignores every colour in it and draws it as a single-colour silhouette, so a full-colour app icon becomes a solid white blob.

- **File:** `android/app/src/main/res/drawable/ic_notification.xml` (a vector).
- **Used by:**
  - notifications Android draws itself (via `default_notification_icon` in `AndroidManifest.xml`)
  - notifications the app draws (via `LocalNotifications._androidIcon` in `lib/notifications/local_notifications.dart`)
- **Accent colour:** tints the icon circle and app name in the shade. It's set in two places that must match:
  - `notification_color` in `android/app/src/main/res/values/colors.xml`
  - `LocalNotifications.accentColor` in Dart

Rules for the icon:
- white (`#FFFFFFFF`) shapes on transparent, nothing else
- 24×24 dp, keeping roughly 1 dp of padding
- simple, bold shapes with no thin lines or text; it shows at about 24 px

To replace it:

1. Get a white-on-transparent SVG of your glyph.
2. In Android Studio: right-click `res` → **New → Vector Asset** → Local file → pick the SVG.
3. Name it `ic_notification` so you overwrite the current file. Nothing else needs to change.
4. Alternatively, use **New → Image Asset → Notification Icons**, which generates PNGs into `drawable-*dpi/`. Delete `drawable/ic_notification.xml` so the two don't clash.
5. Uninstall the app and reinstall it. The launcher and notification shade cache icons.

A backend can also choose the icon and colour for a single message, as long as that icon file is bundled in the app's `res/drawable/`:

```json
"android": { "notification": { "icon": "ic_notification", "color": "#5E35B1" } }
```

### iOS notification icon

iOS has no separate notification icon: banners, the lock screen and Notification Center always show the app icon (its 20 pt size). To change it, change the app icon as described above.

- **Old icon still showing after an icon change:** iOS caches icons. On a device, delete the app and reinstall it. On the simulator, reinstalling isn't enough; reboot it:
  ```bash
  xcrun simctl shutdown booted && xcrun simctl boot <device-udid>
  ```
- **A different picture per message** (for example a sender's photo): this isn't possible with plain notification settings. It needs either a Notification Service Extension (for an image attached to the notification) or Communication Notifications (for a sender avatar). Both are separate iOS app targets.

## One-time setup outside the code

- **iOS:** upload an APNs auth key (`.p8`) in Firebase console → Project settings → Cloud Messaging. In Xcode, pick a signing team for Runner. Push Notifications and Background Modes are already set through `Runner.entitlements` and `Info.plist`. Test on a real device or on an Apple-silicon simulator.
- **Android 13+:** the app asks for the notification permission on first launch.
- **Fresh clone:** the Firebase config files are gitignored, so run `flutterfire configure` first.
