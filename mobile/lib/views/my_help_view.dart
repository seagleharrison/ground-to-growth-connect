import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../util/help_icons.dart';
import '../util/time.dart';
import '../widgets/ui.dart';
import 'messages_view.dart';

/// Opened from Home: what I've asked for, who's helping, and a way to ask.
class MyHelpView extends StatefulWidget {
  const MyHelpView({super.key});

  @override
  State<MyHelpView> createState() => _MyHelpViewState();
}

class _MyHelpViewState extends State<MyHelpView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final app = context.read<AppState>();
      app.help.refreshMine();
      app.calendar.refreshAppointments();
      app.chat.refreshConversations();
    });
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
    return LargeTitlePage(
      title: 'Ask for help',
      onRefresh: help.refreshMine,
      children: [
        GradientButton(
          key: const Key('ask-for-help'),
          label: 'What do you need?',
          icon: Icons.add_rounded,
          onPressed: () => showAskForHelpSheet(context),
        ),
        const SizedBox(height: 18),
        if (help.mineError != null)
          Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(help.mineError!, style: const TextStyle(color: Brand.red))),
        if (help.mine.isEmpty && !help.isLoadingMine)
          const AppCard(
            child: Text(
              "Tell us what you need and a volunteer can step in. You'll see here when someone's on it.",
              style: TextStyle(color: Colors.white70, height: 1.4),
            ),
          ),
        for (final r in help.mine)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _MyRequestCard(
              request: r,
              onDone: () => _run(() => help.markDone(r.id)),
              onCancel: () => _run(() => help.cancel(r.id)),
              onMessageHelper: () {
                final match = app.chat.conversations.where((c) => c.role == 'volunteer' && c.name == r.helperName);
                if (match.isNotEmpty) openChat(context, match.first);
              },
              canMessageHelper: r.helperName != null &&
                  app.chat.conversations.any((c) => c.role == 'volunteer' && c.name == r.helperName),
            ),
          ),
      ],
    );
  }
}

class _MyRequestCard extends StatelessWidget {
  final HelpRequest request;
  final VoidCallback onDone;
  final VoidCallback onCancel;
  final VoidCallback onMessageHelper;
  final bool canMessageHelper;

  const _MyRequestCard({
    required this.request,
    required this.onDone,
    required this.onCancel,
    required this.onMessageHelper,
    required this.canMessageHelper,
  });

  @override
  Widget build(BuildContext context) {
    final r = request;
    final appt = r.appointment;
    final (label, color) = r.isDone
        ? ('Done', Colors.white54)
        : r.isClaimed
            ? ('${r.helperName ?? 'A volunteer'} is helping', Brand.green)
            : ('Waiting for a volunteer', Brand.amber);
    return AppCard(
      key: Key('my-help-${r.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(r.category.icon, color: Brand.orange),
              const SizedBox(width: 10),
              Expanded(child: Text(r.category.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
              Pill(label: label, color: color),
            ],
          ),
          if ((r.note ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(r.note!, style: const TextStyle(color: Colors.white70, height: 1.4)),
          ],
          if (appt != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.event_rounded, size: 16, color: Brand.blue),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${appt.title} · ${shortDate(appt.startsAtLocal)} ${clockTime(appt.startsAtLocal)}',
                    style: const TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
          if (!r.isDone) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                if (canMessageHelper)
                  FilledButton.icon(style: compactFilled, 
                    key: Key('message-helper-${r.id}'),
                    onPressed: onMessageHelper,
                    icon: const Icon(Icons.chat_bubble_rounded, size: 18),
                    label: Text('Message ${r.helperName}'),
                  ),
                OutlinedButton(style: compactOutlined, key: Key('all-set-${r.id}'), onPressed: onDone, child: const Text("I'm all set")),
                TextButton(key: Key('cancel-${r.id}'), onPressed: onCancel, child: const Text('Cancel request')),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

Future<void> showAskForHelpSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AskSheet(),
    );

class _AskSheet extends StatefulWidget {
  const _AskSheet();

  @override
  State<_AskSheet> createState() => _AskSheetState();
}

class _AskSheetState extends State<_AskSheet> {
  final _note = TextEditingController();
  HelpCategory? _category;
  String? _appointmentId;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final category = _category;
    if (category == null) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    final error = await context.read<AppState>().help.ask(
          category: category,
          note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          appointmentId: _appointmentId,
        );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _sending = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final upcoming = [
      for (final a in context.watch<AppState>().calendar.appointments)
        if (a.startsAtLocal.isAfter(now.subtract(const Duration(hours: 3)))) a,
    ];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        decoration: const BoxDecoration(color: Brand.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 18),
              const Text('What do you need?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in HelpCategory.values)
                    ChoiceChip(
                      key: Key('category-${c.wireValue}'),
                      avatar: Icon(c.icon, size: 18),
                      label: Text(c.label),
                      selected: _category == c,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _category = c),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                key: const Key('help-note-field'),
                controller: _note,
                maxLines: 3,
                maxLength: 500,
                decoration: const InputDecoration(labelText: 'Anything we should know? (optional)', prefixIcon: Icon(Icons.notes_rounded)),
              ),
              if (upcoming.isNotEmpty) ...[
                const SizedBox(height: 6),
                DropdownButtonFormField<String?>(
                  key: const Key('help-appointment-field'),
                  initialValue: _appointmentId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Need to get to an appointment? (optional)', prefixIcon: Icon(Icons.event_rounded)),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('No appointment')),
                    for (final a in upcoming)
                      DropdownMenuItem<String?>(
                        value: a.id,
                        child: Text('${a.title} · ${shortDate(a.startsAtLocal)} ${clockTime(a.startsAtLocal)}', overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() => _appointmentId = v),
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                'Volunteers and staff will see this request and your name. If you pick an appointment, they see that one only — nothing else on your calendar. Ground to Growth staff may review messages to keep everyone safe.',
                style: TextStyle(color: Colors.white54, fontSize: 12.5, height: 1.4),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: Brand.red, fontSize: 14)),
              ],
              const SizedBox(height: 16),
              GradientButton(
                key: const Key('send-help-request'),
                label: 'Send request',
                loading: _sending,
                onPressed: _category == null ? null : _send,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
