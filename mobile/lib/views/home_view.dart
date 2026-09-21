import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/models.dart';
import '../nav.dart';
import '../theme/app_theme.dart';
import '../util/time.dart';
import '../widgets/ui.dart';
import 'documents_view.dart' show missingCoreDocuments, walletColors, walletGreen, walletIcon;
import 'edit_profile_view.dart';
import 'profile_avatar.dart';
import 'sharing_sheets.dart';

/// Where someone lands: a friendly greeting, whether location sharing is on,
/// and a short "getting started" list that shows what's done and what's next.
class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().refreshDocumentConsent();
    });
  }

  Future<void> _refresh() async {
    final app = context.read<AppState>();
    await app.refreshSession();
    await app.refreshDocumentConsent();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final user = app.user;
    if (user == null) return const SizedBox.shrink();

    return LargeTitlePage(
      title: '${greeting(DateTime.now())}, ${firstName(user.name)}',
      onRefresh: _refresh,
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 14),
          child: GestureDetector(
            onTap: () => context.read<TabNav>().go(AppTab.me),
            child: ProfileAvatar(bytes: app.profilePictureBytes, name: user.name, radius: 19),
          ),
        ),
      ],
      children: [
        FadeSlideIn(child: _SharingCard(app: app)),
        const SizedBox(height: 16),
        FadeSlideIn(delay: const Duration(milliseconds: 90), child: _GettingStartedCard(app: app)),
        const SizedBox(height: 16),
        FadeSlideIn(delay: const Duration(milliseconds: 180), child: _DocumentsPeek(app: app)),
        const SizedBox(height: 16),
        const FadeSlideIn(delay: Duration(milliseconds: 270), child: _PrivacyPromise()),
      ],
    );
  }
}

// MARK: - Sharing

class _SharingCard extends StatelessWidget {
  final AppState app;
  const _SharingCard({required this.app});

