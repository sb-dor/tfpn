import 'package:flutter/material.dart';

import '../screens/chat_screen.dart';
import '../screens/order_screen.dart';
import 'push_notification_service.dart';

/// The screen a tapped push should open, or null when its route is missing or
/// unknown. Matches on [PushMessage.route], e.g. `/orders/42` -> [OrderScreen].
/// Add new screens here.
Route<void>? routeForPush(PushEvent event) {
  final path = event.message.route;
  if (path == null) return null;

  final segments = Uri.parse(path).pathSegments;
  if (segments.isEmpty) return null;
  final id = segments.length > 1 ? segments[1] : null;

  final Widget? screen = switch (segments.first) {
    'order' || 'orders' when id != null => OrderScreen(orderId: id, push: event),
    'chat' || 'chats' when id != null => ChatScreen(chatId: id, push: event),
    _ => null,
  };
  if (screen == null) return null;

  return MaterialPageRoute<void>(
    settings: RouteSettings(name: path),
    builder: (_) => screen,
  );
}
