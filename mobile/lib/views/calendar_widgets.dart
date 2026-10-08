import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../util/calendar_items.dart';
import '../widgets/ui.dart';

/// A filled, colour-coded block for one calendar item, like Google Calendar's
/// event chips: your own appointments in orange, shelter events in blue.
class EventTile extends StatelessWidget {
  final CalendarItem item;
  final VoidCallback onTap;
  const EventTile({super.key, required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final i = item;
    final sub = [if ((i.location ?? '').isNotEmpty) i.location!].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: i.color,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              key: Key(
                i.isAppointment ? 'appointment-${i.id}' : 'event-${i.id}',
              ),
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            i.title,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: i.onColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            itemTimeLabel(i),
                            style: TextStyle(
                              fontSize: 13,
                              color: i.onColor.withValues(alpha: 0.8),
                            ),
                          ),
                          if (sub.isNotEmpty)
                            Text(
                              sub,
                              style: TextStyle(
                                fontSize: 13,
                                color: i.onColor.withValues(alpha: 0.8),
                                height: 1.3,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Icon(
                      i.isAppointment
                          ? Icons.person_rounded
                          : Icons.groups_rounded,
                      size: 18,
                      color: i.onColor.withValues(alpha: 0.7),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (i.helper != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 2),
              child: Pill(
                key: Key('helper-${i.id}'),
                label: '${i.helper} is taking you',
                color: Brand.green,
                icon: Icons.volunteer_activism_rounded,
              ),
            ),
        ],
      ),
    );
  }
}

/// A circle behind a date number: filled for today, outlined for the selected day.
class DayNumber extends StatelessWidget {
  final DateTime day;
  final bool isToday;
  final bool isSelected;
  final bool dim;
  final double size;
  final double fontSize;
  const DayNumber({
    super.key,
    required this.day,
    required this.isToday,
    this.isSelected = false,
    this.dim = false,
    this.size = 28,
    this.fontSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    final color = isToday ? Brand.orange : null;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: isSelected && !isToday
            ? Border.all(color: Brand.orange, width: 1.6)
            : null,
      ),
      child: Text(
        '${day.day}',
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: isToday || isSelected ? FontWeight.w800 : FontWeight.w600,
          color: isToday
              ? const Color(0xFF3A1D00)
              : (dim ? Colors.white30 : Colors.white),
        ),
      ),
    );
  }
}
