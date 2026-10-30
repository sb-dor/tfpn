import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'push_message.dart';

/// Thin wrapper over flutter_local_notifications. Safe to use from the FCM
/// background isolate too (call [init] there first).
class LocalNotifications {
  LocalNotifications._();

  /// Must match `default_notification_channel_id` in AndroidManifest.xml so
  /// console/backend notifications land in the same high-importance channel.
  static const channel = AndroidNotificationChannel(
    'high_importance_channel',
    'Important notifications',
    description: 'Push notifications from the server.',
    importance: Importance.high,
  );

  static const _androidIcon = '@drawable/ic_notification';

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

    await plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _initialized = true;
  }

  static Future<void> show(PushMessage message) async {
    if (!message.hasContent) {
      debugPrint('[push] nothing to display for $message');
      return;
    }

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
          icon: _androidIcon,
          styleInformation: BigTextStyleInformation(message.body ?? ''),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
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
