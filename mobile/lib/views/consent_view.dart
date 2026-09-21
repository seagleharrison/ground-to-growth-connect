import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';

class ConsentView extends StatelessWidget {
  const ConsentView({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, app, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('Consent')),
          body: RefreshIndicator(
            onRefresh: app.refreshSession,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _StatusCard(app: app),
                const SizedBox(height: 16),
                _DisclosureCard(app: app),
                const SizedBox(height: 16),
                _ActionButtons(app: app),
                if (app.consentHistory.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _AuditLog(app: app),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

class _StatusCard extends StatelessWidget {
  final AppState app;
  const _StatusCard({required this.app});

  @override
  Widget build(BuildContext context) {
    final active = app.consent?.granted == true;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Tracking status', style: TextStyle(fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (active ? Colors.green : Colors.red).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  active ? 'Active' : 'Off',
                  style: TextStyle(
                    color: active ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          if (app.user != null) ...[
            const SizedBox(height: 8),
            Text('Signed in as ${app.user!.name}', style: const TextStyle(color: Colors.grey)),
          ],
        ],
      ),
    );
  }
}

class _DisclosureCard extends StatelessWidget {
  final AppState app;
  const _DisclosureCard({required this.app});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: app.disclosure == null
          ? const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Disclosure · v${app.disclosure!.version}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: SingleChildScrollView(
                    child: Text(app.disclosure!.text,
                        style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  ),
                ),
              ],
            ),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  final AppState app;
  const _ActionButtons({required this.app});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FilledButton(
          onPressed: (app.consent?.granted == true || app.isLoading) ? null : app.grantConsent,
          child: const SizedBox(width: double.infinity, child: Text('Grant consent', textAlign: TextAlign.center)),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: (app.consent?.granted != true || app.isLoading) ? null : app.revokeConsent,
          style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
          child: const SizedBox(width: double.infinity, child: Text('Revoke consent', textAlign: TextAlign.center)),
        ),
      ],
    );
  }
}

class _AuditLog extends StatelessWidget {
  final AppState app;
  const _AuditLog({required this.app});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Consent audit log', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          for (final record in app.consentHistory) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(record.granted ? 'Granted' : 'Revoked',
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  Text(
                    record.createdAt.length >= 19
                        ? record.createdAt.substring(0, 19).replaceAll('T', ' ')
                        : record.createdAt,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Divider(),
          ],
        ],
      ),
    );
  }
}
