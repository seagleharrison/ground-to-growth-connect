import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
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
    return ChangeNotifierProvider(
      create: (_) => AppState()..init(),
      child: MaterialApp(
        title: 'Ground to Growth Connect',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange, brightness: Brightness.dark),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange, brightness: Brightness.dark),
          useMaterial3: true,
        ),
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

class _LockedViewState extends State<LockedView> {
  String? _authError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    setState(() => _authError = null);
    final ok = await BiometricAuth.authenticate('Unlock Ground to Growth Connect');
    if (!mounted) return;
    if (ok) {
      context.read<AppState>().setUnlocked(true);
    } else {
      setState(() => _authError = 'Authentication failed. Try again.');
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
