import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'nav.dart';
import 'theme/app_theme.dart';
import 'services/biometric_auth.dart';
import 'views/main_tab_view.dart';
import 'views/register_view.dart';

void main() {
  runApp(const GroundToGrowthConnectApp());
}

class GroundToGrowthConnectApp extends StatelessWidget {
  const GroundToGrowthConnectApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()..init()),
        ChangeNotifierProvider(create: (_) => TabNav()),
      ],
      child: MaterialApp(
        title: 'Ground to Growth Connect',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        darkTheme: buildAppTheme(),
        themeMode: ThemeMode.dark,
        home: const RootView(),
      ),
    );
  }
}

class RootView extends StatefulWidget {
  const RootView({super.key});

  @override
  State<RootView> createState() => _RootViewState();
}

class _RootViewState extends State<RootView> with WidgetsBindingObserver {
  bool _bootstrapped = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-lock whenever the app leaves the foreground, so returning to it
    // (even briefly backgrounded) requires Face ID again.
    if (state == AppLifecycleState.paused) {
      context.read<AppState>().setUnlocked(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    if (app.isInitializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_bootstrapped) {
      _bootstrapped = true;
      // Fire-and-forget: bootstrap() notifies listeners as it completes, no
      // need to await it before first paint.
      app.bootstrap();
    }

    if (!app.isSignedIn) {
      return const RegisterView();
    }

    return app.isUnlocked ? const MainTabView() : const LockedView();
  }
}

class LockedView extends StatefulWidget {
  const LockedView({super.key});

  @override
  State<LockedView> createState() => _LockedViewState();
}

/// Asks for Face ID by itself the moment the app is open and in front — on a
/// cold start and every time the person comes back to it — so signing in is
/// just looking at the phone. The Unlock button is only a fallback.
class _LockedViewState extends State<LockedView> with WidgetsBindingObserver {
  String? _authError;
  bool _prompting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // iOS refuses Face ID until the app is fully in front. If it isn't yet,
      // the "resumed" callback below asks as soon as it is.
      final state = WidgetsBinding.instance.lifecycleState;
      if (mounted && (state == null || state == AppLifecycleState.resumed)) _unlock();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) _unlock();
  }

  Future<void> _unlock() async {
    if (_prompting) return;
    _prompting = true;
    setState(() => _authError = null);
    try {
      final ok = await BiometricAuth.authenticate('Unlock Ground to Growth Connect');
      if (!mounted) return;
      if (ok) {
        context.read<AppState>().setUnlocked(true);
      } else {
        setState(() => _authError = "Face ID didn't work. Tap Unlock to try again.");
      }
    } finally {
      _prompting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.face_retouching_natural, size: 56, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 20),
            const Text('Ground to Growth Connect is locked', style: TextStyle(fontWeight: FontWeight.w600)),
            if (_authError != null) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _authError!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(onPressed: _unlock, child: const Text('Unlock')),
          ],
        ),
      ),
    );
  }
}
