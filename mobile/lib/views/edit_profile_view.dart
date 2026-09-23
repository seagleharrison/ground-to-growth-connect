import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/models.dart';
import '../services/document_scanner_service.dart';
import 'profile_avatar.dart';

/// Lets someone change their own name, picture, email, phone and gender.
/// Account type is shown but not editable: it decides who can see other
/// people's locations, so only Ground to Growth staff can change it.
class EditProfileView extends StatefulWidget {
  const EditProfileView({super.key});

  @override
  State<EditProfileView> createState() => _EditProfileViewState();
}

class _EditProfileViewState extends State<EditProfileView> {
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  Gender? _gender;

  @override
  void initState() {
    super.initState();
    final user = context.read<AppState>().user!;
    _name = TextEditingController(text: user.name);
    _email = TextEditingController(text: user.email ?? '');
    _phone = TextEditingController(text: user.phone ?? '');
    final rawGender = user.gender;
    _gender = (rawGender == null || rawGender.isEmpty) ? null : Gender.fromWire(rawGender);
    for (final c in [_name, _email, _phone]) {
      c.addListener(() => setState(() {}));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().clearError();
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  bool _hasChanges(User user) {
    final originalGender = (user.gender == null || user.gender!.isEmpty) ? null : Gender.fromWire(user.gender!);
    return _name.text.trim() != user.name ||
        _email.text.trim() != (user.email ?? '') ||
        _phone.text.trim() != (user.phone ?? '') ||
        _gender != originalGender;
  }

  Future<void> _save() async {
    final app = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final ok = await app.updateProfile(
      name: _name.text.trim(),
      email: _email.text.trim(),
      phone: _phone.text.trim(),
      gender: _gender?.wireValue ?? '',
    );
    if (!ok || !mounted) return;
    navigator.pop();
    messenger.showSnackBar(const SnackBar(content: Text('Profile saved')));
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final app = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (file == null) return; // cancelled
      final bytes = await file.readAsBytes();
      await app.setProfilePicture(bytes, DocumentScannerService.mimeTypeFor(bytes));
    } on PlatformException {
      messenger.showSnackBar(SnackBar(
        content: Text(source == ImageSource.camera
            ? "The camera isn't available. You can choose a photo instead."
            : "Couldn't open your photos."),
      ));
    }
  }

  void _showPhotoOptions() {
    final hasPhoto = context.read<AppState>().user?.hasProfilePicture == true;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from photos'),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickPhoto(ImageSource.gallery);
              },
            ),
            if (hasPhoto)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Remove photo', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  context.read<AppState>().removeProfilePicture();
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final user = app.user;
    if (user == null) return const SizedBox.shrink();

    final canSave = _name.text.trim().isNotEmpty && _phone.text.trim().isNotEmpty && _hasChanges(user) && !app.isSavingProfile;

    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: GestureDetector(
              onTap: app.isSavingProfile ? null : _showPhotoOptions,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ProfileAvatar(bytes: app.profilePictureBytes, name: _name.text, radius: 56),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      child: Icon(Icons.camera_alt, size: 18, color: Theme.of(context).colorScheme.onPrimary),
                    ),
                  ),
                  if (app.isSavingProfile)
                    const Positioned.fill(child: Center(child: CircularProgressIndicator())),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: app.isSavingProfile ? null : _showPhotoOptions,
              child: Text(user.hasProfilePicture ? 'Change photo' : 'Add a photo'),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Full name',
              errorText: _name.text.trim().isEmpty ? 'Your name can\'t be blank' : null,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Email (optional)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Phone',
              errorText: _phone.text.trim().isEmpty ? "Phone can't be blank" : null,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<Gender?>(
            initialValue: _gender,
            decoration: const InputDecoration(labelText: 'Gender (optional)'),
            items: [
              const DropdownMenuItem<Gender?>(value: null, child: Text('Not specified')),
              for (final g in Gender.values) DropdownMenuItem<Gender?>(value: g, child: Text(g.label)),
            ],
            onChanged: (g) => setState(() => _gender = g),
          ),
          const SizedBox(height: 12),
          InputDecorator(
            decoration: const InputDecoration(labelText: 'Account type'),
            child: Text(PersonType.fromWire(user.personType).label),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Account type can only be changed by Ground to Growth staff.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
          if (app.errorMessage != null) ...[
            const SizedBox(height: 16),
            Text(app.errorMessage!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: canSave ? _save : null,
            child: app.isSavingProfile
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save changes'),
          ),
        ],
      ),
    );
  }
}
