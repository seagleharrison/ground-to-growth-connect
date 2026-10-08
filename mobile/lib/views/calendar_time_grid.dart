import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../util/calendar_items.dart';
import '../util/time.dart';
import '../widgets/ui.dart';
import 'calendar_widgets.dart';

const double _hourHeight = 56;
const double _gutter = 50;

/// Day and Week: hours down the side, one column per day, items as blocks
/// sized by how long they are (overlapping ones side by side), a red line at
/// the current time, and a tap on an empty slot starts a new appointment there.
class CalendarTimeGrid extends StatefulWidget {
  final List<CalendarItem> items;
  final DateTime focused;
  final int days; // 1 = Day, 7 = Week
  final ValueChanged<DateTime> onFocus;
  final ValueChanged<DateTime> onOpenDay; // tap a date in the header
  final ValueChanged<CalendarItem> onOpen;
  final ValueChanged<DateTime> onAdd;
  const CalendarTimeGrid({
    super.key,
    required this.items,
    required this.focused,
    required this.days,
    required this.onFocus,
    required this.onOpenDay,
    required this.onOpen,
    required this.onAdd,
  });

  @override
  State<CalendarTimeGrid> createState() => _CalendarTimeGridState();
}

class _CalendarTimeGridState extends State<CalendarTimeGrid> {
  static const _mid = 1200;
  late final DateTime _base = _pageStart(widget.focused);
  late final PageController _pages = PageController(
    initialPage: _pageFor(widget.focused),
  );
  late final ScrollController _scroll;
  bool _jumping = false;
  Timer? _tick;

  bool get _week => widget.days == 7;
  int get _step => widget.days;

  DateTime _pageStart(DateTime d) => _week ? startOfWeek(d) : dateOnly(d);

