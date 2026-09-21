import 'dart:typed_data';

import 'package:flutter/material.dart';

/// A round profile picture, or the person's initials when they haven't added
/// one yet.
class ProfileAvatar extends StatelessWidget {
  final Uint8List? bytes;
  final String name;
  final double radius;

  const ProfileAvatar({super.key, required this.bytes, required this.name, this.radius = 32});

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.surfaceContainerHigh,
      foregroundImage: bytes != null ? MemoryImage(bytes!) : null,
      child: Text(
        _initials,
        style: TextStyle(
          fontSize: radius * 0.75,
          fontWeight: FontWeight.w600,
          color: scheme.primary,
        ),
      ),
    );
  }
}
