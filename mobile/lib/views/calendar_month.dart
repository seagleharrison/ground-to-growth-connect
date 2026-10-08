import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../util/calendar_items.dart';
import '../widgets/ui.dart';
import 'calendar_widgets.dart';

/// The month grid with a dot-and-chip summary in every day, and the selected
/// day's items listed underneath. Swipe sideways to change month.
class CalendarMonthView extends StatefulWidget {
  final List<CalendarItem> items;
  final DateTime focused;
  final ValueChanged<DateTime> onFocus;
  final ValueChanged<CalendarItem> onOpen;
  final ValueChanged<DateTime> onAdd;
  final Future<void> Function() onRefresh;
  const CalendarMonthView({
    super.key,
    required this.items,
    required this.focused,
    required this.onFocus,
    required this.onOpen,
    required this.onAdd,
    required this.onRefresh,
  });

  @override
  State<CalendarMonthView> createState() => _CalendarMonthViewState();
}

class _CalendarMonthViewState extends State<CalendarMonthView> {
  static const _mid = 1200;
  late final DateTime _base = monthOf(widget.focused);
  late final PageController _pages = PageController(
    initialPage: _pageFor(widget.focused),
  );
  bool _jumping = false;

  int _pageFor(DateTime d) =>
      _mid + (d.year - _base.year) * 12 + (d.month - _base.month);

  DateTime _monthFor(int page) =>
      DateTime(_base.year, _base.month + (page - _mid));

  @override
  void didUpdateWidget(covariant CalendarMonthView old) {
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
    _pages.dispose();
    super.dispose();
  }

  void _onPage(int page) {
    if (_jumping) return;
    final month = _monthFor(page);
    final today = DateTime.now();
    final next = month.year == today.year && month.month == today.month
        ? dateOnly(today)
        : DateTime(month.year, month.month);
    widget.onFocus(next);
  }

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(DateTime.now());
    final dayItems = itemsOnDay(widget.items, widget.focused);
    return LayoutBuilder(
      builder: (context, box) {
        final gridHeight = (box.maxHeight * 0.46).clamp(240.0, 6 * 64.0);
        return RefreshIndicator(
          onRefresh: widget.onRefresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: [
                    for (final d in weekdayLetters)
                      Expanded(
                        child: Center(
                          child: Text(
                            d,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: gridHeight,
                child: PageView.builder(
                  key: const Key('month-pages'),
                  controller: _pages,
                  onPageChanged: _onPage,
                  itemBuilder: (context, page) => _MonthGrid(
                    month: _monthFor(page),
                    items: widget.items,
                    today: today,
                    selected: widget.focused,
                    gridHeight: gridHeight,
                    onSelect: widget.onFocus,
                  ),
                ),
              ),
              const Divider(height: 24, color: Brand.outline),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        dayTitle(widget.focused),
                        key: const Key('selected-day-title'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      key: const Key('month-add-here'),
                      onPressed: () => widget.onAdd(widget.focused),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, kNavBarClearance),
                child: dayItems.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          'Nothing planned for this day.',
                          key: Key('day-empty'),
                          style: TextStyle(color: Colors.white54),
                        ),
                      )
                    : Column(
                        children: [
                          for (final i in dayItems)
                            EventTile(item: i, onTap: () => widget.onOpen(i)),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MonthGrid extends StatelessWidget {
  final DateTime month;
  final List<CalendarItem> items;
  final DateTime today;
  final DateTime selected;
  final double gridHeight;
  final ValueChanged<DateTime> onSelect;
  const _MonthGrid({
    required this.month,
    required this.items,
    required this.today,
    required this.selected,
    required this.gridHeight,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final days = monthGridDays(month);
    // A 5-week month and a 6-week month both fill the same space.
    final rowHeight = gridHeight / (days.length ~/ 7);
    // Room for chips under the date number; if they don't all fit, the last
    // slot becomes a "+N" instead.
    final maxChips = ((rowHeight - 32) / 14).floor().clamp(0, 4);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        children: [
          for (var w = 0; w < days.length ~/ 7; w++)
            SizedBox(
              height: rowHeight,
              child: Row(
                children: [
                  for (var d = 0; d < 7; d++)
                    Expanded(
                      child: _DayCell(
                        day: days[w * 7 + d],
                        inMonth: days[w * 7 + d].month == month.month,
                        isToday: sameDay(days[w * 7 + d], today),
                        isSelected: sameDay(days[w * 7 + d], selected),
                        items: itemsOnDay(items, days[w * 7 + d]),
                        maxChips: maxChips,
                        onTap: () => onSelect(days[w * 7 + d]),
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

class _DayCell extends StatelessWidget {
  final DateTime day;
  final bool inMonth;
  final bool isToday;
  final bool isSelected;
  final List<CalendarItem> items;
  final int maxChips;
  final VoidCallback onTap;
  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.isSelected,
    required this.items,
    required this.maxChips,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final overflow = maxChips > 0 && items.length > maxChips;
    final shown = items.take(overflow ? maxChips - 1 : maxChips).toList();
    final more = items.length - shown.length;
    final key =
        '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    return InkWell(
      key: Key('month-day-$key'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(1.5, 2, 1.5, 0),
        child: ClipRect(
          child: Column(
            children: [
              DayNumber(
                day: day,
                isToday: isToday,
                isSelected: isSelected,
                dim: !inMonth,
                size: 26,
                fontSize: 13,
              ),
              const SizedBox(height: 2),
              for (final i in shown)
                Container(
                  width: double.infinity,
                  height: 12,
                  margin: const EdgeInsets.only(bottom: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: i.color.withValues(alpha: inMonth ? 1 : 0.4),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    i.title,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: i.onColor,
                      height: 1.1,
                    ),
                  ),
                ),
              if (overflow)
                Text(
                  '+$more',
                  style: const TextStyle(
                    fontSize: 9,
                    height: 1.1,
                    color: Colors.white54,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              if (maxChips == 0 && items.isNotEmpty)
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Brand.orange,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