  @override
  Widget build(BuildContext context) {
    final on = app.consent?.granted == true;
    final tracker = app.locationTracker;

    return ListenableBuilder(
      listenable: tracker,
      builder: (context, _) {
        final last = tracker.lastReportAt;
        return AppCard(
          gradient: on
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF17301E), Brand.surface],
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (on)
                    const PulseDot(color: Brand.green)
                  else
                    Container(
                      width: 34,
                      height: 34,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(color: Brand.surfaceHigh, borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.location_off_rounded, size: 19, color: Colors.white54),
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      on ? 'Sharing your location' : 'Location sharing is off',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ),
                  Pill(label: on ? 'On' : 'Off', color: on ? Brand.green : Colors.white54),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                on
                    ? 'Our outreach team can see roughly where you are, updated every 15 minutes.'
                    : 'Turn it on so our outreach team can find you and bring help to you.',
                style: const TextStyle(color: Colors.white70, height: 1.4, fontSize: 15),
              ),
              if (on) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.schedule_rounded, size: 16, color: Colors.white54),
                    const SizedBox(width: 6),
                    Text(
                      last == null ? 'Waiting for your first check-in…' : 'Last check-in ${timeAgo(last)}',
                      style: const TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                  ],
                ),
                if (tracker.lastError != null) ...[
                  const SizedBox(height: 8),
                  Text(tracker.lastError!, style: const TextStyle(color: Brand.amber, fontSize: 13)),
                ],
              ],
              const SizedBox(height: 16),
              if (on)
                OutlinedButton(
                  onPressed: app.isLoading ? null : () => context.read<AppState>().revokeConsent(),
                  child: const Text('Pause sharing'),
                )
              else
                GradientButton(
                  label: 'Turn on sharing',
                  icon: Icons.location_on_rounded,
                  onPressed: () => showSharingConsentSheet(context),
                ),
              if (app.consentHistory.isNotEmpty)
                Align(
                  alignment: Alignment.center,
                  child: TextButton(
                    onPressed: () => showSharingHistorySheet(context),
                    child: const Text('See sharing history'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// MARK: - Getting started

class _GettingStartedCard extends StatelessWidget {
  final AppState app;
  const _GettingStartedCard({required this.app});

  @override
  Widget build(BuildContext context) {
    final sharingDone = app.consent?.granted == true;
    final docsGranted = app.documentConsent?.granted == true;
    final docsDone = docsGranted && missingCoreDocuments(app.documents).isEmpty;
    final photoDone = app.user?.hasProfilePicture == true;
    final done = [sharingDone, docsDone, photoDone].where((d) => d).length;

    if (done == 3) {
      return AppCard(
        color: const Color(0xFF14261A),
        child: Row(
          children: [
            const Icon(Icons.verified_rounded, color: Brand.green, size: 30),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text("You're all set", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  SizedBox(height: 2),
                  Text('Everything is set up. Thank you.', style: TextStyle(color: Colors.white70)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 54,
                height: 54,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(end: done / 3),
                        duration: const Duration(milliseconds: 700),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, _) => CircularProgressIndicator(
                          value: value,
                          strokeWidth: 6,
                          strokeCap: StrokeCap.round,
                          backgroundColor: Brand.surfaceHigh,
                          color: Brand.orange,
                        ),
                      ),
                    ),
                    Text('$done/3', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Getting started', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    SizedBox(height: 2),
                    Text('Three quick things to set up.', style: TextStyle(color: Colors.white60)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _StepRow(
            icon: Icons.location_on_rounded,
            title: 'Share your location',
            subtitle: sharingDone ? 'On' : 'So we can find you',
            done: sharingDone,
            onTap: sharingDone ? null : () => showSharingConsentSheet(context),
          ),
          _StepRow(
            icon: Icons.account_balance_wallet_rounded,
            title: 'Add your documents',
            subtitle: docsGranted
                ? '${3 - missingCoreDocuments(app.documents).length} of 3 on file'
                : 'ID, Social Security card, birth certificate',
            done: docsDone,
            onTap: docsDone ? null : () => context.read<TabNav>().go(AppTab.documents),
          ),
          _StepRow(
            icon: Icons.photo_camera_rounded,
            title: 'Add a profile photo',
            subtitle: photoDone ? 'Added' : 'Helps us recognize you',
            done: photoDone,
            onTap: photoDone
                ? null
                : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EditProfileView())),
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool done;
  final VoidCallback? onTap;

  const _StepRow({required this.icon, required this.title, required this.subtitle, required this.done, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? walletGreen : Colors.transparent,
                border: done ? null : Border.all(color: Colors.white24, width: 2),
              ),
              child: done ? const Icon(Icons.check_rounded, size: 20, color: Colors.white) : Icon(icon, size: 17, color: Colors.white54),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: done ? Colors.white54 : Colors.white,
                      decoration: done ? TextDecoration.lineThrough : null,
                      decorationColor: Colors.white38,
                    ),
                  ),
                  Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 13)),
                ],
              ),
            ),
            if (!done) const Icon(Icons.chevron_right_rounded, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}

// MARK: - Documents peek

class _DocumentsPeek extends StatelessWidget {
  final AppState app;
  const _DocumentsPeek({required this.app});

  @override
  Widget build(BuildContext context) {
    final granted = app.documentConsent?.granted == true;
    final missing = missingCoreDocuments(app.documents);

    return AppCard(
      onTap: () => context.read<TabNav>().go(AppTab.documents),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Text('Your documents', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
              Text(
                granted ? '${3 - missing.length} of 3 on file' : 'Not started',
                style: TextStyle(color: granted && missing.isEmpty ? walletGreen : Colors.white54, fontSize: 13),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white38),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            granted
                ? 'Safe, encrypted and always with you.'
                : 'Keep copies of your important papers safe, even if the originals get lost.',
            style: const TextStyle(color: Colors.white60, height: 1.35),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final type in DocumentType.coreChecklist)
                Expanded(child: _MiniCard(type: type, onFile: granted && !missing.contains(type))),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniCard extends StatelessWidget {
  final DocumentType type;
  final bool onFile;
  const _MiniCard({required this.type, required this.onFile});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 74,
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(colors: walletColors(type), begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Stack(
        children: [
          Icon(walletIcon(type), color: Colors.white, size: 22),
          Align(
            alignment: Alignment.topRight,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: onFile ? walletGreen : Colors.transparent,
                border: onFile ? null : Border.all(color: Colors.white54, width: 1.6),
              ),
              child: onFile ? const Icon(Icons.check_rounded, size: 14, color: Colors.white) : null,
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Text(
              switch (type) {
                DocumentType.governmentId => 'ID',
                DocumentType.socialSecurityCard => 'SSN',
                DocumentType.birthCertificate => 'Birth',
                DocumentType.other => 'Other',
              },
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// MARK: - Privacy promise

class _PrivacyPromise extends StatelessWidget {
  const _PrivacyPromise();

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Our promise to you', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          SizedBox(height: 12),
          _Promise(Icons.lock_rounded, 'Only you can open your documents. Staff can’t.'),
          _Promise(Icons.grid_on_rounded, 'Your location is blurred to about 200 meters.'),
          _Promise(Icons.delete_outline_rounded, 'Delete everything any time from the Me tab.'),
        ],
      ),
    );
  }
}

class _Promise extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Promise(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Brand.orange),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white70, height: 1.35))),
        ],
      ),
    );
  }
}
