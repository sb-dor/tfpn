import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';

/// Shape of the FCM payload. This decides who has to draw the notification:
///
/// * [notification] - payload has a `notification` block. Firebase console
///   always sends this, and backends can too. While the app is in the
///   background/terminated the OS shows it by itself.
/// * [dataOnly] - payload has only `data`. Typical for backends (Laravel, Go,
///   ...) using the Admin SDK. The OS never shows these, so the app shows a
///   local notification in every state.
enum PushPayloadType { notification, dataOnly }

/// A platform-independent view of a push, built either from a [RemoteMessage]
/// or from the payload stored inside a local notification.
class PushMessage {
  const PushMessage({
    required this.type,
    this.id,
    this.title,
    this.body,
    this.imageUrl,
    this.data = const {},
  });

  final PushPayloadType type;
  final String? id;
  final String? title;
  final String? body;
  final String? imageUrl;

  /// Custom key/value pairs (console "Additional options" or backend `data`).
  final Map<String, dynamic> data;

  bool get hasContent => (title?.isNotEmpty ?? false) || (body?.isNotEmpty ?? false);

  /// Optional deep link / route the backend wants opened on tap.
  String? get route => _string(data, const ['route', 'screen', 'deeplink', 'link', 'url']);

  factory PushMessage.fromRemoteMessage(RemoteMessage message) {
    final data = _flattenData(message.data);
    final notification = message.notification;

    return PushMessage(
      type: notification == null ? PushPayloadType.dataOnly : PushPayloadType.notification,
      id: message.messageId,
      title: notification?.title ?? _string(data, const ['title', 'notification_title', 'headline', 'subject']),
      body: notification?.body ?? _string(data, const ['body', 'message', 'notification_body', 'text', 'content']),
      imageUrl: notification?.android?.imageUrl ??
          notification?.apple?.imageUrl ??
          _string(data, const ['image', 'image_url', 'imageUrl', 'picture']),
      data: data,
    );
  }

  /// Serialized into a local notification so taps can be routed later.
  String toPayload() => jsonEncode({
        'type': type.name,
        'id': id,
        'title': title,
        'body': body,
        'imageUrl': imageUrl,
        'data': data,
      });

  static PushMessage? fromPayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final json = jsonDecode(payload) as Map<String, dynamic>;
      return PushMessage(
        type: PushPayloadType.values.asNameMap()[json['type']] ?? PushPayloadType.dataOnly,
        id: json['id'] as String?,
        title: json['title'] as String?,
        body: json['body'] as String?,
        imageUrl: json['imageUrl'] as String?,
        data: Map<String, dynamic>.from(json['data'] as Map? ?? const {}),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() => 'PushMessage(type: ${type.name}, id: $id, title: $title, body: $body, data: $data)';
}

/// Keys some backends use to wrap the real content as a JSON string, e.g.
/// `{"data": {"payload": "{\"title\":\"Hi\",\"order_id\":7}"}}`.
const _nestedJsonKeys = ['payload', 'data', 'notification', 'extra', 'custom'];

/// FCM data values are always strings. Unwrap nested JSON strings so
/// `title`/`body` and custom fields are found wherever the backend put them.
Map<String, dynamic> _flattenData(Map<String, dynamic> raw) {
  final result = Map<String, dynamic>.from(raw);
  for (final key in _nestedJsonKeys) {
    final value = raw[key];
    if (value is! String || !value.trimLeft().startsWith('{')) continue;
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        result.remove(key);
        decoded.forEach((k, v) => result.putIfAbsent(k.toString(), () => v));
      }
    } catch (_) {
      // Not JSON, keep the original string value.
    }
  }
  return result;
}

String? _string(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value != null && value.toString().isNotEmpty) return value.toString();
  }
  return null;
}
