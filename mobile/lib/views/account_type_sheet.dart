import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

/// Lets someone switch between a participant account and a staff role.
/// Moving into a staff role needs the staff invite code — the same one used at
/// sign-up — because staff can see where participants are.
Future<void> showAccountTypeSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const AccountTypeSheet(),
  );
}

class AccountTypeSheet extends StatefulWidget {
  const AccountTypeSheet({super.key});

  @override
  State<AccountTypeSheet> createState() => _AccountTypeSheetState();
}

class _AccountTypeSheetState extends State<AccountTypeSheet> {
  final _code = TextEditingController();
  PersonType? _picked;
  String? _error;

  static const _options = <(PersonType, IconData, String, String)>[
    (PersonType.homeless, Icons.favorite_rounded, 'Getting support', 'Share your location with outreach and keep your documents safe.'),
    (PersonType.volunteer, Icons.volunteer_activism_rounded, 'Volunteer', 'See the map of people who are sharing their location.'),
    (PersonType.admin, Icons.admin_panel_settings_rounded, 'Admin', 'Everything a volunteer sees, plus organization-wide numbers.'),
  ];

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _save(AppState app, PersonType current) async {
    final picked = _picked;
    if (picked == null || picked == current) return;
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final error = await app.changeAccountType(picked, staffCode: _code.text.trim());
    if (!mounted) return;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text("You're now set up as ${_titleFor(picked).toLowerCase()}.")));
  }

  String _titleFor(PersonType t) => _options.firstWhere((o) => o.$1 == t).$3;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final current = PersonType.fromWire(app.user?.personType ?? 'homeless');
    final picked = _picked ?? current;
    final changing = picked != current;
    final needsCode = changing && picked.isStaff;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(3)))),
            const SizedBox(height: 22),
            Text('Account type', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 6),
            const Text('Choose how you use Ground to Growth Connect.', style: TextStyle(color: Colors.white70, fontSize: 15)),
            const SizedBox(height: 18),
            for (final (type, icon, title, subtitle) in _options)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _TypeTile(
                  key: Key('type-${type.name}'),
                  icon: icon,
                  title: title,
                  subtitle: subtitle,
                  selected: picked == type,
                  isCurrent: current == type,
                  onTap: () => setState(() {
                    _picked = type;
                    _error = null;
                  }),
                ),
              ),
            AnimatedSize(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: !changing
                  ? const SizedBox(width: double.infinity)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 6),
                        if (needsCode) ...[
                          TextField(
                            key: const Key('staff-code-field'),
                            controller: _code,
                            obscureText: true,
                            autocorrect: false,
                            decoration: const InputDecoration(labelText: 'Staff invite code', prefixIcon: Icon(Icons.key_rounded)),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 10),
                        ],
                        _Heads(
                          needsCode
                              ? "You'll stop sharing your location and see the staff map instead of Home and Documents. Your stored documents stay safe and come back if you switch back."
                              : "You'll get Home and Documents back. Location sharing starts off — you choose whether to turn it on.",
                        ),
                      ],
                    ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, key: const Key('account-type-error'), style: const TextStyle(color: Brand.amber, fontSize: 14, height: 1.35)),
            ],
            const SizedBox(height: 18),
            GradientButton(
              key: const Key('account-type-save'),
              label: changing ? 'Switch to ${_titleFor(picked)}' : 'Choose a different type',
              icon: Icons.check_rounded,
              loading: app.isSavingProfile,
              onPressed: changing && (!needsCode || _code.text.trim().isNotEmpty) ? () => _save(app, current) : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _Heads extends StatelessWidget {
  final String text;
  const _Heads(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline_rounded, size: 18, color: Colors.white54),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(color: Colors.white60, fontSize: 13.5, height: 1.4))),
      ],
    );
  }
}

class _TypeTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final bool isCurrent;
  final VoidCallback onTap;

  const _TypeTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.isCurrent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? Brand.orange.withValues(alpha: 0.12) : Brand.surfaceHigh,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? Brand.orange : Colors.transparent, width: 2),
        ),
        child: Row(
          children: [
            Icon(icon, size: 26, color: selected ? Brand.orange : Colors.white54),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      if (isCurrent) ...[const SizedBox(width: 8), const Pill(label: 'Current', color: Brand.green)],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.3)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
