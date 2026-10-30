import 'package:flutter/material.dart';

import '../notifications/push_notification_service.dart';

/// Shows which notification opened a screen. Handy while testing.
class OpenedFromPushCard extends StatelessWidget {
  const OpenedFromPushCard({super.key, required this.event});

  final PushEvent event;

  @override
  Widget build(BuildContext context) {
    final message = event.message;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.notifications_active_outlined),
        title: Text('Opened from: ${message.title ?? '(no title)'}'),
        subtitle: Text('App state: ${event.source.name} · route: ${message.route}'),
      ),
    );
  }
}
