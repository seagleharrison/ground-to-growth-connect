import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import 'messages_view.dart';

/// Admins match volunteers with requests. This lists the volunteers who can
/// take one, and for each: Ping (asks them in chat, nothing is handed over
/// yet), Chat (opens the conversation) and Assign (gives them the request).
Future<void> showVolunteerPicker(BuildContext context, HelpRequest request) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _VolunteerPicker(request: request),
    );

class _VolunteerPicker extends StatefulWidget {
  final HelpRequest request;
  const _VolunteerPicker({required this.request});

  @override
  State<_VolunteerPicker> createState() => _VolunteerPickerState();
}

class _VolunteerPickerState extends State<_VolunteerPicker> {
  List<PersonSummary>? _volunteers;
  String? _error;
  final Set<String> _pinged = {};
  String? _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final people = await ApiClient.shared.fetchPeople('staff');
      if (!mounted) return;
      setState(() => _volunteers = [
            for (final p in people)
              if (p.role == 'volunteer' && p.approved && !p.paused) p,
          ]);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is GgcException ? e.message : "Couldn't load your volunteers.");
    }
  }

  void _say(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _ping(PersonSummary v) async {
    setState(() => _busy = v.userId);
    final error = await context.read<AppState>().help.askVolunteer(widget.request.id, v.userId);
    if (!mounted) return;
    setState(() {
      _busy = null;
      if (error == null) _pinged.add(v.userId);
    });
    _say(error ?? "Asked ${_first(v.name)}. Their reply will show in Messages.");
  }

  Future<void> _assign(PersonSummary v) async {
    setState(() => _busy = v.userId);
    final error = await context.read<AppState>().help.assign(widget.request.id, v.userId);
    if (!mounted) return;
    if (error != null) {
      setState(() => _busy = null);
      _say(error);
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Gave this to ${_first(v.name)}.')));
  }

  void _chat(PersonSummary v) {
    Navigator.of(context).pop();
    openChat(context, Conversation(userId: v.userId, name: v.name, role: 'volunteer'));
  }

  static String _first(String name) => name.trim().split(RegExp(r'\s+')).first;

  @override
  Widget build(BuildContext context) {
    final volunteers = _volunteers;
    final r = widget.request;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      decoration: const BoxDecoration(color: Brand.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 18),
          const Text('Find a volunteer', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            'Ping asks them in chat first. Assign gives them ${r.name == null ? 'this request' : "${_first(r.name!)}'s request"}.',
            style: const TextStyle(color: Colors.white60, height: 1.4),
          ),
          const SizedBox(height: 14),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Brand.red))
          else if (volunteers == null)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          else if (volunteers.isEmpty)
            const Text(
              key: Key('no-volunteers'),
              'No approved volunteers yet. Approve one under Me → Safety first.',
              style: TextStyle(color: Colors.white70, height: 1.4),
            )
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [for (final v in volunteers) _row(v)],
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(PersonSummary v) {
    final busy = _busy == v.userId;
    return Container(
      key: Key('volunteer-${v.userId}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Brand.surfaceHigh, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(v.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
              if (v.thumbsUp + v.thumbsDown > 0) ...[
                const Icon(Icons.thumb_up_alt_outlined, size: 15, color: Colors.white54),
                const SizedBox(width: 4),
                Text('${v.thumbsUp}', style: const TextStyle(color: Colors.white54, fontSize: 13)),
                const SizedBox(width: 12),
                const Icon(Icons.thumb_down_alt_outlined, size: 15, color: Colors.white54),
                const SizedBox(width: 4),
                Text('${v.thumbsDown}', style: const TextStyle(color: Colors.white54, fontSize: 13)),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              OutlinedButton.icon(
                key: Key('ping-${v.userId}'),
                style: compactOutlined,
                onPressed: busy ? null : () => _ping(v),
                icon: Icon(_pinged.contains(v.userId) ? Icons.check_rounded : Icons.notifications_active_outlined, size: 18),
                label: Text(_pinged.contains(v.userId) ? 'Asked' : 'Ping'),
              ),
              OutlinedButton.icon(
                key: Key('chat-${v.userId}'),
                style: compactOutlined,
                onPressed: busy ? null : () => _chat(v),
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                label: const Text('Chat'),
              ),
              FilledButton.icon(
                key: Key('assign-${v.userId}'),
                style: compactFilled,
                onPressed: busy ? null : () => _assign(v),
                icon: const Icon(Icons.assignment_ind_outlined, size: 18),
                label: const Text('Assign'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
