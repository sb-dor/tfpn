import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../firebase_options.dart';
import 'local_notifications.dart';
import 'push_message.dart';

/// How the app got hold of a push.
enum PushEventSource {
  /// Arrived while the app was open (foreground).
  received,

  /// User tapped it while the app was alive in the background (or open).
  opened,

  /// User tapped it while the app was fully closed, which launched the app.
  launched,
}

class PushEvent {
  PushEvent(this.message, this.source) : at = DateTime.now();

  final PushMessage message;
  final PushEventSource source;
  final DateTime at;
}

/// Runs in its own isolate when a push arrives while the app is in the
/// background or terminated. Has no access to app state or UI.
///
/// `notification` payloads are already shown by the OS, so only data-only
/// pushes need a local notification here.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final push = PushMessage.fromRemoteMessage(message);
  debugPrint('[push] background: $push');

  if (push.type == PushPayloadType.dataOnly) {
    await LocalNotifications.init();
    await LocalNotifications.show(push);
  }
}

class PushNotificationService {
  PushNotificationService._();

  static final instance = PushNotificationService._();

  /// Every device subscribes to this, handy for broadcast tests from a backend.
  static const broadcastTopic = 'all';

  final _messaging = FirebaseMessaging.instance;
  final _taps = StreamController<PushEvent>.broadcast();
  PushEvent? _launchEvent;

  final token = ValueNotifier<String?>(null);
  final permission = ValueNotifier<AuthorizationStatus?>(null);
  final events = ValueNotifier<List<PushEvent>>(const []);

  /// Fires when the user taps a notification while the app is running.
  Stream<PushEvent> get taps => _taps.stream;

  /// Call once from `main()` after `Firebase.initializeApp`.
  Future<void> init() async {
    await LocalNotifications.init(onTap: _onLocalNotificationTap);

    // iOS: let the OS banner `notification` payloads while the app is open.
    // Android ignores this, so foreground pushes are shown locally there.
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(
      (message) => _onTap(PushMessage.fromRemoteMessage(message), PushEventSource.opened),
    );
    // getToken/onTokenRefresh are deprecated in favour of register()/onRegistered,
    // but those return a Firebase Installation ID. Admin SDK backends
    // (Laravel, Go, ...) still send to this registration token.
    // ignore: deprecated_member_use
    _messaging.onTokenRefresh.listen(_onToken);

    // App was fully closed and launched by tapping a notification: either an
    // OS-drawn FCM one or a local one we showed for a data-only push.
    final initial = await _messaging.getInitialMessage();
    final launchPush =
        initial != null ? PushMessage.fromRemoteMessage(initial) : await LocalNotifications.launchMessage();
    if (launchPush != null) {
      debugPrint('[push] launched by tap: $launchPush');
      _launchEvent = _record(launchPush, PushEventSource.launched);
    }

    // Not awaited: the permission dialog must not block the first frame.
    unawaited(_requestPermissionAndToken());
  }

  /// Returns the tap that cold-started the app once, then null.
  PushEvent? consumeLaunchEvent() {
    final event = _launchEvent;
    _launchEvent = null;
    return event;
  }

  Future<void> _requestPermissionAndToken() async {
    final settings = await _messaging.requestPermission();
    permission.value = settings.authorizationStatus;
    debugPrint('[push] permission: ${settings.authorizationStatus.name}');

    if (defaultTargetPlatform == TargetPlatform.iOS && !await _waitForApnsToken()) {
      debugPrint('[push] no APNs token: check Push Notifications capability and the APNs key in Firebase');
      return;
    }

    try {
      // ignore: deprecated_member_use
      _onToken(await _messaging.getToken());
      await _messaging.subscribeToTopic(broadcastTopic);
    } catch (e) {
      debugPrint('[push] token error: $e');
    }
  }

  /// On iOS the FCM token only exists after APNs hands one to the app.
  Future<bool> _waitForApnsToken() async {
    for (var i = 0; i < 10; i++) {
      if (await _messaging.getAPNSToken() != null) return true;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return false;
  }

  void _onToken(String? value) {
    // getToken() and onTokenRefresh both report the first token on startup.
    if (value == null || value == token.value) return;
    token.value = value;
    debugPrint('[push] FCM token: $value');
    // TODO: send the token to your backend (Laravel/Go) so it can target this device.
  }

  void _onForegroundMessage(RemoteMessage message) {
    final push = PushMessage.fromRemoteMessage(message);
    debugPrint('[push] foreground: $push');
    _record(push, PushEventSource.received);

    final osShowsIt = defaultTargetPlatform == TargetPlatform.iOS && push.type == PushPayloadType.notification;
    if (!osShowsIt) LocalNotifications.show(push);
  }

  void _onLocalNotificationTap(NotificationResponse response) {
    final push = PushMessage.fromPayload(response.payload);
    if (push != null) _onTap(push, PushEventSource.opened);
  }

  void _onTap(PushMessage push, PushEventSource source) {
    debugPrint('[push] tapped (${source.name}): $push');
    _taps.add(_record(push, source));
  }

  PushEvent _record(PushMessage push, PushEventSource source) {
    final event = PushEvent(push, source);
    events.value = [event, ...events.value];
    return event;
  }
}
