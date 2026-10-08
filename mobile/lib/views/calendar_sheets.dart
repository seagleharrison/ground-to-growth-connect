import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme/app_theme.dart';
import '../util/calendar_items.dart';
import '../util/time.dart';
import '../widgets/ui.dart';

/// The date and time of the next whole hour: where a brand-new appointment starts.
DateTime nextHour([DateTime? from]) {
  final now = from ?? DateTime.now();
  return DateTime(now.year, now.month, now.day, now.hour + 1);
}

Future<void> showAppointmentSheet(
  BuildContext context, {
  CalendarItem? existing,
  DateTime? startingAt,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => AppointmentSheet(existing: existing, startingAt: startingAt),
);

Future<void> showEventDetailSheet(BuildContext context, CalendarItem item) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EventDetailSheet(item: item),
    );

/// Opens whatever was tapped: your own appointment to edit, or a shelter event to read.
Future<void> openCalendarItem(BuildContext context, CalendarItem item) =>
    item.isAppointment
    ? showAppointmentSheet(context, existing: item)
    : showEventDetailSheet(context, item);

class _SheetFrame extends StatelessWidget {
  final Widget child;
  const _SheetFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Material(
        color: Brand.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.92,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EventDetailSheet extends StatelessWidget {
  final CalendarItem item;
  const _EventDetailSheet({required this.item});

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      child: Column(
        key: const Key('event-detail'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: item.color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Shelter & program event',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            item.title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          _DetailRow(
            icon: Icons.schedule_rounded,
            text: '${fullDate(item.start)} · ${itemTimeLabel(item)}',
          ),
          if ((item.location ?? '').isNotEmpty)
            _DetailRow(icon: Icons.place_outlined, text: item.location!),
          if ((item.notes ?? '').isNotEmpty)
            _DetailRow(icon: Icons.notes_rounded, text: item.notes!),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _DetailRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.white54),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 15, height: 1.35)),
        ),
      ],
    ),
  );
}

/// Add or edit one of the person's own private appointments.
class AppointmentSheet extends StatefulWidget {
  final CalendarItem? existing;
  final DateTime? startingAt;
  const AppointmentSheet({super.key, this.existing, this.startingAt});

  @override
  State<AppointmentSheet> createState() => _AppointmentSheetState();
}

class _AppointmentSheetState extends State<AppointmentSheet> {
  late final TextEditingController _title;
  late final TextEditingController _notes;
  late final TextEditingController _location;
  late DateTime _start;
  late DateTime _end;
  late bool _allDay;
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
    _allDay = existing?.allDay ?? false;
    _start = existing?.start ?? widget.startingAt ?? nextHour();
    _end = existing?.end ?? _start.add(const Duration(hours: 1));
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<DateTime?> _pickDate(DateTime initial) => showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2020),
    lastDate: DateTime.now().add(const Duration(days: 1095)),
  );

  Future<void> _pickStartDate() async {
    final picked = await _pickDate(_start);
    if (picked == null) return;
    final length = _end.difference(_start);
    setState(() {
      _start = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _start.hour,
        _start.minute,
      );
      _end = _start.add(length);
    });
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_start),
    );
    if (picked == null) return;
    final length = _end.difference(_start);
    setState(() {
      _start = DateTime(
        _start.year,
        _start.month,
        _start.day,
        picked.hour,
        picked.minute,
      );
      _end = _start.add(length);
    });
  }

  Future<void> _pickEndDate() async {
    final picked = await _pickDate(_end);
    if (picked == null) return;
    setState(
      () => _end = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _end.hour,
        _end.minute,
      ),
    );
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_end),
    );
    if (picked == null) return;
    setState(
      () => _end = DateTime(
        _end.year,
        _end.month,
        _end.day,
        picked.hour,
        picked.minute,
      ),
    );
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Give it a title first.');
      return;
    }
    if (!_allDay && !_end.isAfter(_start)) {
      setState(() => _error = 'The end has to be after the start.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final calendar = context.read<AppState>().calendar;
    final existing = widget.existing;
    final start = _allDay ? dateOnly(_start) : _start;
    final end = _allDay ? null : _end;
    final error = existing == null
        ? await calendar.addAppointment(
            title: title,
            notes: _notes.text,
            location: _location.text,
            startsAt: start,
            endsAt: end,
            allDay: _allDay,
          )
        : await calendar.editAppointment(
            existing.id,
            title: title,
            notes: _notes.text,
            location: _location.text,
            startsAt: start,
            endsAt: end,
            clearEnd: end == null,
            allDay: _allDay,
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
    final existing = widget.existing;
    if (existing == null) return;
    setState(() => _deleting = true);
    final error = await context.read<AppState>().calendar.removeAppointment(
      existing.id,
    );
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
    return _SheetFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            editing ? 'Edit appointment' : 'New appointment',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 18),
          TextField(
            key: const Key('appointment-title-field'),
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Title',
              prefixIcon: Icon(Icons.event_rounded),
            ),
          ),
          const SizedBox(height: 6),
          SwitchListTile(
            key: const Key('appointment-allday-switch'),
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            title: const Text('All day'),
            secondary: const Icon(
              Icons.wb_sunny_outlined,
              color: Colors.white54,
            ),
            value: _allDay,
            onChanged: (v) => setState(() => _allDay = v),
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('appointment-date-button'),
                  onPressed: _pickStartDate,
                  icon: const Icon(Icons.calendar_today_rounded, size: 18),
                  label: Text(shortDate(_start)),
                ),
              ),
              if (!_allDay) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('appointment-time-button'),
                    onPressed: _pickStartTime,
                    icon: const Icon(Icons.schedule_rounded, size: 18),
                    label: Text(clockTime(_start)),
                  ),
                ),
              ],
            ],
          ),
          if (!_allDay) ...[
            const Padding(
              padding: EdgeInsets.only(top: 12, bottom: 6, left: 4),
              child: Text(
                'Ends',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('appointment-end-date-button'),
                    onPressed: _pickEndDate,
                    icon: const Icon(Icons.calendar_today_rounded, size: 18),
                    label: Text(shortDate(_end)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('appointment-end-time-button'),
                    onPressed: _pickEndTime,
                    icon: const Icon(Icons.schedule_rounded, size: 18),
                    label: Text(clockTime(_end)),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          TextField(
            key: const Key('appointment-location-field'),
            controller: _location,
            decoration: const InputDecoration(
              labelText: 'Location (optional)',
              prefixIcon: Icon(Icons.place_outlined),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            key: const Key('appointment-notes-field'),
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              prefixIcon: Icon(Icons.notes_rounded),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              key: const Key('appointment-error'),
              style: const TextStyle(color: Brand.red, fontSize: 14),
            ),
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
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Delete'),
            ),
          ],
        ],
      ),
    );
  }
}
