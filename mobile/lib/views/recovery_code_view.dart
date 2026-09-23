import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

/// Shown once, right after a recovery code is issued — at sign-up, or after
/// generating a fresh one from Settings. There's no password on this app, so
/// this code is the only way back into the account from a new phone, or after
/// a changed number. It can't be shown again once dismissed.
class RecoveryCodeView extends StatefulWidget {
  const RecoveryCodeView({super.key});

  @override
  State<RecoveryCodeView> createState() => _RecoveryCodeViewState();
}

class _RecoveryCodeViewState extends State<RecoveryCodeView> {
  bool _copied = false;

  Future<void> _copy(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final code = context.watch<AppState>().pendingRecoveryCode;
    // The moment it's acknowledged elsewhere (or there's nothing pending),
    // there's nothing to show — RootView switches away on the next build.
    if (code == null) return const Scaffold(body: SizedBox.shrink());

    return PopScope(
      canPop: false, // must be explicitly acknowledged, not swiped/backed away from
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(gradient: Brand.heroGradient, borderRadius: BorderRadius.circular(20)),
                      child: const Icon(Icons.key_rounded, size: 34, color: Color(0xFF3A1D00)),
                    ),
                    const SizedBox(height: 18),
                    Text('Save your recovery code', style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    const Text(
                      "There's no password on this app. If you lose your phone or change your number, "
                      'this code is the only way to get back into your account and your documents.',
                      style: TextStyle(fontSize: 16, height: 1.4, color: Colors.white70),
                    ),
                    const SizedBox(height: 24),
                    AppCard(
                      color: Brand.surfaceHigh,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SelectableText(
                            code,
                            key: const Key('recovery-code-text'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          const SizedBox(height: 14),
                          OutlinedButton.icon(
                            key: const Key('copy-recovery-code'),
                            onPressed: () => _copy(code),
                            icon: Icon(_copied ? Icons.check_rounded : Icons.copy_rounded),
                            label: Text(_copied ? 'Copied' : 'Copy code'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const _Point(Icons.edit_note_rounded, 'Write it down', 'On paper, or give it to a Ground to Growth staff member to keep for you.'),
                    const _Point(Icons.visibility_off_rounded, "We can't show it to you again", "It isn't stored anywhere we can read — only you (or whoever you gave it to) will have it."),
                    const _Point(Icons.phonelink_lock_rounded, 'Works on any device', 'Open the app anywhere, choose "I already have an account," and enter this code.'),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                child: GradientButton(
                  key: const Key('recovery-code-saved'),
                  label: "I've saved it",
                  icon: Icons.check_rounded,
                  onPressed: () => context.read<AppState>().acknowledgeRecoveryCode(),
                ),
              ),
            ],
          ),
        ),
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
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Brand.orange),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 2),
                Text(body, style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
