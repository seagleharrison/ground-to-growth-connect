import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../theme/app_theme.dart';
import '../util/time.dart';
import '../widgets/ui.dart';

/// Which of the two lists to open from Analytics.
enum PeopleGroup {
  serve('serve', 'People we serve'),
  staff('staff', 'Staff & volunteers');

  final String wire;
  final String title;
  const PeopleGroup(this.wire, this.title);
}

String _joined(DateTime d) => 'Joined ${shortDate(d)}, ${d.year}';

String _roleLabel(PersonSummary p) {
  switch (p.role) {
    case 'admin':
      return 'Admin';
    case 'volunteer':
      return 'Volunteer';
    default:
      return 'Getting support';
  }
}

/// A small status line under a name.
String _standing(PersonSummary p) {
  switch (p.role) {
    case 'participant':
      return p.sharing ? 'Sharing location' : 'Not sharing location';
    case 'volunteer':
      if (p.paused) return 'Paused';
      return p.approved ? 'Approved' : 'Waiting for approval';
    default:
      return 'Full access';
  }
}

/// Everyone registered in one group, newest first, with a search box. Tap a
/// person to open their profile.
class PeopleListView extends StatefulWidget {
  final PeopleGroup group;
  const PeopleListView({super.key, required this.group});

  @override
  State<PeopleListView> createState() => _PeopleListViewState();
}

class _PeopleListViewState extends State<PeopleListView> {
  List<PersonSummary>? _people;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final people = await ApiClient.shared.fetchPeople(widget.group.wire);
      if (!mounted) return;
      setState(() {
        _people = people;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is GgcException ? e.message : "Couldn't load the list.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = _people;
    final q = _query.trim().toLowerCase();
    final shown = all == null ? const <PersonSummary>[] : [for (final p in all) if (q.isEmpty || p.name.toLowerCase().contains(q)) p];
    return Scaffold(
      appBar: AppBar(backgroundColor: Brand.background, title: Text(widget.group.title, style: const TextStyle(fontWeight: FontWeight.w800))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          key: const Key('people-list'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            TextField(
              key: const Key('people-search'),
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(hintText: 'Search by name', prefixIcon: Icon(Icons.search_rounded)),
            ),
            const SizedBox(height: 14),
            if (all == null && _error == null) const Padding(padding: EdgeInsets.only(top: 60), child: Center(child: CircularProgressIndicator())),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Column(
                  children: [
                    Text(_error!, key: const Key('people-error'), style: const TextStyle(color: Brand.amber)),
                    const SizedBox(height: 10),
                    OutlinedButton(style: compactOutlined, onPressed: _load, child: const Text('Try again')),
                  ],
                ),
              ),
            if (all != null && all.isEmpty) const Padding(padding: EdgeInsets.only(top: 20), child: Text('No one yet.', key: Key('people-empty'), style: TextStyle(color: Colors.white54))),
            if (all != null && all.isNotEmpty && shown.isEmpty)
              const Padding(padding: EdgeInsets.only(top: 20), child: Text('No one matches that.', key: Key('people-no-match'), style: TextStyle(color: Colors.white54))),
            if (all != null && all.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8, left: 4),
                child: Text(
                  q.isEmpty ? '${all.length} registered' : '${shown.length} of ${all.length}',
                  key: const Key('people-count'),
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ),
            for (final p in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppCard(
                  key: Key('person-${p.userId}'),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PersonDetailView(summary: p))),
                  child: Row(
                    children: [
                      _Initial(name: p.name, role: p.role),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                            const SizedBox(height: 2),
                            Text(
                              p.role == 'participant' ? '${_joined(p.joinedAtLocal)} · ${_standing(p)}' : '${_roleLabel(p)} · ${_standing(p)}',
                              style: const TextStyle(color: Colors.white54, fontSize: 13),
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
      ),
    );
  }
}

class _Initial extends StatelessWidget {
  final String name;
  final String role;
  const _Initial({required this.name, required this.role});

  @override
  Widget build(BuildContext context) {
    final color = role == 'participant' ? Brand.orange : Brand.blue;
    final letter = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.18), shape: BoxShape.circle),
      child: Text(letter, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 18)),
    );
  }
}

/// One person's profile. It loads fresh each time it opens, and the server
/// records every look.
class PersonDetailView extends StatefulWidget {
  final PersonSummary summary;
  const PersonDetailView({super.key, required this.summary});

