import 'package:flutter/material.dart';

import '../notifications/push_notification_service.dart';
import 'opened_from_push_card.dart';

/// Demo target for pushes with `route=/orders/<id>` or `screen=order, id=<id>`.
/// Replace the body with the real order UI, loading the order by [orderId].
class OrderScreen extends StatelessWidget {
  const OrderScreen({super.key, required this.orderId, this.push});

  final String orderId;
  final PushEvent? push;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Order #$orderId')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: const Icon(Icons.receipt_long),
            title: Text('Order #$orderId'),
            subtitle: const Text('Load the order with this id here.'),
          ),
          if (push != null) OpenedFromPushCard(event: push!),
        ],
      ),
    );
  }
}
