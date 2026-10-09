import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../util/help_icons.dart';
import '../util/supply_items.dart';
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
                ? 'What people have asked for, rides first. Anyone can accept one, and the person is told someone is coming.'
                : 'What people have asked for, rides first. Accept one and the person is told someone is coming, then tap each step as you go.',
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

/// One request on the board. The one thing to do next is the big button;
/// everything else sits in the menu, except the safety button, which is
/// always in view while someone is on a match.
class _BoardCard extends StatelessWidget {
  final HelpRequest request;
  final bool isAdmin;
  final VoidCallback onClaim;
  final VoidCallback onRelease;
  final VoidCallback onFinish;
  final VoidCallback onMessage;
  final bool canMessage;
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
    required this.onProgress,
    required this.onUnsafe,
  });

  String get _claimLabel => switch (request.category) {
        HelpCategory.ride => 'I can give this ride',
        HelpCategory.supplies => 'I can bring these',
        _ => 'I can help',
      };

  @override
  Widget build(BuildContext context) {
    final r = request;
    final appt = r.appointment;
    final mine = r.claimedByMe;
    final isRide = r.category == HelpCategory.ride;
    final title = isRide && appt != null ? 'Ride to ${appt.title}' : r.category.label;
    final hasMenu = mine || (isAdmin && (canMessage || (r.isClaimed && !mine)));

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
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                    Text('${r.name ?? 'Someone'} · ${timeAgo(r.createdAtLocal)}', style: const TextStyle(color: Colors.white54, fontSize: 13)),
                  ],
                ),
              ),
              if (hasMenu) _Menu(request: r, isAdmin: isAdmin, mine: mine, canMessage: canMessage, onMessage: onMessage, onRelease: onRelease, onProgress: onProgress),
            ],
          ),
          if (r.isClaimed) ...[
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerLeft, child: Pill(label: mine ? _myStatus(r) : _theirStatus(r), color: Brand.green)),
          ],
          if (r.category == HelpCategory.supplies && r.items.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              key: Key('items-${r.id}'),
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final code in r.items)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(supplyItems.where((i) => i.code == code).firstOrNull?.icon ?? Icons.inventory_2_rounded, size: 16, color: Brand.orange),
                    label: Text(supplyLabel(code)),
                  ),
              ],
            ),
          ],
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
          if (r.isOpen) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              key: Key('claim-${r.id}'),
              onPressed: onClaim,
              icon: const Icon(Icons.volunteer_activism_rounded, size: 18),
              label: Text(_claimLabel),
            ),
          ],
          if (mine) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // The next step, one tap: on my way, then I've arrived, then Done.
                if (r.category == HelpCategory.supplies) ...[
                  if (r.progress != 'ready')
                    FilledButton(style: compactFilled, key: Key('step-ready-${r.id}'), onPressed: () => onProgress('ready'), child: const Text("They're ready")),
                ] else ...[
                  if (r.progress == null)
                    FilledButton(style: compactFilled, key: Key('step-on-my-way-${r.id}'), onPressed: () => onProgress('on_my_way'), child: const Text('On my way')),
                  if (r.progress == 'on_my_way' || r.progress == 'late')
                    FilledButton(style: compactFilled, key: Key('step-arrived-${r.id}'), onPressed: () => onProgress('arrived'), child: const Text("I've arrived")),
                ],
                OutlinedButton(style: compactOutlined, key: Key('finish-${r.id}'), onPressed: onFinish, child: const Text('Done')),
                TextButton(
                  key: Key('unsafe-${r.id}'),
                  style: TextButton.styleFrom(foregroundColor: Brand.red, minimumSize: const Size(0, 44)),
                  onPressed: onUnsafe,
                  child: const Text("I don't feel safe"),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The less-used actions, out of the way.
class _Menu extends StatelessWidget {
  final HelpRequest request;
  final bool isAdmin;
  final bool mine;
  final bool canMessage;
  final VoidCallback onMessage;
  final VoidCallback onRelease;
  final void Function(String kind, {int? minutes}) onProgress;
  const _Menu({required this.request, required this.isAdmin, required this.mine, required this.canMessage, required this.onMessage, required this.onRelease, required this.onProgress});

  @override
  Widget build(BuildContext context) {
    final r = request;
    final isRide = r.category == HelpCategory.ride;
    return PopupMenuButton<String>(
      key: Key('more-${r.id}'),
      color: Brand.surfaceHigh,
      tooltip: 'More',
      onSelected: (v) {
        if (v == 'message') {
          onMessage();
        } else if (v == 'free') {
          onRelease();
        } else if (v == 'cant') {
          onProgress('cant_make_it');
        } else if (v.startsWith('late-')) {
          onProgress('running_late', minutes: int.parse(v.substring(5)));
        }
      },
      itemBuilder: (context) => [
        if (mine && isRide && r.progress != 'arrived')
          for (final m in const [10, 20, 30, 60]) PopupMenuItem(key: Key('late-${r.id}-$m'), value: 'late-$m', child: Text('Running about $m min late')),
        if (mine) PopupMenuItem(key: Key('cant-make-it-${r.id}'), value: 'cant', child: const Text("Can't make it")),
        if (canMessage) PopupMenuItem(key: Key('message-${r.id}'), value: 'message', child: Text(isAdmin ? 'Message ${r.name ?? 'them'}' : 'Message the team')),
        if (!mine && isAdmin && r.isClaimed) PopupMenuItem(key: Key('free-${r.id}'), value: 'free', child: const Text('Free up')),
      ],
    );
  }
}

/// What the person's request shows for someone else's match (admins).
String _theirStatus(HelpRequest r) {
  final who = r.helperName ?? 'A volunteer';
  switch (r.progress) {
    case 'on_my_way':
      return '$who is on the way';
    case 'arrived':
      return '$who has arrived';
    case 'ready':
      return '$who has them ready';
    default:
      return '$who is helping';
  }
}

/// What the volunteer on it sees about their own match.
String _myStatus(HelpRequest r) {
  switch (r.progress) {
    case 'on_my_way':
      return "You're on your way";
    case 'arrived':
      return "You've arrived";
    case 'ready':
      return 'Ready for pickup';
    case 'late':
      return r.progressMinutes == null ? "You're running late" : "You're running late (~${r.progressMinutes} min)";
    default:
      return "You're on it";
  }
}
