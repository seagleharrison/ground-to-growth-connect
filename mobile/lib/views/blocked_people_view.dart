import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../widgets/ui.dart';

/// People you've blocked, with a way to undo it.
class BlockedPeopleView extends StatefulWidget {
  const BlockedPeopleView({super.key});

  @override
  State<BlockedPeopleView> createState() => _BlockedPeopleViewState();
}

class _BlockedPeopleViewState extends State<BlockedPeopleView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().chat.refreshBlocked();
    });
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<AppState>().chat;
    return LargeTitlePage(
      title: 'Blocked people',
      children: [
        if (chat.blocked.isEmpty)
          const AppCard(
            key: Key('no-blocked'),
            child: Text(
              "You haven't blocked anyone. If someone makes you uncomfortable, open your chat with them and tap the three dots.",
              style: TextStyle(color: Colors.white70, height: 1.4),
            ),
          ),
        for (final p in chat.blocked)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppCard(
              key: Key('blocked-${p.userId}'),
              child: Row(
                children: [
                  Expanded(child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                  OutlinedButton(style: compactOutlined, 
                    key: Key('unblock-${p.userId}'),
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final error = await chat.unblock(p.userId);
                      if (error != null) messenger.showSnackBar(SnackBar(content: Text(error)));
                    },
                    child: const Text('Unblock'),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        const Text(
          'Blocking stops messages in both directions, and they no longer see your requests. They are not told.',
          style: TextStyle(color: Colors.white54, fontSize: 12.5, height: 1.4),
        ),
      ],
    );
  }
}
