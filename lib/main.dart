import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'firebase_options.dart';
import 'notifications/push_notification_service.dart';
import 'notifications/push_routes.dart';
import 'notifications/push_topics.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Must be registered before runApp so pushes received while the app is in
  // the background or terminated are handled.
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  await PushNotificationService.instance.init();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Push test',
      theme: ThemeData(colorScheme: .fromSeed(seedColor: Colors.deepPurple)),
      home: const PushHomePage(),
    );
  }
}

class PushHomePage extends StatefulWidget {
  const PushHomePage({super.key});

  @override
  State<PushHomePage> createState() => _PushHomePageState();
}

class _PushHomePageState extends State<PushHomePage> {
  final _push = PushNotificationService.instance;
  late final StreamSubscription<PushEvent> _tapSub;

  @override
  void initState() {
    super.initState();
    _tapSub = _push.taps.listen(_openFromTap);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final launchEvent = _push.consumeLaunchEvent();
      if (launchEvent != null) _openFromTap(launchEvent);
    });
  }

  @override
  void dispose() {
    _tapSub.cancel();
    super.dispose();
  }

  /// A tapped notification opens the screen its payload points at (see
  /// push_routes.dart), or the raw details page when it points nowhere known.
  void _openFromTap(PushEvent event) {
    Navigator.of(context).push(routeForPush(event) ?? _detailsRoute(event));
  }

  void _openDetails(PushEvent event) {
    Navigator.of(context).push(_detailsRoute(event));
  }

  Route<void> _detailsRoute(PushEvent event) =>
      MaterialPageRoute<void>(builder: (_) => PushDetailsPage(event: event));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Push notifications'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ValueListenableBuilder(
            valueListenable: _push.permission,
            builder: (_, status, _) => Text('Permission: ${status?.name ?? 'requesting...'}'),
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder(
            valueListenable: _push.token,
            builder: (context, token, _) => Card(
              child: ListTile(
                title: const Text('FCM token'),
                subtitle: SelectableText(token ?? 'waiting...', maxLines: 3),
                trailing: IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: 'Copy token',
                  onPressed: token == null
                      ? null
                      : () {
                          Clipboard.setData(ClipboardData(text: token));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Token copied')),
                          );
                        },
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Topics', style: Theme.of(context).textTheme.titleMedium),
          TopicsCard(push: _push),
          const SizedBox(height: 12),
          Text('Received', style: Theme.of(context).textTheme.titleMedium),
          ValueListenableBuilder(
            valueListenable: _push.events,
            builder: (_, events, _) => events.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('Nothing yet. Send a test message from the Firebase console or your backend.'),
                  )
                : Column(
                    children: [
                      for (final event in events)
                        ListTile(
                          title: Text(event.message.title ?? '(no title)'),
                          subtitle: Text([
                            event.source.name,
                            event.message.type.name,
                            if (event.message.topic != null) 'topic ${event.message.topic}',
                          ].join(' · ')),
                          trailing: Text(TimeOfDay.fromDateTime(event.at).format(context)),
                          onTap: () => _openDetails(event),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Opt in and out of [PushTopics.available]. Disabled until the FCM token
/// exists, because a subscription belongs to the token.
class TopicsCard extends StatelessWidget {
  const TopicsCard({super.key, required this.push});

  final PushNotificationService push;

  Future<void> _toggle(BuildContext context, PushTopic topic, bool on) async {
    try {
      await push.topics.setSubscribed(topic.name, on);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not ${on ? 'subscribe to' : 'unsubscribe from'} ${topic.label}: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final topics = push.topics;
    return ValueListenableBuilder(
      valueListenable: push.token,
      builder: (context, token, _) => ListenableBuilder(
        listenable: Listenable.merge([topics.subscribed, topics.pending]),
        builder: (context, _) => Card(
          child: Column(
            children: [
              for (final topic in PushTopics.available)
                SwitchListTile(
                  title: Text(topic.label),
                  subtitle: Text(topic.description),
                  value: topics.subscribed.value.contains(topic.name),
                  onChanged: token == null || topics.pending.value.contains(topic.name)
                      ? null
                      : (on) => _toggle(context, topic, on),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class PushDetailsPage extends StatelessWidget {
  const PushDetailsPage({super.key, required this.event});

  final PushEvent event;

  @override
  Widget build(BuildContext context) {
    final message = event.message;
    return Scaffold(
      appBar: AppBar(title: Text(message.title ?? 'Notification')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(message.body ?? '(no body)', style: Theme.of(context).textTheme.bodyLarge),
          const Divider(height: 32),
          Text('Source: ${event.source.name}'),
          Text('Payload type: ${message.type.name}'),
          if (message.topic != null) Text('Topic: ${message.topic}'),
          if (message.route != null) Text('Route: ${message.route}'),
          const SizedBox(height: 12),
          SelectableText(const JsonEncoder.withIndent('  ').convert(message.data)),
        ],
      ),
    );
  }
}
