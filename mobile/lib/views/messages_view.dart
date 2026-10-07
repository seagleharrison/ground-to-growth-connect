import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../util/time.dart';
import '../widgets/ui.dart';
import 'chat_view.dart';
import 'safety_view.dart';

void openChat(BuildContext context, Conversation contact) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatView(contact: contact)));
}

/// One person in a list: name, who they are, the last thing said, and a dot
/// with a count when something is unread.
class ContactTile extends StatelessWidget {
  final Conversation contact;
  const ContactTile({super.key, required this.contact});

  @override
  Widget build(BuildContext context) {
    final unread = contact.unread;
    return PressableScale(
      onTap: () => openChat(context, contact),
      child: Container(
        key: Key('contact-${contact.userId}'),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Brand.surfaceHigh, borderRadius: BorderRadius.circular(20)),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: Brand.surface,
              child: Text(
                contact.name.isEmpty ? '?' : contact.name.characters.first.toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.w800, color: Brand.orange),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(contact.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(
                    contact.lastMessage ?? contact.roleLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: unread > 0 ? Colors.white : Colors.white54, fontSize: 13),
                  ),
                ],
              ),
            ),
            if (contact.lastAtLocal != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(timeAgo(contact.lastAtLocal!), style: const TextStyle(color: Colors.white38, fontSize: 12)),
              ),
            if (unread > 0)
              Container(
                key: Key('unread-${contact.userId}'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Brand.orangeDeep, borderRadius: BorderRadius.circular(12)),
                child: Text('$unread', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Color(0xFF2A1400))),
              ),
          ],
        ),
      ),
    );
  }
}

/// Keeps the contact list fresh while it's on screen.
mixin ConversationPolling<T extends StatefulWidget> on State<T> {
  Timer? _timer;

  void startPollingConversations() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().chat.refreshConversations();
    });
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) context.read<AppState>().chat.refreshConversations();
    });
  }

  void stopPollingConversations() => _timer?.cancel();
}

/// Messages tab for volunteers and admins.
class MessagesView extends StatefulWidget {
  const MessagesView({super.key});

  @override
  State<MessagesView> createState() => _MessagesViewState();
}

class _MessagesViewState extends State<MessagesView> with ConversationPolling {
  @override
  void initState() {
    super.initState();
    startPollingConversations();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final app = context.read<AppState>();
      if (app.currentView == AppView.admin) app.safety.refreshSummary();
    });
  }

  @override
  void dispose() {
    stopPollingConversations();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final chat = app.chat;
    final attention = app.safety.needsAttention;
    return LargeTitlePage(
      title: 'Messages',
      onRefresh: chat.refreshConversations,
      children: [
        if (app.currentView == AppView.admin)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: AppCard(
              key: const Key('open-safety'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SafetyView())),
              child: Row(
                children: [
                  const Icon(Icons.shield_rounded, color: Brand.blue),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Safety', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        Text('Approve volunteers, see reports, review conversations', style: TextStyle(color: Colors.white54, fontSize: 13)),
                      ],
                    ),
                  ),
                  if (attention > 0)
                    Container(
                      key: const Key('safety-badge'),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: Brand.red, borderRadius: BorderRadius.circular(12)),
                      child: Text('$attention', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                    ),
                  const Icon(Icons.chevron_right_rounded, color: Colors.white38),
                ],
              ),
            ),
          ),
        if (chat.error != null)
          Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(chat.error!, style: const TextStyle(color: Brand.red))),
        if (chat.conversations.isEmpty && !chat.isLoading)
          const AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('No messages yet', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                SizedBox(height: 6),
                Text(
                  'Ground to Growth admins show up here. Chat runs through the team, so you can message them about anything you\'re helping with.',
                  style: TextStyle(color: Colors.white70, height: 1.4),
                ),
              ],
            ),
          ),
        for (final c in chat.conversations) ContactTile(contact: c),
      ],
    );
  }
}

/// On a participant's Home: the people they can message, right there.
class HomeContactsCard extends StatefulWidget {
  const HomeContactsCard({super.key});

  @override
  State<HomeContactsCard> createState() => _HomeContactsCardState();
}

class _HomeContactsCardState extends State<HomeContactsCard> with ConversationPolling {
  @override
  void initState() {
    super.initState();
    startPollingConversations();
  }

  @override
  void dispose() {
    stopPollingConversations();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<AppState>().chat;
    if (chat.conversations.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const Key('home-contacts'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Messages'),
        for (final c in chat.conversations.take(4)) ContactTile(contact: c),
      ],
    );
  }
}
