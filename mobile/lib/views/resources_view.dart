import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/help_content.dart';
import '../nav.dart';
import '../services/resources_controller.dart';
import '../util/time.dart';
import '../theme/app_theme.dart';
import '../util/launch.dart';
import '../widgets/ui.dart';

/// Shows [builder] once the Resources content is available, loading it (from
/// the last saved copy, or the copy bundled in the app) if nothing has yet.
class _ContentGate extends StatefulWidget {
  final Widget Function(BuildContext context, HelpContent content) builder;
  final String title;
  const _ContentGate({required this.title, required this.builder});

  @override
  State<_ContentGate> createState() => _ContentGateState();
}

class _ContentGateState extends State<_ContentGate> {
  @override
  void initState() {
    super.initState();
    context.read<AppState>().resources.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    final content = context.watch<AppState>().resources.content;
    if (content == null) {
      return LargeTitlePage(
        title: widget.title,
        children: const [Padding(padding: EdgeInsets.only(top: 80), child: Center(child: CircularProgressIndicator()))],
      );
    }
    return widget.builder(context, content);
  }
}

/// "Sep 21, 2026" from "2026-09-21".
String _prettyDate(String iso) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final parts = iso.split('-');
  if (parts.length != 3) return iso;
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (month == null || month < 1 || month > 12 || day == null) return iso;
  return '${months[month - 1]} $day, ${parts[0]}';
}

/// The Resources tab: places near you, how to replace lost papers, and what
/// health coverage and benefits are out there. Plain language, current
/// (re-checked with the server every time it opens), and every phone number
/// and link can be tapped.
class ResourcesView extends StatefulWidget {
  const ResourcesView({super.key});

  @override
  State<ResourcesView> createState() => _ResourcesViewState();
}

class _ResourcesViewState extends State<ResourcesView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final r = context.read<AppState>().resources;
      r.ensureLoaded();
      r.refresh();
      r.locate(); // only uses location the person already allowed
    });
  }

  Future<void> _refresh() async {
    final r = context.read<AppState>().resources;
    await Future.wait([r.refresh(), r.locate()]);
  }

  @override
  Widget build(BuildContext context) {
    final r = context.watch<AppState>().resources;
    final content = r.content;

    return LargeTitlePage(
      title: 'Resources',
      onRefresh: _refresh,
      children: [
        const FadeSlideIn(child: _UrgentHelpCard()),
        const SizedBox(height: 12),
        _FreshnessRow(controller: r),
        const SizedBox(height: 16),
        FadeSlideIn(
          delay: const Duration(milliseconds: 80),
          child: _EntryCard(
            key: const Key('open-replace-guides'),
            icon: Icons.find_replace_rounded,
            title: 'Replace a lost document',
            subtitle: 'Birth certificate, Social Security card, ID, discharge papers. Where to go and what to bring.',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DocumentGuidesView())),
          ),
        ),
        const SizedBox(height: 12),
        FadeSlideIn(
          delay: const Duration(milliseconds: 160),
          child: _EntryCard(
            key: const Key('open-benefits'),
            icon: Icons.health_and_safety_rounded,
            title: 'Health & benefits',
            subtitle: 'Medicaid, clinics, VA care, food help, and how to apply.',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BenefitsView())),
          ),
        ),
        const SizedBox(height: 24),
        if (content != null) _NearbySection(controller: r),
        const SizedBox(height: 20),
        if (content != null) FadeSlideIn(delay: const Duration(milliseconds: 240), child: _CheckedNote(updatedAt: content.updatedAt)),
      ],
    );
  }
}

/// "Updated Sep 21, 2026 · Checked just now" — so it's always clear how current the info is.
class _FreshnessRow extends StatelessWidget {
  final ResourcesController controller;
  const _FreshnessRow({required this.controller});

