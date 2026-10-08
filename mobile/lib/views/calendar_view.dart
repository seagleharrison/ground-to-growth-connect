import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../services/secure_storage_service.dart';
import '../theme/app_theme.dart';
import '../util/calendar_items.dart';
import '../widgets/ui.dart';
import 'calendar_month.dart';
import 'calendar_schedule.dart';
import 'calendar_sheets.dart';
import 'calendar_time_grid.dart';

enum CalendarMode {
  schedule('Schedule', Icons.view_agenda_outlined),
  day('Day', Icons.view_day_outlined),
  week('Week', Icons.view_week_outlined),
  month('Month', Icons.calendar_view_month_outlined);

  final String label;
  final IconData icon;
  const CalendarMode(this.label, this.icon);
}

/// The Calendar tab, modelled on Google Calendar: switch between Schedule,
/// Day, Week and Month, jump back with Today, and add with the + button.
/// It shows shelter/program events and the person's own private appointments.
class CalendarView extends StatefulWidget {
  const CalendarView({super.key});

  @override
  State<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<CalendarView> {
  CalendarMode _mode = CalendarMode.month;
  late DateTime _focused = dateOnly(DateTime.now());

  @override
  void initState() {
    super.initState();
    SecureStorageService.loadCalendarMode()
        .then((saved) {
          final mode = CalendarMode.values
              .where((m) => m.name == saved)
              .firstOrNull;
          if (mode != null && mounted) setState(() => _mode = mode);
        })
        .catchError((_) {});
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
    await Future.wait([
      calendar.refreshEvents(),
      calendar.refreshAppointments(),
    ]);
  }

  void _setMode(CalendarMode mode) {
    setState(() => _mode = mode);
    SecureStorageService.saveCalendarMode(mode.name).catchError((_) {});
  }

  void _focus(DateTime day) => setState(() => _focused = dateOnly(day));

  void _add([DateTime? startingAt]) {
    // A tapped day (no time) starts mid-morning; a tapped time slot keeps its time.
    final start = startingAt == null
        ? nextHour()
        : (startingAt.hour == 0 && startingAt.minute == 0
              ? DateTime(startingAt.year, startingAt.month, startingAt.day, 9)
              : startingAt);
    showAppointmentSheet(context, startingAt: start);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final calendar = app.calendar;
    final items = buildCalendarItems(
      calendar.content,
      calendar.appointments,
      helperFor: app.help.helperForAppointment,
    );
    final today = dateOnly(DateTime.now());

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                _TopBar(
                  title: monthTitle(_focused),
                  mode: _mode,
                  onMode: _setMode,
                  onToday: () => _focus(today),
                  todayShown: sameDay(_focused, today),
                ),
                if (calendar.content != null && calendar.eventsOffline)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      "Couldn't check for new events — showing what we last had.",
                      style: TextStyle(color: Brand.amber, fontSize: 13),
                    ),
                  ),
                if (calendar.appointmentsError != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      calendar.appointmentsError!,
                      style: const TextStyle(color: Brand.red, fontSize: 13),
                    ),
                  ),
                Expanded(
                  child: switch (_mode) {
                    CalendarMode.schedule => CalendarScheduleView(
                      items: items,
                      loading: calendar.content == null,
                      onOpen: (i) => openCalendarItem(context, i),
                      onRefresh: _refresh,
                    ),
                    CalendarMode.month => CalendarMonthView(
                      items: items,
                      focused: _focused,
                      onFocus: _focus,
                      onOpen: (i) => openCalendarItem(context, i),
                      onAdd: _add,
                      onRefresh: _refresh,
                    ),
                    CalendarMode.week || CalendarMode.day => CalendarTimeGrid(
                      key: ValueKey(_mode),
                      items: items,
                      focused: _focused,
                      days: _mode == CalendarMode.week ? 7 : 1,
                      onFocus: _focus,
                      onOpenDay: (d) {
                        _focus(d);
                        if (_mode == CalendarMode.week) {
                          _setMode(CalendarMode.day);
                        }
                      },
                      onOpen: (i) => openCalendarItem(context, i),
                      onAdd: _add,
                    ),
                  },
                ),
              ],
            ),
            Positioned(
              right: 18,
              bottom: kNavBarClearance - 6,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: FloatingActionButton(
                  key: const Key('add-appointment'),
                  elevation: 0,
                  focusElevation: 0,
                  hoverElevation: 0,
                  highlightElevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  backgroundColor: Brand.orange,
                  foregroundColor: const Color(0xFF3A1D00),
                  onPressed: () =>
                      _add(_mode == CalendarMode.schedule ? null : _focused),
                  child: const Icon(Icons.add_rounded, size: 30),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String title;
  final CalendarMode mode;
  final ValueChanged<CalendarMode> onMode;
  final VoidCallback onToday;
  final bool todayShown;
  const _TopBar({
    required this.title,
    required this.mode,
    required this.onMode,
    required this.onToday,
    required this.todayShown,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              key: const Key('calendar-title'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
              ),
            ),
          ),
          IconButton(
            key: const Key('calendar-today'),
            tooltip: 'Today',
            onPressed: todayShown ? null : onToday,
            icon: Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(
                  color: todayShown ? Colors.white24 : Colors.white70,
                  width: 1.6,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${DateTime.now().day}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: todayShown ? Colors.white38 : Colors.white,
                ),
              ),
            ),
          ),
          PopupMenuButton<CalendarMode>(
            key: const Key('calendar-view-menu'),
            tooltip: 'Change view',
            color: Brand.surfaceHigh,
            onSelected: onMode,
            icon: Icon(mode.icon),
            itemBuilder: (context) => [
              for (final m in CalendarMode.values)
                PopupMenuItem(
                  key: Key('view-${m.name}'),
                  value: m,
                  child: Row(
                    children: [
                      Icon(
                        m.icon,
                        size: 20,
                        color: m == mode ? Brand.orange : Colors.white70,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        m.label,
                        style: TextStyle(
                          fontWeight: m == mode
                              ? FontWeight.w800
                              : FontWeight.w500,
                          color: m == mode ? Brand.orange : Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
