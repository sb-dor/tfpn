import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tfpn/notifications/push_message.dart';

void main() {
  test('console style message uses the notification block', () {
    final push = PushMessage.fromRemoteMessage(
      const RemoteMessage(
        messageId: '1',
        notification: RemoteNotification(title: 'Hello', body: 'From console'),
        data: {'route': '/orders/7'},
      ),
    );

    expect(push.type, PushPayloadType.notification);
    expect(push.title, 'Hello');
    expect(push.body, 'From console');
    expect(push.route, '/orders/7');
  });

  test('data-only backend message reads title/body from data', () {
    final push = PushMessage.fromRemoteMessage(
      const RemoteMessage(data: {'title': 'Order shipped', 'message': 'On its way', 'order_id': '7'}),
    );

    expect(push.type, PushPayloadType.dataOnly);
    expect(push.title, 'Order shipped');
    expect(push.body, 'On its way');
    expect(push.data['order_id'], '7');
  });

  test('nested JSON payload string is unwrapped', () {
    final push = PushMessage.fromRemoteMessage(
      const RemoteMessage(data: {'payload': '{"title":"Hi","body":"There","screen":"chat"}'}),
    );

    expect(push.title, 'Hi');
    expect(push.body, 'There');
    expect(push.route, '/chat');
    expect(push.data.containsKey('payload'), isFalse);
  });

  group('route', () {
    PushMessage withData(Map<String, dynamic> data) =>
        PushMessage.fromRemoteMessage(RemoteMessage(data: data));

    test('reads a route path as is', () {
      expect(withData({'route': '/orders/42'}).route, '/orders/42');
      expect(withData({'route': 'orders/42'}).route, '/orders/42');
    });

    test('reads app and web deep links', () {
      expect(withData({'deeplink': 'myapp://orders/42'}).route, '/orders/42');
      expect(withData({'link': 'https://example.com/chat/9?ref=push'}).route, '/chat/9');
    });

    test('builds the route from screen + id', () {
      expect(withData({'screen': 'order', 'id': '42'}).route, '/order/42');
      expect(withData({'type': 'chat', 'id': '9'}).route, '/chat/9');
      expect(withData({'screen': 'settings'}).route, '/settings');
    });

    test('is null without routing keys', () {
      expect(withData({'title': 'Hi'}).route, isNull);
    });
  });

  test('reads requested sound and Android channel', () {
    final data = PushMessage.fromRemoteMessage(const RemoteMessage(data: {'title': 'T', 'sound': 'default'}));
    expect(data.sound, 'default');

    final notification = PushMessage.fromRemoteMessage(
      const RemoteMessage(
        notification: RemoteNotification(
          title: 'T',
          android: AndroidNotification(channelId: 'high_importance_channel', sound: 'default'),
        ),
      ),
    );
    expect(notification.androidChannelId, 'high_importance_channel');
    expect(notification.sound, 'default');
  });

  test('round-trips through a local notification payload', () {
    const original = PushMessage(
      type: PushPayloadType.dataOnly,
      id: 'abc',
      title: 'T',
      body: 'B',
      topic: 'news',
      data: {'k': 'v'},
    );

    final restored = PushMessage.fromPayload(original.toPayload())!;

    expect(restored.type, original.type);
    expect(restored.id, 'abc');
    expect(restored.title, 'T');
    expect(restored.topic, 'news');
    expect(restored.data, {'k': 'v'});
  });

  test('topic messages know their topic, token messages do not', () {
    final fromTopic = PushMessage.fromRemoteMessage(const RemoteMessage(from: '/topics/news', data: {'title': 'Hi'}));
    final fromToken = PushMessage.fromRemoteMessage(const RemoteMessage(from: '1234567890', data: {'title': 'Hi'}));

    expect(fromTopic.topic, 'news');
    expect(fromToken.topic, isNull);
  });
}
