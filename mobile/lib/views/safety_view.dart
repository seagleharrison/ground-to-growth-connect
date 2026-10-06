import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../util/time.dart';
import '../widgets/ui.dart';

/// Admin-only: keeping people safe. Approve new volunteers, see what's been
/// reported, and review conversations — every review is recorded.
class SafetyView extends StatefulWidget {
  const SafetyView({super.key});

  @override
  State<SafetyView> createState() => _SafetyViewState();
}

class _SafetyViewState extends State<SafetyView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().safety.refreshAll();
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

  void _open(AdminConversation c) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => AdminConversationView(a: c.a, b: c.b)),
      );

  @override
  Widget build(BuildContext context) {
    final safety = context.watch<AppState>().safety;
    final pending = [for (final v in safety.volunteers) if (!v.approved) v];
    final active = [for (final v in safety.volunteers) if (v.approved) v];
    final open = [for (final r in safety.reports) if (r.isOpen) r];
    final now = DateTime.now();

    return LargeTitlePage(
      title: 'Safety',
      onRefresh: safety.refreshAll,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 16),
          child: Text(
            'Messages are private between two people unless an admin reviews them to keep someone safe. '
            'Every time you open a conversation here, it is recorded.',
            style: TextStyle(color: Colors.white60, height: 1.4),
          ),
        ),
        if (safety.error != null)
          Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(safety.error!, style: const TextStyle(color: Brand.red))),

        const SectionLabel('Waiting for approval'),
        if (pending.isEmpty)
          const Padding(padding: EdgeInsets.only(bottom: 18, left: 4), child: Text('No one is waiting.', key: Key('no-pending'), style: TextStyle(color: Colors.white54))),
        for (final v in pending)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppCard(
              key: Key('pending-${v.userId}'),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(v.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        Text('Signed up ${timeAgo(DateTime.parse(v.createdAt).toLocal(), now: now)}. Can\'t see anyone yet.', style: const TextStyle(color: Colors.white54, fontSize: 13)),
                      ],
                    ),
                  ),
                  FilledButton(style: compactFilled, key: Key('approve-${v.userId}'), onPressed: () => _run(() => safety.volunteerAction(v.userId, 'approve')), child: const Text('Approve')),
                ],
              ),
            ),
          ),

        const SizedBox(height: 8),
        const SectionLabel('Reports'),
        if (open.isEmpty)
          const Padding(padding: EdgeInsets.only(bottom: 18, left: 4), child: Text('Nothing reported.', key: Key('no-reports'), style: TextStyle(color: Colors.white54))),
        for (final r in open)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppCard(
              key: Key('report-${r.id}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.flag_rounded, color: Brand.red, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('${r.reporter.name} reported ${r.subject.name}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(timeAgo(r.createdAtLocal, now: now), style: const TextStyle(color: Colors.white54, fontSize: 13)),
                  ),
                  if ((r.reason ?? '').isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(r.reason!, style: const TextStyle(height: 1.4)),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      FilledButton(style: compactFilled, 
                        key: Key('review-${r.id}'),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => AdminConversationView(a: r.reporter, b: r.subject)),
                        ),
                        child: const Text('Review chat'),
                      ),
                      OutlinedButton(style: compactOutlined, key: Key('resolve-${r.id}'), onPressed: () => _run(() => safety.resolve(r.id)), child: const Text('Mark resolved')),
                      if (r.subject.role == 'volunteer')
                        OutlinedButton(style: compactOutlined, 
                          key: Key('pause-report-${r.id}'),
                          onPressed: () => _run(() => safety.volunteerAction(r.subject.userId, 'pause')),
                          child: Text('Pause ${r.subject.name}'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),

        const SizedBox(height: 8),
        const SectionLabel('Conversations'),
        if (safety.conversations.isEmpty)
          const Padding(padding: EdgeInsets.only(bottom: 18, left: 4), child: Text('No conversations yet.', style: TextStyle(color: Colors.white54))),
        for (final c in safety.conversations)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppCard(
              key: Key('convo-${c.a.userId}-${c.b.userId}'),
              onTap: () => _open(c),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${c.a.name} & ${c.b.name}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text('${c.count} messages · ${timeAgo(c.lastAtLocal, now: now)}', style: const TextStyle(color: Colors.white54, fontSize: 13)),
                      ],
                    ),
                  ),
                  if (c.flagged) const Pill(label: 'Reported', color: Brand.red),
                  const Icon(Icons.chevron_right_rounded, color: Colors.white38),
                ],
              ),
            ),
          ),

        const SizedBox(height: 8),
        const SectionLabel('Volunteers'),
        if (active.isEmpty)
          const Padding(padding: EdgeInsets.only(bottom: 18, left: 4), child: Text('No approved volunteers yet.', style: TextStyle(color: Colors.white54))),
        for (final v in active)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppCard(
              key: Key('volunteer-${v.userId}'),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(child: Text(v.name, style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
                        if (v.paused) ...[const SizedBox(width: 8), const Pill(label: 'Paused', color: Brand.amber)],
                      ],
                    ),
                  ),
                  TextButton(
                    key: Key(v.paused ? 'unpause-${v.userId}' : 'pause-${v.userId}'),
                    onPressed: () => _run(() => safety.volunteerAction(v.userId, v.paused ? 'unpause' : 'pause')),
                    child: Text(v.paused ? 'Resume' : 'Pause'),
                  ),
                  TextButton(
                    key: Key('revoke-${v.userId}'),
                    onPressed: () => _run(() => safety.volunteerAction(v.userId, 'revoke')),
                    child: const Text('Remove access', style: TextStyle(color: Brand.red)),
                  ),
                ],
              ),
            ),
          ),

        const SizedBox(height: 8),
        const SectionLabel('Who has reviewed conversations'),
        if (safety.accessLog.isEmpty)
          const Padding(padding: EdgeInsets.only(left: 4), child: Text('No conversation has been opened yet.', key: Key('no-access'), style: TextStyle(color: Colors.white54))),
        for (final e in safety.accessLog.take(10))
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              '${e.admin} reviewed ${e.a} and ${e.b} · ${timeAgo(e.createdAtLocal, now: now)}',
              style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.35),
            ),
          ),
      ],
    );
  }
}

