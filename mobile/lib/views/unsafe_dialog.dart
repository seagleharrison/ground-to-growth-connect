import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The "I don't feel safe" button's confirmation. Pressing it tells every
/// admin right away and ends the match, so it asks once first.
Future<bool?> showUnsafeDialog(BuildContext context, {String? helper, bool byVolunteer = false}) => showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('unsafe-dialog'),
        backgroundColor: Brand.surface,
        title: const Text("Don't feel safe?"),
        content: Text(
          byVolunteer
              ? 'This tells every Ground to Growth admin right away and ends your match. If you are in danger, call 911.'
              : 'This tells every Ground to Growth admin right away and ends this match${helper == null ? '' : ' with $helper'}. '
                  "They won't be able to take your requests again. If you are in danger, call 911.",
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(key: const Key('unsafe-cancel'), onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            key: const Key('unsafe-confirm'),
            style: TextButton.styleFrom(foregroundColor: Brand.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send alert'),
          ),
        ],
      ),
    );
