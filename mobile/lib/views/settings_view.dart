import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/models.dart';
import 'edit_profile_view.dart';
import 'profile_avatar.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late TextEditingController _apiUrlController;

  @override
  void initState() {
    super.initState();
    _apiUrlController = TextEditingController();
  }

  @override
  void dispose() {
    _apiUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, app, _) {
        if (_apiUrlController.text.isEmpty && app.apiBaseUrl.isNotEmpty) {
          _apiUrlController.text = app.apiBaseUrl;
        }
        return Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (app.user != null) ...[
                const Text('Profile', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _profileCard(context, app),
                const SizedBox(height: 8),
                if ((app.user!.email ?? '').isNotEmpty) _row('Email', app.user!.email!),
                if ((app.user!.phone ?? '').isNotEmpty) _row('Phone', app.user!.phone!),
                if ((app.user!.gender ?? '').isNotEmpty)
                  _row('Gender', Gender.fromWire(app.user!.gender!).label),
                const SizedBox(height: 24),
              ],

              const Text('Server', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: _apiUrlController,
                decoration: const InputDecoration(labelText: 'API base URL'),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => app.saveApiBaseUrl(_apiUrlController.text),
                child: const Text('Save API URL'),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'iOS Simulator: http://127.0.0.1:3001\nAndroid emulator: http://10.0.2.2:3001\nPhysical device: http://YOUR_MAC_IP:3001',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
              const SizedBox(height: 24),

              const Text('Security & privacy', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const _InfoRow(icon: Icons.lock_outline, text: 'Access token stored in secure storage'),
              const _InfoRow(icon: Icons.lock, text: 'Personal details encrypted at rest'),
              const _InfoRow(icon: Icons.grid_on, text: 'Location snapped to a ~200m grid'),
              const SizedBox(height: 24),

              OutlinedButton(
                onPressed: app.signOut,
                child: const Text('Sign out'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => _confirmDelete(context, app),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Delete my data'),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  "Deleting your data permanently removes your account, consent records, and all location history from Ground to Growth Initiative's server.",
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Picture, name and account type in one tappable card that opens the editor.
  Widget _profileCard(BuildContext context, AppState app) {
    final user = app.user!;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const EditProfileView()),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              ProfileAvatar(bytes: app.profilePictureBytes, name: user.name, radius: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      PersonType.fromWire(user.personType).label,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Text('Edit', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
              Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text(label, style: const TextStyle(color: Colors.grey)), Text(value)],
        ),
      );

  Future<void> _confirmDelete(BuildContext context, AppState app) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete your data?'),
        content: const Text(
            'This permanently deletes your account and all stored location history. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete everything', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await app.deleteAccount();
    }
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [Icon(icon, size: 18), const SizedBox(width: 8), Text(text)]),
    );
  }
}
