import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'push_message.dart';

/// Thin wrapper over flutter_local_notifications. Safe to use from the FCM
/// background isolate too (call [init] there first).
class LocalNotifications {
  LocalNotifications._();

  /// Custom notification sound, bundled as
  /// android/app/src/main/res/raw/chime.wav and ios/Runner/chime.wav.
  static const soundName = 'chime';

  /// Default channel: plays the chime. Must match
  /// `default_notification_channel_id` in AndroidManifest.xml so pushes drawn
  /// by Android itself use it too. Android 8+ fixes a channel's sound when it
  /// is first created, so a different sound needs a new channel id.
  static const chimeChannel = AndroidNotificationChannel(
    'chime_channel',
    'Notifications',
    description: 'Push notifications from the server.',
    importance: Importance.high,
    sound: RawResourceAndroidNotificationSound(soundName),
  );

  /// Same, with the phone's standard notification sound.
  static const systemSoundChannel = AndroidNotificationChannel(
    'high_importance_channel',
    'Notifications (system sound)',
    description: 'Push notifications that use the standard sound.',
    importance: Importance.high,
  );

  /// Small icon (android/app/src/main/res/drawable/ic_notification.xml) and
  /// accent colour; keep in sync with `notification_color` in colors.xml.
  static const _androidIcon = '@drawable/ic_notification';
  static const accentColor = Color(0xFF5E35B1);

  static final plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init({
    void Function(NotificationResponse response)? onTap,
  }) async {
    if (_initialized) return;

    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(_androidIcon),
        // Permission is requested through FirebaseMessaging instead.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: onTap,
    );

    final android = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(chimeChannel);
    await android?.createNotificationChannel(systemSoundChannel);

    _initialized = true;
  }

  /// Senders choose the system sound per message: data-only pushes with
  /// `sound: default`, notification pushes with
  /// `android.notification.channel_id: high_importance_channel` (Android
  /// ignores their `sound` field and plays the channel's). Everything else
  /// gets the chime.
  static bool _usesSystemSound(PushMessage message) => message.type == PushPayloadType.notification
      ? message.androidChannelId == systemSoundChannel.id
      : message.sound == 'default';

  static Future<void> show(PushMessage message) async {
    if (!message.hasContent) {
      debugPrint('[push] nothing to display for $message');
      return;
    }

    final systemSound = _usesSystemSound(message);
    final channel = systemSound ? systemSoundChannel : chimeChannel;

    await plugin.show(
      id: (message.id ?? DateTime.now().toIso8601String()).hashCode,
      title: message.title,
      body: message.body,
      payload: message.toPayload(),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: Importance.high,
          priority: Priority.high,
          sound: channel.sound,
          icon: _androidIcon,
          color: accentColor,
          styleInformation: BigTextStyleInformation(message.body ?? ''),
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          // null = the system sound; otherwise a file in the app bundle.
          sound: systemSound ? null : '$soundName.wav',
        ),
      ),
    );
  }

  /// The local notification that cold-started the app, if any.
  static Future<PushMessage?> launchMessage() async {
    final details = await plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return null;
    return PushMessage.fromPayload(details.notificationResponse?.payload);
  }
}