/// An admin reading one conversation. Opening it was recorded.
class AdminConversationView extends StatefulWidget {
  final PersonRef a;
  final PersonRef b;
  const AdminConversationView({super.key, required this.a, required this.b});

  @override
  State<AdminConversationView> createState() => _AdminConversationViewState();
}

class _AdminConversationViewState extends State<AdminConversationView> {
  List<AdminMessage>? _messages;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final m = await context.read<AppState>().safety.read(widget.a.userId, widget.b.userId);
      if (mounted) setState(() => _messages = m);
    } catch (e) {
      if (mounted) setState(() => _error = e is GgcException ? e.message : "Couldn't open this conversation.");
    }
  }

  String _name(String id) => id == widget.a.userId ? widget.a.name : widget.b.name;

  @override
  Widget build(BuildContext context) {
    final messages = _messages;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Brand.background,
        title: Text('${widget.a.name} & ${widget.b.name}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
      ),
      body: Column(
        children: [
          Container(
            key: const Key('review-notice'),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Brand.surface,
            child: const Text(
              'You are reviewing this conversation for safety. Opening it has been recorded.',
              style: TextStyle(color: Brand.amber, fontSize: 13),
            ),
          ),
          Expanded(
            child: _error != null
                ? Center(child: Text(_error!, style: const TextStyle(color: Brand.red)))
                : messages == null
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: messages.length,
                        itemBuilder: (context, i) {
                          final m = messages[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${_name(m.senderId)} · ${timeAgo(m.createdAtLocal)}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                const SizedBox(height: 2),
                                Text(m.body, style: const TextStyle(fontSize: 16, height: 1.35)),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