  int _pageFor(DateTime d) => _mid + daysBetween(_base, _pageStart(d)) ~/ _step;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    // Start a little above "now" when it's in view, otherwise at the morning.
    final hour =
        (sameDay(widget.focused, now) ||
            _week && _pageStart(widget.focused) == _pageStart(now))
        ? (now.hour - 1)
        : 7;
    _scroll = ScrollController(
      initialScrollOffset: (hour.clamp(0, 17)) * _hourHeight,
    );
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant CalendarTimeGrid old) {
    super.didUpdateWidget(old);
    final target = _pageFor(widget.focused);
    if (_pages.hasClients && (_pages.page?.round() ?? target) != target) {
      _jumping = true;
      _pages
          .animateToPage(
            target,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          )
          .whenComplete(() => _jumping = false);
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _pages.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onPage(int page) {
    if (_jumping) return;
    final start = addDays(_base, (page - _mid) * _step);
    final offset = _week
        ? daysBetween(startOfWeek(widget.focused), dateOnly(widget.focused))
        : 0;
    widget.onFocus(addDays(start, offset));
  }

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(DateTime.now());
    final start = _pageStart(widget.focused);
    final visible = [for (var i = 0; i < widget.days; i++) addDays(start, i)];
    final allDay = [
      for (final d in visible)
        [
          for (final i in itemsOnDay(widget.items, d))
            if (i.showsAsAllDay) i,
        ],
    ];
    final anyAllDay = allDay.any((l) => l.isNotEmpty);

    return Column(
      children: [
        _Header(
          days: visible,
          today: today,
          selected: widget.focused,
          week: _week,
          onTap: widget.onOpenDay,
        ),
        if (anyAllDay) _AllDayStrip(columns: allDay, onOpen: widget.onOpen),
        const Divider(height: 1, color: Brand.outline),
        Expanded(
          child: SingleChildScrollView(
            key: const Key('time-grid-scroll'),
            controller: _scroll,
            padding: const EdgeInsets.only(bottom: kNavBarClearance),
            child: SizedBox(
              height: 24 * _hourHeight,
              child: Row(
                children: [
                  const _HourLabels(),
                  Expanded(
                    child: PageView.builder(
                      key: const Key('time-grid-pages'),
                      controller: _pages,
                      onPageChanged: _onPage,
                      itemBuilder: (context, page) {
                        final pageStart = addDays(_base, (page - _mid) * _step);
                        return Row(
                          children: [
                            for (var i = 0; i < widget.days; i++)
                              Expanded(
                                child: _DayColumn(
                                  day: addDays(pageStart, i),
                                  items: widget.items,
                                  isToday: sameDay(
                                    addDays(pageStart, i),
                                    today,
                                  ),
                                  onOpen: widget.onOpen,
                                  onAdd: widget.onAdd,
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final List<DateTime> days;
  final DateTime today;
  final DateTime selected;
  final bool week;
  final ValueChanged<DateTime> onTap;
  const _Header({
    required this.days,
    required this.today,
    required this.selected,
    required this.week,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 6),
      child: Row(
        children: [
          const SizedBox(width: _gutter),
          for (final d in days)
            Expanded(
              child: InkWell(
                key: Key('grid-head-${d.year}-${d.month}-${d.day}'),
                onTap: () => onTap(d),
                child: Column(
                  children: [
                    Text(
                      weekdayShort[d.weekday % 7].toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: sameDay(d, today)
                            ? Brand.orange
                            : Colors.white54,
                      ),
                    ),
                    const SizedBox(height: 2),
                    DayNumber(
                      day: d,
                      isToday: sameDay(d, today),
                      isSelected: week && sameDay(d, selected),
                      size: 32,
                      fontSize: 16,
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

class _AllDayStrip extends StatelessWidget {
  final List<List<CalendarItem>> columns;
  final ValueChanged<CalendarItem> onOpen;
  const _AllDayStrip({required this.columns, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(
            width: _gutter,
            child: Padding(
              padding: EdgeInsets.only(top: 3, left: 6),
              child: Text(
                'all-day',
                style: TextStyle(fontSize: 10, color: Colors.white38),
              ),
            ),
          ),
          for (final col in columns)
            Expanded(
              child: Column(
                children: [
                  for (final i in col.take(2))
                    GestureDetector(
                      onTap: () => onOpen(i),
                      child: Container(
                        width: double.infinity,
                        margin: const EdgeInsets.fromLTRB(1, 0, 1, 2),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: i.color,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          i.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: i.onColor,
                          ),
                        ),
                      ),
                    ),
                  if (col.length > 2)
                    Text(
                      '+${col.length - 2}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white54,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _HourLabels extends StatelessWidget {
  const _HourLabels();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _gutter,
      child: Stack(
        children: [
          for (var h = 1; h < 24; h++)
            Positioned(
              top: h * _hourHeight - 7,
              left: 0,
              right: 6,
              child: Text(
                clockTime(DateTime(2000, 1, 1, h)).replaceAll(':00', ''),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 10, color: Colors.white38),
              ),
            ),
        ],
      ),
    );
  }
}

class _DayColumn extends StatelessWidget {
  final DateTime day;
  final List<CalendarItem> items;
  final bool isToday;
  final ValueChanged<CalendarItem> onOpen;
  final ValueChanged<DateTime> onAdd;
  const _DayColumn({
    required this.day,
    required this.items,
    required this.isToday,
    required this.onOpen,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final placed = layoutDay(itemsOnDay(items, day), day);
    final now = DateTime.now();
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        return GestureDetector(
          key: Key('grid-col-${day.year}-${day.month}-${day.day}'),
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            final minutes = (details.localPosition.dy / _hourHeight * 60)
                .floor();
            final rounded = (minutes ~/ 30) * 30;
            onAdd(
              DateTime(
                day.year,
                day.month,
                day.day,
                rounded ~/ 60,
                rounded % 60,
              ),
            );
          },
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(child: CustomPaint(painter: _GridLines())),
              for (final p in placed)
                Positioned(
                  top: p.startMin * _hourHeight / 60 + 1,
                  height: (p.endMin - p.startMin) * _hourHeight / 60 - 2,
                  left: width / p.lanes * p.lane + 1,
                  width: width / p.lanes - 2,
                  child: GestureDetector(
                    key: Key('block-${p.item.id}-${day.day}'),
                    onTap: () => onOpen(p.item),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(4, 2, 3, 2),
                      clipBehavior: Clip.hardEdge,
                      decoration: BoxDecoration(
                        color: p.item.color,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      // Narrow columns (a week on a phone) show one line cut with "…"
                      // instead of a word broken letter by letter.
                      child: width / p.lanes < 64
                          ? Text(
                              p.item.title,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: p.item.onColor,
                                height: 1.15,
                              ),
                            )
                          : Text(
                              p.endMin - p.startMin >= 45
                                  ? '${p.item.title}\n${clockTime(p.item.start)}'
                                  : p.item.title,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: p.item.onColor,
                                height: 1.15,
                              ),
                            ),
                    ),
                  ),
                ),
              if (isToday)
                Positioned(
                  key: const Key('now-line'),
                  top: (now.hour * 60 + now.minute) * _hourHeight / 60 - 4,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Brand.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Expanded(child: Container(height: 2, color: Brand.red)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _GridLines extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = Brand.outline
      ..strokeWidth = 1;
    for (var h = 0; h <= 24; h++) {
      final y = h * _hourHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    canvas.drawLine(Offset.zero, Offset(0, size.height), line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
