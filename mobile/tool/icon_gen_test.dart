// Draws the app icon masters (same orange leaf as the sign-up screen):
//   flutter test tool/icon_gen_test.dart --dart-define=ICON_DIR=/some/dir
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ground_to_growth_connect/theme/app_theme.dart';

const _outDir = String.fromEnvironment('ICON_DIR', defaultValue: '/tmp/g2g-icons');
final _fonts = '${Platform.environment['HOME']}/development/flutter/bin/cache/artifacts/material_fonts';

Future<ui.Image> _draw(int size, {required bool background, required double leafFraction}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final rect = Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble());
  if (background) {
    canvas.drawRect(
      rect,
      Paint()..shader = const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Brand.orange, Brand.orangeDeep]).createShader(rect),
    );
  }
  final icon = Icons.eco_rounded;
  final painter = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(fontFamily: icon.fontFamily, fontSize: size * leafFraction, color: const Color(0xFF3A1D00)),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(canvas, Offset((size - painter.width) / 2, (size - painter.height) / 2));
  return recorder.endRecording().toImage(size, size);
}

void main() {
  test('draw icon masters', () async {
    final icons = FontLoader('MaterialIcons')..addFont(File('$_fonts/MaterialIcons-Regular.otf').readAsBytes().then((b) => ByteData.view(b.buffer)));
    await icons.load();
    await Directory(_outDir).create(recursive: true);
    Future<void> save(String name, ui.Image image) async {
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      await File('$_outDir/$name').writeAsBytes(bytes.buffer.asUint8List());
    }

    // Full icon (iOS, Play Store, old Android): gradient with the leaf.
    await save('icon-1024.png', await _draw(1024, background: true, leafFraction: 0.58));
    // Android adaptive foreground: leaf only, kept inside the central safe area.
    await save('foreground-432.png', await _draw(432, background: false, leafFraction: 0.40));
  });
}
