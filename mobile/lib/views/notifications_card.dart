import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../services/push_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

/// Offers to turn notifications on, at a moment that's visible rather than the
/// instant the app opens. Disappears once answered, or for a week after "Not now".
class NotificationsCard extends StatelessWidget {
  final String reason;
  const NotificationsCard({super.key, required this.reason});

  @override
  Widget build(BuildContext context) {
    final push = context.watch<AppState>().push;
    if (!push.shouldOffer) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AppCard(
        key: const Key('notifications-card'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.notifications_active_rounded, color: Brand.orange),
                SizedBox(width: 10),
                Expanded(child: Text('Get notified', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '$reason Notifications never show your messages or anyone\'s name — only that something needs you.',
              style: const TextStyle(color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton(style: compactFilled, key: const Key('enable-notifications'), onPressed: push.enable, child: const Text('Turn on')),
                TextButton(key: const Key('notifications-not-now'), onPressed: push.dismissPrompt, child: const Text('Not now')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A row in Me showing whether notifications are on, and how to change it.
class NotificationsRow extends StatelessWidget {
  const NotificationsRow({super.key});

  @override
  Widget build(BuildContext context) {
    final push = context.watch<AppState>().push;
    if (push.status == PushStatus.unknown || push.status == PushStatus.unavailable) return const SizedBox.shrink();
    final (subtitle, action, onTap) = switch (push.status) {
      PushStatus.enabled => ('On', null, null),
      PushStatus.denied => ('Off. Turn them on in your phone\'s Settings.', 'Open Settings', push.openSettings),
      _ => ('Off', 'Turn on', push.enable),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: AppCard(
        key: const Key('notifications-row'),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            const Icon(Icons.notifications_rounded, color: Brand.orange),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Notifications', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle, key: const Key('notifications-status'), style: const TextStyle(color: Colors.white54, fontSize: 13)),
                ],
              ),
            ),
            if (action != null)
              TextButton(key: const Key('notifications-action'), onPressed: onTap, child: Text(action)),
          ],
        ),
      ),
    );
  }
}
