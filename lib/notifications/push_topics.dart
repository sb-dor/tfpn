import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A topic the user can opt into. A backend sends one message to the topic
/// (`"topic": "news"` instead of `"token"`) and FCM delivers it to every
/// device subscribed to it.
class PushTopic {
  const PushTopic(this.name, this.label, this.description);

  /// FCM topic name, matching `[a-zA-Z0-9-_.~%]+`.
  final String name;
  final String label;
  final String description;
}

typedef TopicCall = Future<void> Function(String topic);

/// Remembers which optional topics this device follows and keeps FCM in sync.
///
/// FCM stores subscriptions per token on its side, but the app can't ask FCM
/// for them, so the choices are saved locally and replayed by [restore].
class PushTopics {
  PushTopics({required this.subscribe, required this.unsubscribe});

  static const available = [
    PushTopic('news', 'News', 'Product updates and announcements'),
    PushTopic('offers', 'Offers', 'Discounts and promotions'),
  ];

  static const _prefsKey = 'push_topics';

  /// FCM calls, passed in so tests can fake them.
  final TopicCall subscribe;
  final TopicCall unsubscribe;

  /// Topics this device is subscribed to.
  final subscribed = ValueNotifier<Set<String>>(const {});

  /// Topics with a subscribe/unsubscribe call still in flight.
  final pending = ValueNotifier<Set<String>>(const {});

  /// Subscribe again to the saved topics. Call once the FCM token exists:
  /// it is idempotent, and covers a token that changed since last time.
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_prefsKey)?.toSet() ?? const <String>{};
    for (final topic in saved) {
      await subscribe(topic);
    }
    subscribed.value = saved;
  }

  /// Throws if FCM rejects the call; the saved state only changes on success.
  Future<void> setSubscribed(String topic, bool on) async {
    pending.value = {...pending.value, topic};
    try {
      await (on ? subscribe(topic) : unsubscribe(topic));
      final next = {...subscribed.value};
      on ? next.add(topic) : next.remove(topic);
      subscribed.value = next;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsKey, next.toList()..sort());
      debugPrint(
        '[push] ${on ? 'subscribed to' : 'unsubscribed from'} topic $topic',
      );
    } finally {
      pending.value = {...pending.value}..remove(topic);
    }
  }
}
