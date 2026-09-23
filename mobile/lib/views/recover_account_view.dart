import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

/// Reached from "I already have an account" on the sign-up screen. Getting
/// back in needs only the recovery code shown once at sign-up — no email,
/// no password.
class RecoverAccountView extends StatefulWidget {
  const RecoverAccountView({super.key});

  @override
  State<RecoverAccountView> createState() => _RecoverAccountViewState();
}

class _RecoverAccountViewState extends State<RecoverAccountView> {
  final _codeController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit(AppState app) async {
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    final error = await app.recover(_codeController.text.trim());
    if (!mounted) return;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    // This screen was reached by pushing a route on top of RootView, so a
    // state change alone doesn't bring the signed-in app into view — leaving
    // this screen up is what a person would actually see otherwise.
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final canSubmit = _codeController.text.trim().isNotEmpty && !app.isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Use your recovery code')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(gradient: Brand.heroGradient, borderRadius: BorderRadius.circular(18)),
              child: const Icon(Icons.key_rounded, size: 30, color: Color(0xFF3A1D00)),
            ),
            const SizedBox(height: 18),
            const Text(
              'Enter the recovery code you saved when you first created your account. It gets you back into the same account, with the same documents.',
              style: TextStyle(fontSize: 16, height: 1.4, color: Colors.white70),
            ),
            const SizedBox(height: 22),
            TextField(
              key: const Key('recovery-code-field'),
              controller: _codeController,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(fontSize: 18, letterSpacing: 1.5, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(labelText: 'Recovery code', hintText: 'G7K4-9XPQ-3RTM', prefixIcon: Icon(Icons.key_rounded)),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => canSubmit ? _submit(app) : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Brand.red, fontSize: 14, height: 1.35)),
            ],
            const SizedBox(height: 22),
            GradientButton(
              key: const Key('recover-submit'),
              label: 'Continue',
              icon: Icons.arrow_forward_rounded,
              loading: app.isLoading,
              onPressed: canSubmit ? () => _submit(app) : null,
            ),
            const SizedBox(height: 16),
            const Text(
              "Lost the code, too? There's no way to get back into that account without it — Ground to Growth staff can't see or reset it either. "
              "You'd need to create a new account and add your documents again.",
              style: TextStyle(color: Colors.white54, fontSize: 12.5, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
