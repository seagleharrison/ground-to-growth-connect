import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../util/launch.dart';
import '../widgets/ui.dart';

/// The admins' shared contact book: a name, phone, email and a note for each
/// person or place the team may need to reach. Opened from Me.
class ContactsView extends StatefulWidget {
  const ContactsView({super.key});

  @override
  State<ContactsView> createState() => _ContactsViewState();
}

class _ContactsViewState extends State<ContactsView> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().contacts.refresh();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppState>().contacts;
    final query = _search.text.trim().toLowerCase();
    final shown = [
      for (final c in controller.contacts)
        if (query.isEmpty ||
            c.name.toLowerCase().contains(query) ||
            (c.phone ?? '').contains(query) ||
            (c.email ?? '').toLowerCase().contains(query) ||
            (c.notes ?? '').toLowerCase().contains(query))
          c,
    ];

    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          GradientButton(
            key: const Key('add-contact'),
            label: 'Add a contact',
            icon: Icons.person_add_alt_1_rounded,
            onPressed: () => showContactSheet(context),
          ),
          const SizedBox(height: 14),
          if (controller.contacts.length > 4) ...[
            TextField(
              key: const Key('contact-search'),
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(hintText: 'Search contacts', prefixIcon: Icon(Icons.search_rounded)),
            ),
            const SizedBox(height: 14),
          ],
          if (controller.error != null)
            Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(controller.error!, style: const TextStyle(color: Brand.red))),
          if (controller.contacts.isEmpty && !controller.isLoading && controller.error == null)
            const AppCard(
              key: Key('contacts-empty'),
              child: Text(
                'Keep the numbers the team needs here: case workers, clinics, kitchens. Only admins can see this list.',
                style: TextStyle(color: Colors.white70, height: 1.4),
              ),
            )
          else if (shown.isEmpty && controller.contacts.isNotEmpty)
            const Padding(padding: EdgeInsets.all(12), child: Text('No one matches that.', style: TextStyle(color: Colors.white60))),
          for (final c in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                key: Key('contact-${c.id}'),
                onTap: () => showContactSheet(context, existing: c),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: Brand.orange.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
                      child: Text(c.name.trim().characters.first.toUpperCase(), style: const TextStyle(color: Brand.orange, fontWeight: FontWeight.w800, fontSize: 17)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                          if ((c.phone ?? '').isNotEmpty || (c.email ?? '').isNotEmpty)
                            Text(
                              [if ((c.phone ?? '').isNotEmpty) c.phone!, if ((c.email ?? '').isNotEmpty) c.email!].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white60, fontSize: 13.5),
                            ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: Colors.white38),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Add a contact, or look at and change one. Notes sit underneath the other fields.
Future<void> showContactSheet(BuildContext context, {Contact? existing}) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ContactSheet(existing: existing),
    );

class _ContactSheet extends StatefulWidget {
  final Contact? existing;
  const _ContactSheet({this.existing});

  @override
  State<_ContactSheet> createState() => _ContactSheetState();
}

class _ContactSheetState extends State<_ContactSheet> {
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _phone = TextEditingController(text: widget.existing?.phone);
  late final _email = TextEditingController(text: widget.existing?.email);
  late final _notes = TextEditingController(text: widget.existing?.notes);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Give this contact a name first.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await context.read<AppState>().contacts.save(
          id: widget.existing?.id,
          name: _name.text,
          phone: _phone.text,
          email: _email.text,
          notes: _notes.text,
        );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _saving = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final c = widget.existing!;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${c.name}?'),
        content: const Text('This removes them from the contact book for every admin.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(key: const Key('confirm-delete-contact'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Brand.red))),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    final error = await context.read<AppState>().contacts.delete(c.id);
    if (!mounted) return;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    final hasPhone = (existing?.phone ?? '').isNotEmpty;
    final hasEmail = (existing?.email ?? '').isNotEmpty;
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
              Text(existing == null ? 'New contact' : 'Contact', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              TextField(
                key: const Key('contact-name'),
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name', prefixIcon: Icon(Icons.person_outline_rounded)),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('contact-phone'),
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone number', prefixIcon: Icon(Icons.phone_outlined)),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('contact-email'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline_rounded)),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('contact-notes'),
                controller: _notes,
                minLines: 4,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Notes', alignLabelWithHint: true),
              ),
              if (existing != null && (hasPhone || hasEmail)) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    if (hasPhone)
                      OutlinedButton.icon(
                        key: const Key('contact-call'),
                        style: compactOutlined,
                        onPressed: () => Launch.call(context, existing.phone!, existing.phone!),
                        icon: const Icon(Icons.call_rounded, size: 18),
                        label: const Text('Call'),
                      ),
                    if (hasEmail)
                      OutlinedButton.icon(
                        key: const Key('contact-email-button'),
                        style: compactOutlined,
                        onPressed: () => Launch.link(context, 'mailto:${existing.email}'),
                        icon: const Icon(Icons.mail_rounded, size: 18),
                        label: const Text('Email'),
                      ),
                  ],
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, key: const Key('contact-error'), style: const TextStyle(color: Brand.amber)),
              ],
              const SizedBox(height: 16),
              GradientButton(
                key: const Key('save-contact'),
                label: _saving ? 'Saving…' : 'Save',
                onPressed: _saving ? null : _save,
              ),
              if (existing != null)
                Center(
                  child: TextButton(
                    key: const Key('delete-contact'),
                    onPressed: _saving ? null : _delete,
                    style: TextButton.styleFrom(foregroundColor: Brand.red, minimumSize: const Size(0, 44)),
                    child: const Text('Delete contact'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
