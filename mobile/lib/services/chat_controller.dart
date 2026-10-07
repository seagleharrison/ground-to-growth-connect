import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'api_client.dart';

/// Contacts and one-to-one chat. There's no push service, so screens that are
/// open poll [refreshConversations] / [loadThread] every few seconds.
class ChatController extends ChangeNotifier {
  List<Conversation> conversations = [];
  final Map<String, List<ChatMessage>> threads = {};
  final Map<String, bool> _threadCanSend = {};

  /// People this person has blocked (people getting support only).
  List<PersonRef> blocked = [];
  bool isLoading = false;
  String? error;

  /// Set by AppState: true (and tells the person why) while an admin is only
  /// previewing, so nothing is sent from a preview.
  bool Function()? writeBlocked;

  /// Set by AppState: keeps the app icon's badge in step with unread messages.
  void Function(int count)? badgeSink;

  int get unreadTotal => conversations.fold(0, (sum, c) => sum + c.unread);

  /// Whether new messages can still go to this person: false once the help
  /// that opened the chat has ended, or after a block or pause.
  bool canSendTo(String userId) =>
      _threadCanSend[userId] ?? conversations.where((c) => c.userId == userId).firstOrNull?.canSend ?? true;

  void clearPrivate() {
    conversations = [];
    blocked = [];
    threads.clear();
    _threadCanSend.clear();
    error = null;
    notifyListeners();
  }

  Future<void> refreshConversations() async {
    isLoading = true;
    notifyListeners();
    try {
      conversations = await ApiClient.shared.fetchConversations();
      error = null;
      badgeSink?.call(unreadTotal);
    } catch (e) {
      error = e is GgcException ? e.message : "Couldn't load your messages.";
    }
    isLoading = false;
    notifyListeners();
  }

  /// Fetches the thread (which also marks it read) and clears its unread count.
  Future<void> loadThread(String userId) async {
    try {
      final thread = await ApiClient.shared.fetchThread(userId);
      threads[userId] = thread.messages;
      _threadCanSend[userId] = thread.canSend;
      conversations = [
        for (final c in conversations)
          if (c.userId == userId)
            Conversation(userId: c.userId, name: c.name, role: c.role, lastMessage: c.lastMessage, lastAt: c.lastAt, canSend: thread.canSend)
          else
            c,
      ];
      error = null;
    } catch (e) {
      error = e is GgcException ? e.message : "Couldn't load this chat.";
    }
    notifyListeners();
  }

  /// Returns an error message, or null once it's sent.
  Future<String?> send(String userId, String body) async {
    if (writeBlocked?.call() == true) return "Switched off while previewing.";
    try {
      final sent = await ApiClient.shared.sendMessage(userId, body);
      threads[userId] = [...?threads[userId], sent];
      notifyListeners();
      return null;
    } catch (e) {
      return e is GgcException ? e.message : "Couldn't send that.";
    }
  }

  /// Blocks someone. Returns an error message, or null once it's done.
  Future<String?> block(String userId) async {
    if (writeBlocked?.call() == true) return "Switched off while previewing.";
    try {
      await ApiClient.shared.blockUser(userId);
      conversations = conversations.where((c) => c.userId != userId).toList();
      threads.remove(userId);
      _threadCanSend.remove(userId);
      notifyListeners();
      refreshBlocked();
      return null;
    } catch (e) {
      return e is GgcException ? e.message : "Couldn't block them just now.";
    }
  }

  /// "Report a problem". [blocked] says whether the person was also blocked
  /// right away (reporting a volunteer does that).
  Future<({String? error, bool blocked})> report(String userId, {String? reason}) async {
    if (writeBlocked?.call() == true) return (error: "Switched off while previewing.", blocked: false);
    try {
      final blocked = await ApiClient.shared.reportUser(userId, reason: reason);
      if (blocked) {
        conversations = conversations.where((c) => c.userId != userId).toList();
        notifyListeners();
      }
      return (error: null, blocked: blocked);
    } catch (e) {
      return (error: e is GgcException ? e.message : "Couldn't send that report.", blocked: false);
    }
  }

  Future<void> refreshBlocked() async {
    try {
      blocked = await ApiClient.shared.fetchBlocked();
    } catch (_) {}
    notifyListeners();
  }

  Future<String?> unblock(String userId) async {
    if (writeBlocked?.call() == true) return "Switched off while previewing.";
    try {
      await ApiClient.shared.unblockUser(userId);
      blocked = blocked.where((p) => p.userId != userId).toList();
      notifyListeners();
      return null;
    } catch (e) {
      return e is GgcException ? e.message : "Couldn't unblock them just now.";
    }
  }
}
