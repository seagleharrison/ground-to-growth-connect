import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import 'account_type_sheet.dart';
import 'edit_profile_view.dart';
import 'profile_avatar.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late final TextEditingController _apiUrlController;

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
    final app = context.watch<AppState>();
    if (_apiUrlController.text.isEmpty && app.apiBaseUrl.isNotEmpty) {
      _apiUrlController.text = app.apiBaseUrl;
    }

    return LargeTitlePage(
      title: 'Me',
      children: [
        if (app.user != null) ...[
          FadeSlideIn(child: _profileCard(context, app)),
          const SizedBox(height: 12),
          if (_contactRows(app).isNotEmpty)
            FadeSlideIn(
              delay: const Duration(milliseconds: 70),
              child: AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                child: Column(children: _contactRows(app)),
              ),
            ),
          const SizedBox(height: 12),
          FadeSlideIn(
            delay: const Duration(milliseconds: 110),
            child: AppCard(
              key: const Key('account-type-row'),
              onTap: () => showAccountTypeSheet(context),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              child: Row(
                children: [
                  const Icon(Icons.swap_horiz_rounded, color: Brand.orange),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Account type', style: TextStyle(fontWeight: FontWeight.w700)),
                        SizedBox(height: 2),
                        Text('Switch between getting support and staff', style: TextStyle(color: Colors.white54, fontSize: 13)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right_rounded, color: Colors.white38),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],

        const SectionLabel('Privacy & security'),
        const AppCard(
          child: Column(
            children: [
              _InfoRow(Icons.lock_rounded, 'Your sign-in is kept in your phone’s secure storage'),
              _InfoRow(Icons.enhanced_encryption_rounded, 'Your personal details are encrypted'),
              _InfoRow(Icons.grid_on_rounded, 'Your location is blurred to about 200 meters'),
              _InfoRow(Icons.face_rounded, 'Face ID or your passcode protects the app and your documents'),
            ],
          ),
        ),
        const SizedBox(height: 24),

        const SectionLabel('Advanced'),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: AppCard(
            padding: EdgeInsets.zero,
            child: ExpansionTile(
              shape: const Border(),
              collapsedShape: const Border(),
              leading: const Icon(Icons.dns_rounded, color: Colors.white60),
              title: const Text('Server settings', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('For Ground to Growth staff', style: TextStyle(color: Colors.white54)),
              childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              children: [
                TextField(
                  controller: _apiUrlController,
                  decoration: const InputDecoration(labelText: 'API base URL'),
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => app.saveApiBaseUrl(_apiUrlController.text),
                  child: const Text('Save API URL'),
                ),
                const SizedBox(height: 10),
                const Text(
                  'iOS Simulator: http://127.0.0.1:3001\nAndroid emulator: http://10.0.2.2:3001\nPhysical device: http://YOUR_MAC_IP:3001',
                  style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.5),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        const SectionLabel('Account'),
        OutlinedButton.icon(
          onPressed: app.signOut,
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Sign out'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => _confirmDelete(context, app),
          style: OutlinedButton.styleFrom(foregroundColor: Brand.red),
          icon: const Icon(Icons.delete_outline_rounded),
          label: const Text('Delete my data'),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 12, 4, 0),
          child: Text(
            "Deleting your data permanently removes your account, consent records, documents and all location history from Ground to Growth Initiative's server.",
            style: TextStyle(color: Colors.white54, fontSize: 12.5, height: 1.4),
          ),
        ),
        const SizedBox(height: 28),
        const Center(
          child: Text('Ground to Growth Connect · a program of Ground to Growth Initiative',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.white30, fontSize: 12)),
        ),
      ],
    );
  }

  List<Widget> _contactRows(AppState app) {
    final user = app.user!;
    return [
      if ((user.email ?? '').isNotEmpty) _row(Icons.mail_rounded, 'Email', user.email!),
      if ((user.phone ?? '').isNotEmpty) _row(Icons.phone_rounded, 'Phone', user.phone!),
      if ((user.gender ?? '').isNotEmpty) _row(Icons.badge_rounded, 'Gender', Gender.fromWire(user.gender!).label),
    ];
  }

  /// Picture, name and account type in one tappable card that opens the editor.
  Widget _profileCard(BuildContext context, AppState app) {
    final user = app.user!;
    return AppCard(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EditProfileView())),
      child: Row(
        children: [
          ProfileAvatar(bytes: app.profilePictureBytes, name: user.name, radius: 34),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Pill(label: PersonType.fromWire(user.personType).label, color: Brand.orange),
              ],
            ),
          ),
          const Text('Edit', style: TextStyle(color: Brand.orange, fontWeight: FontWeight.w700)),
          const Icon(Icons.chevron_right_rounded, color: Brand.orange),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Colors.white54),
            const SizedBox(width: 14),
            Text(label, style: const TextStyle(color: Colors.white60)),
            const Spacer(),
            Flexible(child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
      );

  Future<void> _confirmDelete(BuildContext context, AppState app) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Brand.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Delete your data?'),
        content: const Text(
          'This permanently deletes your account, your documents and all stored location history. This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete everything', style: TextStyle(color: Brand.red)),
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
  const _InfoRow(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Brand.orange),
          const SizedBox(width: 14),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white70, height: 1.35))),
        ],
      ),
    );
  }
}