  @override
  Widget build(BuildContext context) {
    final content = controller.content;
    final String status;
    if (controller.isRefreshing) {
      status = 'Checking for updates…';
    } else if (controller.offline) {
      status = 'Can\'t reach the server. Showing the last saved info.';
    } else if (controller.lastCheckedAt != null) {
      status = 'Checked ${timeAgo(controller.lastCheckedAt!)}';
    } else {
      status = '';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          if (controller.isRefreshing)
            const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54))
          else
            Icon(controller.offline ? Icons.cloud_off_rounded : Icons.update_rounded, size: 14, color: controller.offline ? Brand.amber : Colors.white38),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              [if (content != null) 'Info updated ${_prettyDate(content.updatedAt)}', if (status.isNotEmpty) status].join(' · '),
              key: const Key('freshness-row'),
              style: TextStyle(color: controller.offline ? Brand.amber : Colors.white54, fontSize: 12.5, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}

class _UrgentHelpCard extends StatelessWidget {
  const _UrgentHelpCard();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: const Color(0xFF2A1A18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.emergency_rounded, color: Brand.red),
              SizedBox(width: 10),
              Text('Need help right now?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'In an emergency, call 911. If you\'re in crisis or having thoughts of hurting yourself, call or text 988. It\'s free and always open.',
            style: TextStyle(color: Colors.white70, height: 1.4),
          ),
          const SizedBox(height: 14),
          const Row(
            children: [
              Expanded(child: PhoneButton(phone: emergencyPhone, prominent: true)),
              SizedBox(width: 10),
              Expanded(child: PhoneButton(phone: crisisPhone)),
            ],
          ),
        ],
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _EntryCard({super.key, required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: Brand.orange.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(16)),
            child: Icon(icon, color: Brand.orange, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(color: Colors.white60, height: 1.35, fontSize: 14)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Colors.white38),
        ],
      ),
    );
  }
}

class _CheckedNote extends StatelessWidget {
  final String updatedAt;
  const _CheckedNote({required this.updatedAt});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline_rounded, size: 16, color: Colors.white38),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'This is general information, reviewed ${_prettyDate(updatedAt)}. Prices and rules change, so confirm with the office before you go. Your outreach worker can help.',
            key: const Key('checked-note'),
            style: const TextStyle(color: Colors.white54, fontSize: 12.5, height: 1.4),
          ),
        ),
      ],
    );
  }
}

// MARK: - Near you

class _NearbySection extends StatelessWidget {
  final ResourcesController controller;
  const _NearbySection({required this.controller});

  @override
  Widget build(BuildContext context) {
    final places = controller.nearby;
    if (places.isEmpty) return const SizedBox.shrink();
    final status = controller.nearbyStatus;
    final notice = controller.regionNotice;
    final knowsWhere = controller.position != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(knowsWhere ? 'Near you' : 'Places in Savannah'),
        if (!knowsWhere && status != NearbyStatus.ready) ...[
          _LocationPrompt(controller: controller),
          const SizedBox(height: 12),
        ],
        if (notice != RegionNotice.none) ...[
          _RegionNoticeCard(notice: notice, nearestMeters: places.first.distanceMeters),
          const SizedBox(height: 12),
        ],
        for (final p in places) ...[
          _PlaceCard(item: p),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _LocationPrompt extends StatelessWidget {
  final ResourcesController controller;
  const _LocationPrompt({required this.controller});

  @override
  Widget build(BuildContext context) {
    final denied = controller.nearbyStatus == NearbyStatus.denied;
    final unavailable = controller.nearbyStatus == NearbyStatus.unavailable;
    return AppCard(
      key: const Key('location-prompt'),
      color: const Color(0xFF17232B),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.near_me_rounded, color: Brand.blue),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  denied ? 'Location is off' : unavailable ? 'Couldn\'t find you just now' : 'See what\'s closest to you',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            denied
                ? 'Turn on location for this app in your phone\'s Settings to sort these by distance.'
                : 'We\'ll sort these by how far they are from you. Your location stays on your phone for this. It isn\'t sent to us or anyone else.',
            style: const TextStyle(color: Colors.white70, height: 1.4),
          ),
          if (!denied) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              key: const Key('use-my-location'),
              onPressed: () => controller.locate(ask: true),
              child: const Text('Use my location'),
            ),
          ],
        ],
      ),
    );
  }
}

class _RegionNoticeCard extends StatelessWidget {
  final RegionNotice notice;
  final double? nearestMeters;
  const _RegionNoticeCard({required this.notice, required this.nearestMeters});

