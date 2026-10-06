import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../util/help_icons.dart';
import '../util/time.dart';
import '../widgets/ui.dart';
import 'messages_view.dart';

/// Help tab for volunteers and admins: what people have asked for, so they
/// can see what's needed and step in. Taking one on tells the person someone
/// is helping, and opens the way to message them.
class HelpBoardView extends StatefulWidget {
  const HelpBoardView({super.key});

  @override
  State<HelpBoardView> createState() => _HelpBoardViewState();
}

class _HelpBoardViewState extends State<HelpBoardView> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().help.refreshBoard();
    });
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) context.read<AppState>().help.refreshBoard();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _run(Future<String?> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    final error = await action();
    if (error != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final help = app.help;
    final isAdmin = app.user?.isAdmin == true;

    return LargeTitlePage(
      title: 'Help',
      onRefresh: help.refreshBoard,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 14),
          child: Text(
            'What people have asked for. Tap "I can help" to take one on, and they\'ll see you\'re on it.',
            style: TextStyle(color: Colors.white60, height: 1.4),
          ),
        ),
        if (help.boardError != null && help.boardError!.contains('approve'))
          AppCard(
            key: const Key('awaiting-approval'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.hourglass_top_rounded, color: Brand.amber),
                    SizedBox(width: 10),
                    Text('Waiting for approval', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'To keep everyone safe, an admin approves each volunteer before they can see requests or message anyone. '
                  'Ground to Growth will be in touch.',
                  style: TextStyle(color: Colors.white70, height: 1.4),
                ),
                const SizedBox(height: 10),
                OutlinedButton(key: const Key('check-approval'), onPressed: help.refreshBoard, child: const Text('Check again')),
              ],
            ),
          )
        else if (help.boardError != null)
          Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(help.boardError!, style: const TextStyle(color: Brand.red))),
        if (help.board.isEmpty && !help.isLoadingBoard && help.boardError == null)
          const AppCard(
            key: Key('board-empty'),
            child: Text('Nothing needed right now. New requests show up here.', style: TextStyle(color: Colors.white70, height: 1.4)),
          ),
        for (final r in help.board)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _BoardCard(
              request: r,
              isAdmin: isAdmin,
              onClaim: () => _run(() => help.claim(r.id)),
              onRelease: () => _run(() => help.release(r.id)),
              onFinish: () => _run(() => help.finish(r.id)),
              onMessage: () => openChat(
                context,
                Conversation(userId: r.userId!, name: r.name ?? 'Message', role: 'participant'),
              ),
            ),
          ),
      ],
    );
  }
}

class _BoardCard extends StatelessWidget {
  final HelpRequest request;
  final bool isAdmin;
  final VoidCallback onClaim;
  final VoidCallback onRelease;
  final VoidCallback onFinish;
  final VoidCallback onMessage;

  const _BoardCard({
    required this.request,
    required this.isAdmin,
    required this.onClaim,
    required this.onRelease,
    required this.onFinish,
    required this.onMessage,
  });

  @override
  Widget build(BuildContext context) {
    final r = request;
    final appt = r.appointment;
    final mine = r.claimedByMe;
    return AppCard(
      key: Key('help-${r.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: Brand.orange.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
                child: Icon(r.category.icon, color: Brand.orange, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.category.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                    Text('${r.name ?? 'Someone'} · ${timeAgo(r.createdAtLocal)}', style: const TextStyle(color: Colors.white54, fontSize: 13)),
                  ],
                ),
              ),
              if (r.isClaimed)
                Pill(label: mine ? "You're on it" : '${r.helperName ?? 'A volunteer'} is helping', color: Brand.green),
            ],
          ),
          if ((r.note ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(r.note!, style: const TextStyle(height: 1.4, fontSize: 15)),
          ],
          if (appt != null) ...[
            const SizedBox(height: 10),
            Container(
              key: Key('help-appt-${r.id}'),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Brand.surfaceHigh, borderRadius: BorderRadius.circular(14)),
              child: Row(
                children: [
                  const Icon(Icons.event_rounded, size: 18, color: Brand.blue),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(appt.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(
                          '${fullDate(appt.startsAtLocal)} · ${clockTime(appt.startsAtLocal)}'
                          '${(appt.location ?? '').isEmpty ? '' : '\n${appt.location}'}',
                          style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              if (r.isOpen)
                FilledButton.icon(style: compactFilled, 
                  key: Key('claim-${r.id}'),
                  onPressed: onClaim,
                  icon: const Icon(Icons.volunteer_activism_rounded, size: 18),
                  label: const Text('I can help'),
                ),
              if (mine) ...[
                FilledButton.icon(style: compactFilled, 
                  key: Key('message-${r.id}'),
                  onPressed: onMessage,
                  icon: const Icon(Icons.chat_bubble_rounded, size: 18),
                  label: const Text('Message'),
                ),
                OutlinedButton(style: compactOutlined, key: Key('finish-${r.id}'), onPressed: onFinish, child: const Text('Done')),
                OutlinedButton(style: compactOutlined, key: Key('release-${r.id}'), onPressed: onRelease, child: const Text("Can't anymore")),
              ],
              if (!mine && isAdmin && r.isClaimed)
                OutlinedButton(style: compactOutlined, key: Key('free-${r.id}'), onPressed: onRelease, child: const Text('Free up')),
            ],
          ),
        ],
      ),
    );
  }
}
