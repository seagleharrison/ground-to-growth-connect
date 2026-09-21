import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

/// The informed-consent step for sharing location. The full disclosure text is
/// shown and must be agreed to; nothing is shared until the person taps agree.
Future<void> showSharingConsentSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _ConsentSheet(),
  );
}

class _ConsentSheet extends StatelessWidget {
  const _ConsentSheet();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final disclosure = app.disclosure;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      builder: (context, controller) => Column(
        children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(3))),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 12),
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(gradient: Brand.heroGradient, borderRadius: BorderRadius.circular(20)),
                  child: const Icon(Icons.location_on_rounded, size: 34, color: Color(0xFF3A1D00)),
                ),
                const SizedBox(height: 18),
                Text('Share your location?', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                const Text(
                  'This helps our outreach team find you and bring help to you. It is your choice, and you can stop any time.',
                  style: TextStyle(fontSize: 16, height: 1.4, color: Colors.white70),
                ),
                const SizedBox(height: 22),
                const _Point(Icons.grid_on_rounded, 'Blurred for your privacy', 'Your spot is rounded to about 200 meters before it leaves your phone.'),
                const _Point(Icons.schedule_rounded, 'Every 15 minutes', 'Just a quick check-in, not constant tracking.'),
                const _Point(Icons.groups_rounded, 'Only Ground to Growth staff', 'Outreach staff and volunteers who signed in with our code.'),
                const _Point(Icons.pause_circle_rounded, 'Stop any time', 'Turn it off and it stops right away. Your choice never affects the help you get.'),
                const SizedBox(height: 14),
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: AppCard(
                    padding: EdgeInsets.zero,
                    child: ExpansionTile(
                      shape: const Border(),
                      collapsedShape: const Border(),
                      title: Text(
                        disclosure == null ? 'Full disclosure' : 'Full disclosure · v${disclosure.version}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                      children: [
                        Text(
                          disclosure?.text ?? 'Loading…',
                          style: const TextStyle(fontSize: 12.5, height: 1.45, color: Colors.white60),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GradientButton(
                    label: 'I understand — turn on sharing',
                    icon: Icons.check_rounded,
                    loading: app.isLoading,
                    onPressed: disclosure == null
                        ? null
                        : () async {
                            final navigator = Navigator.of(context);
                            await context.read<AppState>().grantConsent();
                            navigator.pop();
                          },
                  ),
                  TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Not now')),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Point extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _Point(this.icon, this.title, this.body);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: Brand.orange.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: Brand.orange, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 2),
                Text(body, style: const TextStyle(color: Colors.white60, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The record of every time sharing was turned on or off.
Future<void> showSharingHistorySheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) {
      final records = context.watch<AppState>().consentHistory;
      return ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 32),
        children: [
          Text('Sharing history', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          const Text('Every time you turned sharing on or off.', style: TextStyle(color: Colors.white60)),
          const SizedBox(height: 16),
          if (records.isEmpty) const Text('Nothing yet.', style: TextStyle(color: Colors.white54)),
          for (final r in records)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                r.granted ? Icons.check_circle_rounded : Icons.pause_circle_rounded,
                color: r.granted ? Brand.green : Brand.amber,
              ),
              title: Text(r.granted ? 'Turned on' : 'Turned off', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                r.createdAt.length >= 19 ? r.createdAt.substring(0, 19).replaceAll('T', ' ') : r.createdAt,
                style: const TextStyle(color: Colors.white54),
              ),
            ),
        ],
      );
    },
  );
}
