import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'api_client.dart';

/// The admins' shared contact book (name, phone, email, notes).
class ContactsController extends ChangeNotifier {
  /// Set by AppState: true while an admin is only previewing, so nothing is changed.
  bool Function()? writeBlocked;
  List<Contact> contacts = [];
  bool isLoading = false;
  String? error;

  /// Called on sign-out so the next person on this phone never sees these.
  void clearPrivate() {
    contacts = [];
    error = null;
    notifyListeners();
  }

  Future<void> refresh() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      contacts = await ApiClient.shared.fetchContacts();
    } catch (e) {
      error = e is GgcException ? e.message : "Couldn't load your contacts.";
    }
    isLoading = false;
    notifyListeners();
  }

  void _sort() => contacts.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  /// Adds a contact, or changes [id]. Returns an error message, or null on success.
  Future<String?> save({String? id, required String name, String? phone, String? email, String? notes}) async {
    if (writeBlocked?.call() == true) return 'Switched off while previewing.';
    if (name.trim().isEmpty) return 'Give this contact a name first.';
    try {
      if (id == null) {
        contacts = [...contacts, await ApiClient.shared.createContact(name: name.trim(), phone: phone, email: email, notes: notes)];
      } else {
        final updated = await ApiClient.shared.updateContact(id, name: name.trim(), phone: phone, email: email, notes: notes);
        contacts = [for (final c in contacts) if (c.id == id) updated else c];
      }
      _sort();
      notifyListeners();
      return null;
    } catch (e) {
      return e is GgcException ? e.message : "Couldn't save that contact.";
    }
  }

  Future<String?> delete(String id) async {
    if (writeBlocked?.call() == true) return 'Switched off while previewing.';
    try {
      await ApiClient.shared.deleteContact(id);
      contacts = [for (final c in contacts) if (c.id != id) c];
      notifyListeners();
      return null;
    } catch (e) {
      return e is GgcException ? e.message : "Couldn't delete that contact.";
    }
  }
}
