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
    expect(push.route, 'chat');
    expect(push.data.containsKey('payload'), isFalse);
  });

  test('round-trips through a local notification payload', () {
    const original = PushMessage(
      type: PushPayloadType.dataOnly,
      id: 'abc',
      title: 'T',
      body: 'B',
      data: {'k': 'v'},
    );

    final restored = PushMessage.fromPayload(original.toPayload())!;

    expect(restored.type, original.type);
    expect(restored.id, 'abc');
    expect(restored.title, 'T');
    expect(restored.data, {'k': 'v'});
  });
}
