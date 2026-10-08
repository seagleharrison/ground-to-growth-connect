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
import 'notifications_card.dart';
import 'unsafe_dialog.dart';

/// Help tab for volunteers and admins: what people have asked for, so they
/// can see what's needed and step in. Taking one on tells the person someone
/// is helping, and opens the way to message the team about it.
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
    final team = app.chat.conversations.where((c) => c.role == 'team').firstOrNull;

    return LargeTitlePage(
      title: 'Help',
      onRefresh: help.refreshBoard,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 14),
          child: Text(
            isAdmin
                ? 'What people have asked for. When volunteers offer to help, confirm the match here, and the person is told someone is coming.'
                : 'What people have asked for. Tap "I can help" to offer. An admin confirms each match, then your steps (on my way, arrived, done) show up here.',
            style: const TextStyle(color: Colors.white60, height: 1.4),
          ),
        ),
        const NotificationsCard(reason: 'Hear about new requests and messages even when the app is closed.'),
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
              onApprove: (o) => _run(() => help.approveOffer(o.id)),
              onDecline: (o) => _run(() => help.declineOffer(o.id)),
              onWithdraw: () => _run(() => help.withdrawOffer(r.id, r.myOfferId ?? '')),
              onProgress: (kind, {minutes}) => _run(() => help.progress(r.id, kind, minutes: minutes)),
              onUnsafe: () async {
                final confirmed = await showUnsafeDialog(context, byVolunteer: true);
                if (confirmed == true) await _run(() => help.progress(r.id, 'unsafe'));
              },
              // Chat only runs through admins: an admin writes to the person,
              // a volunteer writes to the team.
              onMessage: () {
                if (isAdmin) {
                  openChat(context, Conversation(userId: r.userId!, name: r.name ?? 'Message', role: 'participant'));
                } else if (team != null) {
                  openChat(context, team);
                }
              },
              canMessage: isAdmin ? r.userId != null : (r.claimedByMe && team != null),
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
  final bool canMessage;
  final ValueChanged<HelpOffer> onApprove;
  final ValueChanged<HelpOffer> onDecline;
  final VoidCallback onWithdraw;
  final void Function(String kind, {int? minutes}) onProgress;
  final VoidCallback onUnsafe;

  const _BoardCard({
    required this.request,
    required this.isAdmin,
    required this.onClaim,
    required this.onRelease,
    required this.onFinish,
    required this.onMessage,
    required this.canMessage,
    required this.onApprove,
    required this.onDecline,
    required this.onWithdraw,
    required this.onProgress,
    required this.onUnsafe,
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
                Pill(label: mine ? _myStatus(r) : '${r.helperName ?? 'A volunteer'} is helping', color: Brand.green),
              if (r.isOpen && r.hasMyOffer) const Pill(key: Key('offer-waiting'), label: 'Waiting for the team', color: Brand.amber),
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
          if (r.isOpen && isAdmin && r.offers.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Volunteers offering to help', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white70)),
            ),
            for (final o in r.offers)
              Container(
                key: Key('offer-${o.id}'),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Brand.surfaceHigh, borderRadius: BorderRadius.circular(14)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(o.volunteerName, style: const TextStyle(fontWeight: FontWeight.w800))),
                        const Icon(Icons.thumb_up_alt_outlined, size: 16, color: Brand.green),
                        const SizedBox(width: 4),
                        Text('${o.thumbsUp}', style: const TextStyle(color: Colors.white70)),
                        const SizedBox(width: 12),
                        const Icon(Icons.thumb_down_alt_outlined, size: 16, color: Brand.red),
                        const SizedBox(width: 4),
                        Text('${o.thumbsDown}', style: const TextStyle(color: Colors.white70)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        FilledButton(style: compactFilled, key: Key('approve-offer-${o.id}'), onPressed: () => onApprove(o), child: const Text('Confirm')),
                        OutlinedButton(style: compactOutlined, key: Key('decline-offer-${o.id}'), onPressed: () => onDecline(o), child: const Text('Not this one')),
                      ],
                    ),
                  ],
                ),
              ),
          ],
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              if (r.isOpen && !r.hasMyOffer)
                FilledButton.icon(
                  style: compactFilled,
                  key: Key('claim-${r.id}'),
                  onPressed: onClaim,
                  icon: const Icon(Icons.volunteer_activism_rounded, size: 18),
                  label: Text(isAdmin ? "I'll take it" : (r.category == HelpCategory.ride ? 'I can give a ride' : 'I can help')),
                ),
              if (r.isOpen && r.hasMyOffer)
                OutlinedButton(style: compactOutlined, key: Key('withdraw-${r.id}'), onPressed: onWithdraw, child: const Text('Take back my offer')),
              if (canMessage)
                FilledButton.icon(
                  style: compactFilled,
                  key: Key('message-${r.id}'),
                  onPressed: onMessage,
                  icon: const Icon(Icons.chat_bubble_rounded, size: 18),
                  label: Text(isAdmin ? 'Message ${r.name ?? 'them'}' : 'Message the team'),
                ),
              if (mine) ...[
                // The next step, one tap: on my way, then I've arrived, then Done.
                if (r.progress == null)
                  FilledButton(style: compactFilled, key: Key('step-on-my-way-${r.id}'), onPressed: () => onProgress('on_my_way'), child: const Text('On my way')),
                if (r.progress == 'on_my_way' || r.progress == 'late')
                  FilledButton(style: compactFilled, key: Key('step-arrived-${r.id}'), onPressed: () => onProgress('arrived'), child: const Text("I've arrived")),
                OutlinedButton(style: compactOutlined, key: Key('finish-${r.id}'), onPressed: onFinish, child: const Text('Done')),
                if (r.progress != 'arrived')
                  PopupMenuButton<int>(
                    key: Key('late-${r.id}'),
                    color: Brand.surfaceHigh,
                    tooltip: 'Running late',
                    onSelected: (m) => onProgress('running_late', minutes: m),
                    itemBuilder: (context) => [
                      for (final m in const [10, 20, 30, 45, 60]) PopupMenuItem(key: Key('late-${r.id}-$m'), value: m, child: Text('About $m minutes late')),
                    ],
                    child: IgnorePointer(
                      child: OutlinedButton.icon(style: compactOutlined, onPressed: () {}, icon: const Icon(Icons.schedule_rounded, size: 18), label: const Text('Running late')),
                    ),
                  ),
                OutlinedButton(style: compactOutlined, key: Key('cant-make-it-${r.id}'), onPressed: () => onProgress('cant_make_it'), child: const Text("Can't make it")),
                OutlinedButton(
                  key: Key('unsafe-${r.id}'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44), foregroundColor: Brand.red, side: const BorderSide(color: Brand.red)),
                  onPressed: onUnsafe,
                  child: const Text("I don't feel safe"),
                ),
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

/// What the volunteer on it sees about their own match.
String _myStatus(HelpRequest r) {
  switch (r.progress) {
    case 'on_my_way':
      return "You're on your way";
    case 'arrived':
      return "You've arrived";
    case 'late':
      return r.progressMinutes == null ? "You're running late" : "You're running late (~${r.progressMinutes} min)";
    default:
      return "You're on it";
  }
}