  @override
  Widget build(BuildContext context) {
    final miles = nearestMeters == null ? null : (nearestMeters! / 1609.344).round();
    final text = switch (notice) {
      RegionNotice.outsideGeorgia =>
        'You seem to be outside Georgia. The places and Georgia programs here may not apply where you are. Social Security, Medicare, VA care, 911 and 988 work anywhere in the U.S. For local help with food, shelter and more, call 211.',
      RegionNotice.farFromSavannah =>
        'The places below are in Savannah, about $miles miles from you. For help near you, call 211, or ask an outreach worker.',
      RegionNotice.none => '',
    };
    return AppCard(
      key: const Key('region-notice'),
      color: const Color(0xFF2B2417),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.public_rounded, color: Brand.amber),
              const SizedBox(width: 12),
              Expanded(child: Text(text, style: const TextStyle(color: Colors.white70, height: 1.4))),
            ],
          ),
          const SizedBox(height: 12),
          const PhoneButton(phone: localHelpPhone),
        ],
      ),
    );
  }
}

class _PlaceCard extends StatelessWidget {
  final NearbyPlace item;
  const _PlaceCard({required this.item});

  static IconData _icon(String category) => switch (category) {
        'id' => Icons.contact_page_outlined,
        'records' => Icons.description_outlined,
        'health' => Icons.local_hospital_outlined,
        'shelter' => Icons.home_work_outlined,
        'veterans' => Icons.military_tech_outlined,
        _ => Icons.place_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final p = item.place;
    final d = item.distanceMeters;
    return AppCard(
      key: Key('place-${p.id}'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_icon(p.category), color: Brand.orange, size: 26),
              const SizedBox(width: 12),
              Expanded(child: Text(p.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, height: 1.25))),
              if (d != null) ...[
                const SizedBox(width: 8),
                Pill(key: Key('distance-${p.id}'), label: formatMiles(d), color: Brand.blue),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(p.address, style: const TextStyle(color: Colors.white70, height: 1.35)),
          if (p.hours != null) ...[
            const SizedBox(height: 4),
            Text(p.hours!, style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.35)),
          ],
          const SizedBox(height: 8),
          Text(p.note, style: const TextStyle(color: Colors.white60, fontSize: 14, height: 1.4)),
          const SizedBox(height: 12),
          PhoneButton(phone: p.phone),
          const SizedBox(height: 10),
          PressableScale(
            onTap: () => Launch.link(context, Launch.directionsUrl(p.lat, p.lng)),
            child: Container(
              key: Key('directions-${p.id}'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(color: Brand.surfaceHigh, borderRadius: BorderRadius.circular(16)),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.directions_rounded, size: 20),
                  SizedBox(width: 8),
                  Text('Directions', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text('Checked ${_prettyDate(p.verifiedOn)}. Call ahead to confirm hours.', style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ],
      ),
    );
  }
}

/// "0.4 mi", "12 mi".
String formatMiles(double meters) {
  final miles = meters / 1609.344;
  if (miles < 0.1) return 'under 0.1 mi';
  return '${miles.toStringAsFixed(miles < 10 ? 1 : 0)} mi';
}

/// A big tappable phone number.
class PhoneButton extends StatelessWidget {
  final HelpPhone phone;
  final bool prominent;
  const PhoneButton({super.key, required this.phone, this.prominent = false});

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: () => Launch.call(context, phone.dial, phone.display),
      child: Container(
        key: Key('call-${phone.dial}'),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: prominent ? Brand.red : Brand.surfaceHigh,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.call_rounded, size: 20, color: prominent ? const Color(0xFF3A0E09) : Colors.white),
            const SizedBox(width: 8),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Call ${phone.display}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: prominent ? const Color(0xFF3A0E09) : Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// MARK: - Lists

/// "Replace a lost document": which to start with, then one card per document.
class DocumentGuidesView extends StatelessWidget {
  const DocumentGuidesView({super.key});

  @override
  Widget build(BuildContext context) {
    return _ContentGate(title: 'Replace a document', builder: _build);
  }

