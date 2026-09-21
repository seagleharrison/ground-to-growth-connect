import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../util/launch.dart';
import '../widgets/ui.dart';

/// Organization-wide numbers, for admin accounts only (the tab isn't shown to
/// anyone else, and the server refuses the request for anyone else too).
/// Everything here is a count — no names, locations or documents.
class AnalyticsView extends StatefulWidget {
  const AnalyticsView({super.key});

  @override
  State<AnalyticsView> createState() => _AnalyticsViewState();
}

class _AnalyticsViewState extends State<AnalyticsView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().refreshAnalytics();
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final a = app.analytics;

    return LargeTitlePage(
      title: 'Analytics',
      onRefresh: app.refreshAnalytics,
      children: [
        if (a == null && app.analyticsError == null)
          const Padding(
            padding: EdgeInsets.only(top: 80),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (a == null && app.analyticsError != null)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(app.analyticsError!, key: const Key('analytics-error'), style: const TextStyle(color: Brand.amber, height: 1.4)),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: app.refreshAnalytics, child: const Text('Try again')),
              ],
            ),
          ),
        if (a != null) ...[
          FadeSlideIn(child: _Overview(a: a)),
          const SizedBox(height: 16),
          FadeSlideIn(delay: const Duration(milliseconds: 80), child: _SharingCard(a: a)),
          const SizedBox(height: 16),
          FadeSlideIn(delay: const Duration(milliseconds: 160), child: _DocumentsCard(a: a)),
          const SizedBox(height: 16),
          FadeSlideIn(delay: const Duration(milliseconds: 240), child: _DailyCard(a: a)),
          if (app.sourceReport != null) ...[
            const SizedBox(height: 16),
            FadeSlideIn(delay: const Duration(milliseconds: 280), child: _SourcesCard(report: app.sourceReport!)),
          ],
          const SizedBox(height: 16),
          const FadeSlideIn(delay: Duration(milliseconds: 320), child: _PrivacyNote()),
        ],
      ],
    );
  }
}

class _Overview extends StatelessWidget {
  final Analytics a;
  const _Overview({required this.a});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _BigNumber(key: const Key('stat-participants'), value: a.participants, label: 'People we serve', color: Brand.orange)),
        const SizedBox(width: 12),
        Expanded(child: _BigNumber(key: const Key('stat-staff'), value: a.staff, label: 'Staff & volunteers', color: Brand.blue)),
      ],
    );
  }
}

class _BigNumber extends StatelessWidget {
  final int value;
  final String label;
  final Color color;
  const _BigNumber({super.key, required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(end: value.toDouble()),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => Text(
              '${v.round()}',
              style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: color, height: 1),
            ),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// A labeled bar showing "part of a whole".
class _ProgressRow extends StatelessWidget {
  final String label;
  final int value;
  final int total;
  final Color color;
  const _ProgressRow({required this.label, required this.value, required this.total, required this.color});

  @override
  Widget build(BuildContext context) {
    final fraction = total == 0 ? 0.0 : (value / total).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 15))),
              Text(total == 0 ? '$value' : '$value of $total', style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: fraction),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 10,
                backgroundColor: Brand.surfaceHigh,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SharingCard extends StatelessWidget {
  final Analytics a;
  const _SharingCard({required this.a});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Location sharing', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          _ProgressRow(label: 'Sharing their location', value: a.participantsSharing, total: a.participants, color: Brand.green),
          _ProgressRow(label: 'Checked in today', value: a.activeLast24Hours, total: a.participants, color: Brand.orange),
          _ProgressRow(label: 'Checked in this week', value: a.activeLast7Days, total: a.participants, color: Brand.blue),
        ],
      ),
    );
  }
}

class _DocumentsCard extends StatelessWidget {
  final Analytics a;
  const _DocumentsCard({required this.a});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Documents', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          _ProgressRow(label: 'Using document storage', value: a.participantsUsingStorage, total: a.participants, color: Brand.blue),
          _ProgressRow(label: 'ID, Social Security card and birth certificate all on file', value: a.participantsWithAllThree, total: a.participants, color: Brand.green),
          const SizedBox(height: 4),
          Text('${a.documentsStored} documents stored in all', style: const TextStyle(color: Colors.white54, fontSize: 13)),
        ],
      ),
    );
  }
}

class _DailyCard extends StatelessWidget {
  final Analytics a;
  const _DailyCard({required this.a});

  @override
  Widget build(BuildContext context) {
    final maxCheckIns = a.daily.fold<int>(1, (m, d) => d.checkIns > m ? d.checkIns : m);
    final newPeople = a.daily.fold<int>(0, (s, d) => s + d.signups);
    final checkIns = a.daily.fold<int>(0, (s, d) => s + d.checkIns);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Last ${a.daily.length} days', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('$checkIns check-ins · $newPeople new ${newPeople == 1 ? 'account' : 'accounts'}',
              key: const Key('daily-summary'), style: const TextStyle(color: Colors.white60)),
          const SizedBox(height: 18),
          SizedBox(
            height: 110,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final (i, d) in a.daily.indexed)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(end: d.checkIns / maxCheckIns),
                        duration: Duration(milliseconds: 500 + i * 30),
                        curve: Curves.easeOutCubic,
                        builder: (context, v, _) => Container(
                          height: 4 + 106 * v,
                          decoration: BoxDecoration(
                            color: i == a.daily.length - 1 ? Brand.orange : Brand.orange.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_shortDate(a.daily.first.date), style: const TextStyle(color: Colors.white38, fontSize: 12)),
              const Text('Today', style: TextStyle(color: Colors.white38, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  static String _shortDate(String iso) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final parts = iso.split('-');
    return '${months[int.parse(parts[1]) - 1]} ${int.parse(parts[2])}';
  }
}

/// Official pages the Resources tab points to. The server re-checks them every
/// day; anything that vanished or changed is listed here so someone can make
/// sure the guide still matches, then tap "Still right".
class _SourcesCard extends StatelessWidget {
  final SourceReport report;
  const _SourcesCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final items = report.needsAttention;
    return AppCard(
      key: const Key('sources-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Resources info', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            items.isEmpty
                ? 'All ${report.total} official pages we point people to look unchanged.'
                : '${items.length} of ${report.total} official pages need a look.',
            key: const Key('sources-summary'),
            style: TextStyle(color: items.isEmpty ? Brand.green : Brand.amber, height: 1.35),
          ),
          for (final a in items) ...[
            const SizedBox(height: 14),
            const Divider(height: 1, color: Colors.white12),
            const SizedBox(height: 14),
            Text(Uri.tryParse(a.url)?.host ?? a.url, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(a.reason, style: const TextStyle(color: Colors.white60, fontSize: 13.5, height: 1.4)),
            const SizedBox(height: 4),
            Text(a.url, style: const TextStyle(color: Colors.white38, fontSize: 11.5)),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(
                  key: Key('open-source-${a.url}'),
                  onPressed: () => Launch.link(context, a.url),
                  child: const Text('Open page'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  key: Key('reviewed-${a.url}'),
                  onPressed: () => context.read<AppState>().markSourceReviewed(a.url),
                  child: const Text('Still right', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          const Text(
            'To change what people see, update the guide on the server. It reaches every phone the next time they open Resources.',
            style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.shield_rounded, size: 16, color: Colors.white38),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'Only admins can see this page. It shows totals only — never names, locations or documents.',
            style: TextStyle(color: Colors.white54, fontSize: 12.5, height: 1.4),
          ),
        ),
      ],
    );
  }
}
