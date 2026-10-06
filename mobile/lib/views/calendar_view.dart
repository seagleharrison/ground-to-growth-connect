import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/calendar_content.dart';
import '../models/models.dart';
import '../services/help_controller.dart';
import '../theme/app_theme.dart';
import '../util/time.dart';
import '../widgets/ui.dart';

/// One thing on the Calendar: either a shelter/program event (read-only,
/// server content) or the person's own private appointment (editable).
class _AgendaEntry {
  final DateTime when;
  final String title;
  final String? subtitle;
  final Appointment? appointment; // non-null only for a personal appointment
  final String? helper; // first name of a volunteer taking them there

  _AgendaEntry({required this.when, required this.title, this.subtitle, this.appointment, this.helper});

  bool get isAppointment => appointment != null;
}

/// The participant's Calendar tab: shelter/program events and their own
/// private appointments, in one chronological list, day by day.
class CalendarView extends StatefulWidget {
  const CalendarView({super.key});

  @override
  State<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<CalendarView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final calendar = context.read<AppState>().calendar;
      calendar.ensureEventsLoaded().then((_) {
        if (mounted) calendar.refreshEvents();
      });
      calendar.refreshAppointments();
      context.read<AppState>().help.refreshMine();
    });
  }

  Future<void> _refresh() async {
    final calendar = context.read<AppState>().calendar;
    await Future.wait([calendar.refreshEvents(), calendar.refreshAppointments()]);
  }

  List<_AgendaEntry> _upcoming(CalendarEventsContent? content, List<Appointment> appointments, HelpController help) {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final entries = <_AgendaEntry>[
      for (final e in content?.events ?? const <CalendarEventInfo>[])
        _AgendaEntry(when: e.startsAtLocal, title: e.title, subtitle: e.description ?? e.location),
      for (final a in appointments) _AgendaEntry(when: a.startsAtLocal, title: a.title, subtitle: a.location, appointment: a, helper: help.helperForAppointment(a.id)),
    ]..removeWhere((e) => e.when.isBefore(startOfToday));
    entries.sort((a, b) => a.when.compareTo(b.when));
    return entries;
  }

  Future<void> _openAppointmentSheet(BuildContext context, {Appointment? existing}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AppointmentSheet(existing: existing),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final calendar = app.calendar;
    final entries = _upcoming(calendar.content, calendar.appointments, app.help);

    final groups = <(DateTime, List<_AgendaEntry>)>[];
    for (final entry in entries) {
      final day = DateTime(entry.when.year, entry.when.month, entry.when.day);
      if (groups.isNotEmpty && groups.last.$1 == day) {
        groups.last.$2.add(entry);
      } else {
        groups.add((day, [entry]));
      }
    }

    return LargeTitlePage(
      title: 'Calendar',
      onRefresh: _refresh,
      actions: [
        IconButton(
          key: const Key('add-appointment'),
          onPressed: () => _openAppointmentSheet(context),
          icon: const Icon(Icons.add_circle_rounded, size: 28),
        ),
      ],
      children: [
        if (calendar.content == null)
          const Padding(padding: EdgeInsets.only(top: 80), child: Center(child: CircularProgressIndicator())),
        if (calendar.content != null && calendar.eventsOffline)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text("Couldn't check for new events — showing what we last had.", style: TextStyle(color: Brand.amber, fontSize: 13)),
          ),
        if (calendar.appointmentsError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(calendar.appointmentsError!, style: const TextStyle(color: Brand.red, fontSize: 13)),
          ),
        if (calendar.content != null && groups.isEmpty)
          const AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Nothing coming up', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                SizedBox(height: 6),
                Text(
                  'Tap the + above to add your own appointment. Shelter and program events will show up here too.',
                  style: TextStyle(color: Colors.white70, height: 1.4),
                ),
              ],
            ),
          ),
        for (final (day, dayEntries) in groups) ...[
          Padding(
            padding: const EdgeInsets.only(top: 18, bottom: 8, left: 4),
            child: Text(fullDate(day), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Colors.white70)),
          ),
          for (final entry in dayEntries)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppCard(
                key: entry.isAppointment ? Key('appointment-${entry.appointment!.id}') : null,
                onTap: entry.isAppointment ? () => _openAppointmentSheet(context, existing: entry.appointment) : null,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: (entry.isAppointment ? Brand.orange : Brand.blue).withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        entry.isAppointment ? Icons.person_rounded : Icons.groups_rounded,
                        size: 18,
                        color: entry.isAppointment ? Brand.orange : Brand.blue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                          const SizedBox(height: 2),
                          Text(clockTime(entry.when), style: const TextStyle(color: Colors.white54, fontSize: 13)),
                          if (entry.helper != null) ...[
                            const SizedBox(height: 6),
                            Pill(
                              key: Key('helper-${entry.appointment!.id}'),
                              label: '${entry.helper} is taking you',
                              color: Brand.green,
                              icon: Icons.volunteer_activism_rounded,
                            ),
                          ],
                          if ((entry.subtitle ?? '').isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(entry.subtitle!, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.3)),
                          ],
                        ],
                      ),
                    ),
                    if (entry.isAppointment) const Icon(Icons.chevron_right_rounded, color: Colors.white38),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _AppointmentSheet extends StatefulWidget {
  final Appointment? existing;
  const _AppointmentSheet({this.existing});

  @override
  State<_AppointmentSheet> createState() => _AppointmentSheetState();
}

