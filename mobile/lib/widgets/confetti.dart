import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A short burst of falling confetti — a small celebration for finishing
/// something that took effort. Plays once, ignores touches, then disappears.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({super.key});

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))
    ..forward();
  late final List<_Piece> _pieces = _makePieces();

  static List<_Piece> _makePieces() {
    final rng = math.Random(7);
    const colors = [Brand.orange, Brand.green, Brand.blue, Brand.amber, Color(0xFFB98CFF), Colors.white];
    return List.generate(56, (i) {
      return _Piece(
        x: rng.nextDouble(),
        delay: rng.nextDouble() * 0.35,
        speed: 0.55 + rng.nextDouble() * 0.6,
        sway: (rng.nextDouble() - 0.5) * 0.22,
        size: 6 + rng.nextDouble() * 7,
        spin: rng.nextDouble() * 8,
        color: colors[i % colors.length],
      );
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(painter: _ConfettiPainter(_pieces, _c.value), size: Size.infinite),
      ),
    );
  }
}

class _Piece {
  final double x, delay, speed, sway, size, spin;
  final Color color;
  const _Piece({
    required this.x,
    required this.delay,
    required this.speed,
    required this.sway,
    required this.size,
    required this.spin,
    required this.color,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<_Piece> pieces;
  final double t;
  _ConfettiPainter(this.pieces, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in pieces) {
      final local = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final y = -20 + (size.height + 40) * Curves.easeIn.transform(local) * p.speed;
      final x = size.width * (p.x + p.sway * math.sin(local * 7));
      final fade = local > 0.75 ? (1 - local) / 0.25 : 1.0;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.spin * local * math.pi);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.55), const Radius.circular(2)),
        Paint()..color = p.color.withValues(alpha: fade),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