  static Widget _build(BuildContext context, HelpContent content) {
    return LargeTitlePage(
      title: 'Replace a document',
      children: [
        AppCard(
          color: const Color(0xFF17232B),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lightbulb_outline_rounded, color: Brand.blue),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Start with your birth certificate, then your Social Security card, then your photo ID. Each one usually needs the one before it.',
                  key: Key('guides-order-tip'),
                  style: TextStyle(color: Colors.white70, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        for (final topic in content.documentGuides) ...[
          _TopicTile(topic: topic),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class BenefitsView extends StatelessWidget {
  const BenefitsView({super.key});

  @override
  Widget build(BuildContext context) {
    return _ContentGate(title: 'Health & benefits', builder: _build);
  }

  static Widget _build(BuildContext context, HelpContent content) {
    return LargeTitlePage(
      title: 'Health & benefits',
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 0, 4, 16),
          child: Text(
            'Ways to get care and support. Tap one to see who can get it and how to apply.',
            style: TextStyle(color: Colors.white60, fontSize: 15, height: 1.4),
          ),
        ),
        for (final topic in content.benefitPrograms) ...[
          _TopicTile(topic: topic),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 6),
        _CheckedNote(updatedAt: content.updatedAt),
      ],
    );
  }
}

class _TopicTile extends StatelessWidget {
  final HelpTopic topic;
  const _TopicTile({required this.topic});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      key: Key('topic-${topic.id}'),
      padding: const EdgeInsets.all(16),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => HelpTopicView(topic: topic))),
      child: Row(
        children: [
          Icon(topic.icon, color: Brand.orange, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(topic.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(topic.summary, style: const TextStyle(color: Colors.white60, fontSize: 14, height: 1.35)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Colors.white38),
        ],
      ),
    );
  }
}

// MARK: - One topic

class HelpTopicView extends StatelessWidget {
  final HelpTopic topic;
  const HelpTopicView({super.key, required this.topic});

  @override
  Widget build(BuildContext context) {
    final related = topic.relatedDocument;
    return LargeTitlePage(
      title: topic.title,
      children: [
        Text(topic.summary, style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.4)),
        const SizedBox(height: 18),
        for (final section in topic.sections) ...[
          _SectionCard(section: section),
          const SizedBox(height: 14),
        ],
        if (topic.phones.isNotEmpty) ...[
          const SectionLabel('Call'),
          for (final phone in topic.phones) ...[
            _LabeledPhone(phone: phone),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 4),
        ],
        if (topic.links.isNotEmpty) ...[
          const SectionLabel('Official links'),
          for (final link in topic.links) ...[
            _LinkTile(link: link),
            const SizedBox(height: 10),
          ],
        ],
        if (related != null) ...[
          const SizedBox(height: 10),
          GradientButton(
            key: const Key('add-to-vault'),
            label: 'Got it? Add it to your documents',
            icon: Icons.account_balance_wallet_rounded,
            onPressed: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
              context.read<TabNav>().go(AppTab.documents);
            },
          ),
        ],
        const SizedBox(height: 16),
        Builder(builder: (context) {
          final updated = context.watch<AppState>().resources.content?.updatedAt;
          return updated == null ? const SizedBox.shrink() : _CheckedNote(updatedAt: updated);
        }),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final HelpSection section;
  const _SectionCard({required this.section});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(section.heading, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          for (final (i, item) in section.items.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (section.numbered)
                    Container(
                      width: 26,
                      height: 26,
                      margin: const EdgeInsets.only(right: 12, top: 1),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: Brand.orange.withValues(alpha: 0.18), shape: BoxShape.circle),
                      child: Text('${i + 1}', style: const TextStyle(color: Brand.orange, fontWeight: FontWeight.w800, fontSize: 13)),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.only(right: 12, top: 7),
                      child: Icon(Icons.circle, size: 6, color: Brand.orange),
                    ),
                  Expanded(child: Text(item, style: const TextStyle(color: Colors.white70, height: 1.45, fontSize: 15.5))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _LabeledPhone extends StatelessWidget {
  final HelpPhone phone;
  const _LabeledPhone({required this.phone});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(phone.label, style: const TextStyle(color: Colors.white60, fontSize: 13)),
        ),
        PhoneButton(phone: phone),
      ],
    );
  }
}

class _LinkTile extends StatelessWidget {
  final HelpLink link;
  const _LinkTile({required this.link});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      key: Key('link-${link.url}'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      onTap: () => Launch.link(context, link.url),
      child: Row(
        children: [
          const Icon(Icons.open_in_new_rounded, size: 20, color: Brand.blue),
          const SizedBox(width: 12),
          Expanded(child: Text(link.label, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.3))),
        ],
      ),
    );
  }
}