  @override
  State<PersonDetailView> createState() => _PersonDetailViewState();
}

class _PersonDetailViewState extends State<PersonDetailView> {
  PersonDetail? _person;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final person = await ApiClient.shared.fetchPerson(widget.summary.userId);
      if (!mounted) return;
      setState(() {
        _person = person;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is GgcException ? e.message : "Couldn't load this profile.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _person;
    return Scaffold(
      appBar: AppBar(backgroundColor: Brand.background, title: Text(widget.summary.name, style: const TextStyle(fontWeight: FontWeight.w800))),
      body: ListView(
        key: const Key('person-detail'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          if (p == null && _error == null) const Padding(padding: EdgeInsets.only(top: 80), child: Center(child: CircularProgressIndicator())),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Column(
                children: [
                  Text(_error!, key: const Key('person-error'), style: const TextStyle(color: Brand.amber)),
                  const SizedBox(height: 10),
                  OutlinedButton(style: compactOutlined, onPressed: _load, child: const Text('Try again')),
                ],
              ),
            ),
          if (p != null) ...[
            Row(
              children: [
                _Initial(name: p.name, role: p.role),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
                      Text('${_roleLabel(p)} · ${_joined(p.joinedAtLocal)}', style: const TextStyle(color: Colors.white54)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _Section(title: 'Contact', rows: [
              _Row(Icons.email_outlined, 'Email', p.email, key: const Key('detail-email')),
              _Row(Icons.phone_outlined, 'Phone', p.phone, key: const Key('detail-phone')),
              _Row(Icons.person_outline_rounded, 'Gender', p.gender == null ? null : _genderLabel(p.gender!), key: const Key('detail-gender')),
            ]),
            const SizedBox(height: 14),
            if (p.role == 'participant') ...[
              _Section(title: 'Sharing', rows: [
                _Row(Icons.my_location_rounded, 'Location', p.sharing ? 'On' : 'Off', key: const Key('detail-sharing')),
                if (p.sharing) _Row(Icons.schedule_rounded, 'Last check-in', p.lastCheckInLocal == null ? 'Not yet' : timeAgo(p.lastCheckInLocal!), key: const Key('detail-checkin')),
                _Row(Icons.folder_open_rounded, 'Documents', p.documentStorage ? 'On · ${p.documentsOnFile} on file' : 'Off', key: const Key('detail-documents')),
              ]),
              const SizedBox(height: 14),
              _Section(title: 'Help', rows: [
                _Row(Icons.volunteer_activism_rounded, 'Requests', '${p.helpRequests} asked · ${p.helpRequestsDone} done', key: const Key('detail-help')),
              ]),
            ] else
              _Section(title: p.role == 'admin' ? 'Role' : 'Standing', rows: [
                _Row(Icons.verified_user_outlined, 'Status', _standing(p), key: const Key('detail-status')),
                _Row(Icons.volunteer_activism_rounded, 'Requests helped', '${p.helped}', key: const Key('detail-helped')),
                if (p.role == 'volunteer') _Row(Icons.thumbs_up_down_outlined, 'How it went', '👍 ${p.thumbsUp}   👎 ${p.thumbsDown}', key: const Key('detail-thumbs')),
              ]),
            const SizedBox(height: 18),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.shield_rounded, size: 16, color: Colors.white38),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Only admins can see this. Messages, calendars, documents and locations stay private. Each time a profile is opened it is recorded.',
                    style: TextStyle(color: Colors.white54, fontSize: 12.5, height: 1.4),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

String _genderLabel(String wire) {
  switch (wire) {
    case 'female':
      return 'Female';
    case 'male':
      return 'Male';
    case 'nonbinary':
      return 'Non-binary';
    case 'prefer_not_to_say':
      return 'Prefers not to say';
    default:
      return 'Other';
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<_Row> rows;
  const _Section({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white70)),
          const SizedBox(height: 6),
          ...rows,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  const _Row(this.icon, this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.white54),
          const SizedBox(width: 12),
          SizedBox(width: 120, child: Text(label, style: const TextStyle(color: Colors.white54))),
          Expanded(
            child: value == null
                ? const Text('Not given', style: TextStyle(color: Colors.white30))
                : SelectableText(value!, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