class _AppointmentSheetState extends State<_AppointmentSheet> {
  late final TextEditingController _title;
  late final TextEditingController _notes;
  late final TextEditingController _location;
  late DateTime _when;
  bool _saving = false;
  bool _deleting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _title = TextEditingController(text: existing?.title ?? '');
    _notes = TextEditingController(text: existing?.notes ?? '');
    _location = TextEditingController(text: existing?.location ?? '');
    final now = DateTime.now();
    _when = existing?.startsAtLocal ?? DateTime(now.year, now.month, now.day, now.hour + 1);
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked != null) {
      setState(() => _when = DateTime(picked.year, picked.month, picked.day, _when.hour, _when.minute));
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_when));
    if (picked != null) {
      setState(() => _when = DateTime(_when.year, _when.month, _when.day, picked.hour, picked.minute));
    }
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = "Give it a title first.");
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final calendar = context.read<AppState>().calendar;
    final existing = widget.existing;
    final error = existing == null
        ? await calendar.addAppointment(title: title, notes: _notes.text, location: _location.text, startsAt: _when)
        : await calendar.editAppointment(existing.id, title: title, notes: _notes.text, location: _location.text, startsAt: _when);
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
    final existing = widget.existing;
    if (existing == null) return;
    setState(() => _deleting = true);
    final error = await context.read<AppState>().calendar.removeAppointment(existing.id);
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _deleting = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        decoration: const BoxDecoration(
          color: Brand.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 18),
            Text(editing ? 'Edit appointment' : 'New appointment', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 18),
            TextField(
              key: const Key('appointment-title-field'),
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title', prefixIcon: Icon(Icons.event_rounded)),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('appointment-date-button'),
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today_rounded, size: 18),
                    label: Text(shortDate(_when)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('appointment-time-button'),
                    onPressed: _pickTime,
                    icon: const Icon(Icons.schedule_rounded, size: 18),
                    label: Text(clockTime(_when)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              key: const Key('appointment-location-field'),
              controller: _location,
              decoration: const InputDecoration(labelText: 'Location (optional)', prefixIcon: Icon(Icons.place_outlined)),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const Key('appointment-notes-field'),
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notes (optional)', prefixIcon: Icon(Icons.notes_rounded)),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Brand.red, fontSize: 14)),
            ],
            const SizedBox(height: 20),
            GradientButton(
              key: const Key('save-appointment'),
              label: editing ? 'Save changes' : 'Add appointment',
              loading: _saving,
              onPressed: _saving || _deleting ? null : _save,
            ),
            if (editing) ...[
              const SizedBox(height: 10),
              OutlinedButton(
                key: const Key('delete-appointment'),
                onPressed: _saving || _deleting ? null : _delete,
                style: OutlinedButton.styleFrom(foregroundColor: Brand.red),
                child: _deleting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Delete'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
