/// Three missed 15-minute check-ins in a row is a real gap, not just normal
/// timing jitter or a slow network — worth flagging rather than staying
/// silent about it (a stale check-in looks identical to a fresh one
/// otherwise, whatever actually caused the gap — the app got force-quit, the
/// phone died, no signal).
const staleCheckInThreshold = Duration(minutes: 45);

bool isStaleCheckIn(DateTime when, {DateTime? now}) => (now ?? DateTime.now()).difference(when) > staleCheckInThreshold;

/// "4 min ago", "Yesterday", "Sep 12" — how people actually say it.
String timeAgo(DateTime when, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final diff = current.difference(when);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  if (diff.inDays == 1) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays} days ago';
  return shortDate(when);
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String shortDate(DateTime d) => '${_months[d.month - 1]} ${d.day}';

String clockTime(DateTime d) {
  final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final minute = d.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${d.hour < 12 ? 'AM' : 'PM'}';
}

/// "Good morning" / "Good afternoon" / "Good evening".
String greeting(DateTime now) {
  if (now.hour < 12) return 'Good morning';
  if (now.hour < 17) return 'Good afternoon';
  return 'Good evening';
}

String firstName(String fullName) {
  final parts = fullName.trim().split(RegExp(r'\s+'));
  return parts.isEmpty || parts.first.isEmpty ? 'there' : parts.first;
}

const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// "Sunday, Sep 21"
String fullDate(DateTime d) => '${_weekdays[d.weekday - 1]}, ${shortDate(d)}';
