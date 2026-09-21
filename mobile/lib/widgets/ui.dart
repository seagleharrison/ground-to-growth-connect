import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Space the floating bottom bar takes up, so scrolling content can clear it.
const double kNavBarClearance = 112;

/// Shrinks slightly while pressed and gives a light tap of haptics — the
/// small "this is alive" feeling on every tappable card and button.
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;

  const PressableScale({super.key, required this.child, this.onTap, this.pressedScale = 0.97});

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap == null) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapCancel: () => _set(false),
      onTapUp: (_) => _set(false),
      onTap: widget.onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              widget.onTap!();
            },
      child: AnimatedScale(
        scale: _down ? widget.pressedScale : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// The app's basic surface: a soft rounded card with a hairline border.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Gradient? gradient;
  final Color? color;
  final double radius;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.gradient,
    this.color,
    this.radius = 24,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? Brand.surface) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: child,
    );
    return onTap == null ? card : PressableScale(onTap: onTap, child: card);
  }
}

/// The big orange call-to-action button.
class GradientButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool loading;

  const GradientButton({super.key, required this.label, this.icon, this.onPressed, this.loading = false});

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return PressableScale(
      onTap: enabled ? onPressed : null,
      pressedScale: 0.98,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 56,
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: enabled ? Brand.heroGradient : null,
          color: enabled ? null : Brand.surfaceHigh,
          borderRadius: BorderRadius.circular(18),
          boxShadow: enabled
              ? [BoxShadow(color: Brand.orangeDeep.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 6))]
              : null,
        ),
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF3A1D00)),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 22, color: enabled ? const Color(0xFF3A1D00) : Colors.white38),
                    const SizedBox(width: 10),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: enabled ? const Color(0xFF3A1D00) : Colors.white38,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// A small rounded label, for statuses like "On file" or "Sharing".
class Pill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const Pill({super.key, required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 4)],
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: Colors.white54),
      ),
    );
  }
}

/// Fades and slides its child up into place. Give each item a slightly larger
/// [delay] and a screen assembles itself instead of just appearing.
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final double offset;

  const FadeSlideIn({super.key, required this.child, this.delay = Duration.zero, this.offset = 18});

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 480));
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: curve,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: curve.value,
        child: Transform.translate(offset: Offset(0, (1 - curve.value) * widget.offset), child: child),
      ),
    );
  }
}

/// A dot that gently pulses outward — used for "live" things like active sharing.
class PulseDot extends StatefulWidget {
  final Color color;
  final double size;
  const PulseDot({super.key, required this.color, this.size = 12});

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size * 2.6,
      height: widget.size * 2.6,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: widget.size * (1 + 1.6 * _c.value),
              height: widget.size * (1 + 1.6 * _c.value),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(alpha: 0.35 * (1 - _c.value)),
              ),
            ),
            Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
            ),
          ],
        ),
      ),
    );
  }
}

/// Frosted-glass panel that floats over the map.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  const GlassPanel({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.radius = 24});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: const Color(0xFF0E1117).withValues(alpha: 0.74),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// A round frosted button for map controls.
class GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool active;

  const GlassIconButton({super.key, required this.icon, this.onPressed, this.tooltip, this.active = false});

  @override
  Widget build(BuildContext context) {
    final button = PressableScale(
      onTap: onPressed,
      pressedScale: 0.92,
      child: GlassPanel(
        radius: 26,
        padding: const EdgeInsets.all(12),
        child: Icon(icon, size: 22, color: active ? Brand.orange : Colors.white),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// A screen with a big collapsing title (like Apple's own apps), pull-to-refresh,
/// and room at the bottom for the floating tab bar.
class LargeTitlePage extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final List<Widget>? actions;

  const LargeTitlePage({super.key, required this.title, required this.children, this.onRefresh, this.actions});

  @override
  Widget build(BuildContext context) {
    final scroll = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      slivers: [
        SliverAppBar.large(
          backgroundColor: Brand.background,
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.6)),
          actions: actions,
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, kNavBarClearance),
          sliver: SliverList(delegate: SliverChildListDelegate(children)),
        ),
      ],
    );
    return Scaffold(
      body: onRefresh == null ? scroll : RefreshIndicator(onRefresh: onRefresh!, child: scroll),
    );
  }
}
