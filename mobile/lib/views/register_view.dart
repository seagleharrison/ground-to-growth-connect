import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/models.dart';

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
  Gender _gender = Gender.preferNotToSay;
  PersonType _personType = PersonType.homeless;

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
    final staffOk = !_personType.isStaff || _staffCodeController.text.trim().isNotEmpty;
    return nameOk && staffOk && !app.isLoading;
  }

  void _submit(AppState app) {
    final payload = RegisterRequest(
      name: _nameController.text.trim(),
      email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
      gender: _gender.wireValue,
      phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
      personType: _personType.name,
      staffCode: _personType.isStaff ? _staffCodeController.text.trim() : null,
    );
    app.register(payload);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, app, _) {
        if (app.errorMessage != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Error'),
                content: Text(app.errorMessage!),
                actions: [
                  TextButton(
                    onPressed: () {
                      app.clearError();
                      Navigator.of(context).pop();
                    },
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          });
        }

        return Scaffold(
          appBar: AppBar(title: const Text('Welcome')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Ground to Growth Connect',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('A path to healing, a journey to home',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey)),
              Text('A program of Ground to Growth Initiative · Savannah, GA',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
              const SizedBox(height: 24),

              const Text('Your details', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Full name'),
                onChanged: (_) => setState(() {}),
              ),
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email (optional)'),
                keyboardType: TextInputType.emailAddress,
              ),
              TextField(
                controller: _phoneController,
                decoration: const InputDecoration(labelText: 'Phone (optional)'),
                keyboardType: TextInputType.phone,
              ),
              DropdownButtonFormField<Gender>(
                initialValue: _gender,
                decoration: const InputDecoration(labelText: 'Gender'),
                items: Gender.values
                    .map((g) => DropdownMenuItem(value: g, child: Text(g.label)))
                    .toList(),
                onChanged: (g) => setState(() => _gender = g ?? _gender),
              ),
              const SizedBox(height: 24),

              const Text('Account type', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              DropdownButtonFormField<PersonType>(
                initialValue: _personType,
                decoration: const InputDecoration(labelText: 'I am a'),
                items: PersonType.values
                    .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                    .toList(),
                onChanged: (t) => setState(() => _personType = t ?? _personType),
              ),
              if (_personType.isStaff) ...[
                TextField(
                  controller: _staffCodeController,
                  decoration: const InputDecoration(labelText: 'Staff invite code'),
                  obscureText: true,
                  onChanged: (_) => setState(() {}),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Staff accounts can view participant locations and require a code from Ground to Growth.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
              ],
              const SizedBox(height: 24),

              FilledButton(
                onPressed: _canSubmit(app) ? () => _submit(app) : null,
                child: app.isLoading
                    ? const SizedBox(
                        height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Create account'),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  "Your details are encrypted and stored securely. Your access token is kept only in this device's secure storage.",
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),

              if (app.disclosure != null) ...[
                const SizedBox(height: 24),
                Text('Disclosure · v${app.disclosure!.version}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(app.disclosure!.text, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ],
          ),
        );
      },
    );
  }
}
