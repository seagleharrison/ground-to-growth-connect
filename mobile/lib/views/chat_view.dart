import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../util/time.dart';

/// One-to-one chat. There's no push service, so while this is open it checks
/// for new messages every few seconds.
class ChatView extends StatefulWidget {
  final Conversation contact;
  const ChatView({super.key, required this.contact});

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  Timer? _poll;
  bool _sending = false;
  String? _error;
  int _shown = 0;

  String get _id => widget.contact.userId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().chat.loadThread(_id);
    });
    _poll = Timer.periodic(const Duration(seconds: 6), (_) {
      if (mounted) context.read<AppState>().chat.loadThread(_id);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    final error = await context.read<AppState>().chat.send(_id, text);
    if (!mounted) return;
    setState(() {
      _sending = false;
      _error = error;
      if (error == null) _controller.clear();
    });
  }

  Future<void> _report() async {
    // null means cancelled; otherwise the text typed (possibly empty).
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => _ReportDialog(name: widget.contact.name),
    );
    if (reason == null || !mounted) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final result = await context.read<AppState>().chat.report(_id, reason: reason.isEmpty ? null : reason);
    if (result.error != null) {
      messenger.showSnackBar(SnackBar(content: Text(result.error!)));
      return;
    }
    messenger.showSnackBar(SnackBar(
      content: Text(result.blocked
          ? "Thank you. An admin will look at this, and ${widget.contact.name} can't contact you in the meantime."
          : 'Thank you. An admin will look at this.'),
    ));
    if (result.blocked) navigator.pop();
  }

  Future<void> _block() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Brand.surface,
        title: Text('Block ${widget.contact.name}?'),
        content: Text(
          "You won't be able to message each other, and ${widget.contact.name} won't see your requests. "
          'If they were helping you, your request goes back to other volunteers. You can undo this in Me.',
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(key: const Key('confirm-block'), onPressed: () => Navigator.pop(context, true), child: const Text('Block')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final error = await context.read<AppState>().chat.block(_id);
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text('${widget.contact.name} is blocked.')));
    navigator.pop();
  }

  void _scrollToEnd() {
    if (!_scroll.hasClients) return;
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final messages = app.chat.threads[_id] ?? const <ChatMessage>[];
    if (messages.length != _shown) {
      _shown = messages.length;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Brand.background,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.contact.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            Text(widget.contact.roleLabel, style: const TextStyle(fontSize: 12, color: Colors.white54)),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            key: const Key('chat-menu'),
            onSelected: (v) => v == 'report' ? _report() : _block(),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'report', key: Key('menu-report'), child: Text('Report a problem')),
              // People getting support can block a volunteer; the team can't be blocked.
              if (app.user?.isStaff == false && widget.contact.role != 'team')
                PopupMenuItem(value: 'block', key: const Key('menu-block'), child: Text('Block ${widget.contact.name}')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            key: const Key('chat-safety-notice'),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Brand.surface,
            child: const Row(
              children: [
                Icon(Icons.shield_outlined, size: 16, color: Brand.blue),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ground to Growth staff may review messages to keep everyone safe.',
                    style: TextStyle(color: Colors.white60, fontSize: 12.5, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        app.chat.error ?? 'Say hello to ${widget.contact.name}. Messages are private between the two of you.',
                        key: const Key('chat-empty'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white54, height: 1.4),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    itemCount: messages.length,
                    itemBuilder: (context, i) => _Bubble(message: messages[i]),
                  ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Text(_error!, style: const TextStyle(color: Brand.red, fontSize: 13)),
            ),
          if (!app.chat.canSendTo(_id))
            SafeArea(
              top: false,
              child: Container(
                key: const Key('chat-closed'),
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Brand.surface, borderRadius: BorderRadius.circular(16)),
                child: Text(
                  app.user?.isStaff == true
                      ? "This chat is closed because you're no longer helping this person."
                      : 'This chat is closed because the help has ended. You can ask for help again, or message the Ground to Growth team any time.',
                  style: const TextStyle(color: Colors.white60, height: 1.4),
                ),
              ),
            )
          else
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('chat-input'),
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(hintText: 'Message'),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    key: const Key('chat-send'),
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.arrow_upward_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage message;
  const _Bubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final mine = message.fromMe;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        decoration: BoxDecoration(
          color: mine ? Brand.orangeDeep : Brand.surfaceHigh,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message.body, style: TextStyle(fontSize: 16, height: 1.3, color: mine ? const Color(0xFF2A1400) : Colors.white)),
            const SizedBox(height: 3),
            Text(
              timeAgo(message.createdAtLocal),
              style: TextStyle(fontSize: 11, color: mine ? const Color(0xAA2A1400) : Colors.white38),
            ),
          ],
        ),
      ),
    );
  }
}

/// Owns its text box, so the controller lives exactly as long as the dialog
/// (including while it animates closed).
class _ReportDialog extends StatefulWidget {
  final String name;
  const _ReportDialog({required this.name});

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Brand.surface,
      title: const Text('Report a problem'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tell the Ground to Growth team what happened with ${widget.name}. An admin will look at it.',
            style: const TextStyle(color: Colors.white70, height: 1.4),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('report-reason'),
            controller: _reason,
            maxLines: 4,
            maxLength: 1000,
            decoration: const InputDecoration(hintText: 'What happened? (optional)'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          key: const Key('send-report'),
          onPressed: () => Navigator.pop(context, _reason.text.trim()),
          child: const Text('Send report'),
        ),
      ],
    );
  }
}
