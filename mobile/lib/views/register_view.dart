import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

class RegisterView extends StatefulWidget {
  const RegisterView({super.key});

  @override
  State<RegisterView> createState() => _RegisterViewState();
}

class _RegisterViewState extends State<RegisterView> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _staffCodeController = TextEditingController();
  Gender? _gender;
  bool _isStaff = false;
  PersonType _staffType = PersonType.volunteer;
  String? _shownError;

  PersonType get _personType => _isStaff ? _staffType : PersonType.homeless;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _staffCodeController.dispose();
    super.dispose();
  }

  bool _canSubmit(AppState app) {
    final nameOk = _nameController.text.trim().isNotEmpty;
    final staffOk = !_isStaff || _staffCodeController.text.trim().isNotEmpty;
    return nameOk && staffOk && !app.isLoading;
  }

  void _submit(AppState app) {
    FocusScope.of(context).unfocus();
    app.register(RegisterRequest(
      name: _nameController.text.trim(),
      email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
      gender: (_gender ?? Gender.preferNotToSay).wireValue,
      phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
      personType: _personType.name,
      staffCode: _isStaff ? _staffCodeController.text.trim() : null,
    ));
  }

  /// Shows a failure once, as a banner, instead of stacking dialogs.
  void _surfaceError(AppState app) {
    final message = app.errorMessage;
    if (message == null || message == _shownError) return;
    _shownError = message;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          duration: const Duration(seconds: 7),
          content: Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: Brand.red),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
        ));
      app.clearError();
      _shownError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    _surfaceError(app);

    return Scaffold(
      body: Stack(
        children: [
          // Soft warm glow behind the header.
          Positioned(
            top: -140,
            left: -60,
            right: -60,
            child: Container(
              height: 380,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [Brand.orange.withValues(alpha: 0.16), Brand.orange.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 40),
              children: [
                FadeSlideIn(child: _hero(context)),
                const SizedBox(height: 28),
                FadeSlideIn(delay: const Duration(milliseconds: 100), child: _formCard(context, app)),
                const SizedBox(height: 16),
                FadeSlideIn(delay: const Duration(milliseconds: 180), child: _optionalDetails(context)),
                const SizedBox(height: 22),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 240),
                  child: GradientButton(
                    label: 'Create my account',
                    icon: Icons.arrow_forward_rounded,
                    loading: app.isLoading,
                    onPressed: _canSubmit(app) ? () => _submit(app) : null,
                  ),
                ),
                const SizedBox(height: 16),
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lock_rounded, size: 16, color: Colors.white38),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Your details are encrypted. There's no password to remember — your account stays safely on this phone.",
                        style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (app.disclosure != null)
                  Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(
                        'Read the privacy disclosure · v${app.disclosure!.version}',
                        style: const TextStyle(fontSize: 14, color: Brand.orange, fontWeight: FontWeight.w600),
                      ),
                      children: [
                        Text(app.disclosure!.text, style: const TextStyle(color: Colors.white54, fontSize: 12.5, height: 1.45)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _hero(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            gradient: Brand.heroGradient,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [BoxShadow(color: Brand.orangeDeep.withValues(alpha: 0.4), blurRadius: 24, offset: const Offset(0, 10))],
          ),
          child: const Icon(Icons.eco_rounded, size: 38, color: Color(0xFF3A1D00)),
        ),
        const SizedBox(height: 22),
        Text('Ground to Growth\nConnect', style: Theme.of(context).textTheme.headlineLarge?.copyWith(height: 1.05)),
        const SizedBox(height: 10),
        const Text(
          'A path to healing, a journey to home',
          style: TextStyle(fontSize: 17, color: Brand.orange, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        const Text('A program of Ground to Growth Initiative · Savannah, GA', style: TextStyle(color: Colors.white54, fontSize: 13)),
      ],
    );
  }

  Widget _formCard(BuildContext context, AppState app) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Let's get you started", style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_rounded)),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),
          const Text('I am…', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white70)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _RoleTile(
                  key: const Key('role-participant'),
                  icon: Icons.favorite_rounded,
                  title: 'Getting support',
                  selected: !_isStaff,
                  onTap: () => setState(() => _isStaff = false),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _RoleTile(
                  key: const Key('role-staff'),
                  icon: Icons.volunteer_activism_rounded,
                  title: 'Staff or volunteer',
                  selected: _isStaff,
                  onTap: () => setState(() => _isStaff = true),
                ),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !_isStaff
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final t in [PersonType.volunteer, PersonType.admin])
                            ChoiceChip(
                              key: Key('staff-type-${t.name}'),
                              label: Text(t.label),
                              selected: _staffType == t,
                              onSelected: (_) => setState(() => _staffType = t),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _staffCodeController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Staff invite code',
                          prefixIcon: Icon(Icons.key_rounded),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(top: 8, left: 4),
                        child: Text(
                          'Staff can see where participants are. Ask Ground to Growth for the code.',
                          style: TextStyle(color: Colors.white54, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _optionalDetails(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 18),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          leading: const Icon(Icons.contact_page_rounded, color: Brand.orange),
          title: const Text('Add contact details', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('Optional', style: TextStyle(color: Colors.white54)),
          children: [
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_rounded)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone', prefixIcon: Icon(Icons.phone_rounded)),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<Gender?>(
              initialValue: _gender,
              decoration: const InputDecoration(labelText: 'Gender', prefixIcon: Icon(Icons.badge_rounded)),
              items: [
                const DropdownMenuItem<Gender?>(value: null, child: Text('Prefer not to say')),
                for (final g in Gender.values.where((g) => g != Gender.preferNotToSay))
                  DropdownMenuItem<Gender?>(value: g, child: Text(g.label)),
              ],
              onChanged: (g) => setState(() => _gender = g),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  const _RoleTile({super.key, required this.icon, required this.title, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? Brand.orange.withValues(alpha: 0.14) : Brand.surfaceHigh,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? Brand.orange : Colors.transparent, width: 2),
        ),
        child: Column(
          children: [
            Icon(icon, size: 28, color: selected ? Brand.orange : Colors.white54),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700, color: selected ? Colors.white : Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}
