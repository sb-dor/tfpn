import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tfpn/notifications/push_topics.dart';

void main() {
  late List<String> calls;
  late PushTopics topics;

  setUp(() {
    calls = [];
    topics = PushTopics(
      subscribe: (topic) async => calls.add('+$topic'),
      unsubscribe: (topic) async => calls.add('-$topic'),
    );
  });

  test(
    'subscribing and unsubscribing calls FCM and saves the choice',
    () async {
      SharedPreferences.setMockInitialValues({});

      await topics.setSubscribed('news', true);
      await topics.setSubscribed('offers', true);
      await topics.setSubscribed('news', false);

      expect(calls, ['+news', '+offers', '-news']);
      expect(topics.subscribed.value, {'offers'});
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('push_topics'), ['offers']);
    },
  );

  test('restore subscribes again to the saved topics', () async {
    SharedPreferences.setMockInitialValues({
      'push_topics': ['news', 'offers'],
    });

    await topics.restore();

    expect(calls, ['+news', '+offers']);
    expect(topics.subscribed.value, {'news', 'offers'});
  });

  test('a failed call changes nothing and clears pending', () async {
    SharedPreferences.setMockInitialValues({});
    final failing = PushTopics(
      subscribe: (_) async => throw Exception('apns-token-not-set'),
      unsubscribe: (_) async {},
    );

    await expectLater(failing.setSubscribed('news', true), throwsException);

    expect(failing.subscribed.value, isEmpty);
    expect(failing.pending.value, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('push_topics'), isNull);
  });
}
