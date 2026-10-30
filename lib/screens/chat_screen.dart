import 'package:flutter/material.dart';

import '../notifications/push_notification_service.dart';
import 'opened_from_push_card.dart';

/// Demo target for pushes with `route=/chat/<id>` or `screen=chat, id=<id>`.
/// Replace the body with the real chat UI, loading the chat by [chatId].
class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key, required this.chatId, this.push});

  final String chatId;
  final PushEvent? push;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Chat $chatId')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: const Icon(Icons.chat_bubble_outline),
            title: Text('Chat $chatId'),
            subtitle: const Text('Load the conversation with this id here.'),
          ),
          if (push != null) OpenedFromPushCard(event: push!),
        ],
      ),
    );
  }
}
