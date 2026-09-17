import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// The glass orb: Glyf's onboarding signature. A glossy sphere holding the
/// Glyf symbol (the app icon's g and violet dot), floating on a soft glow,
/// its sheen slowly turning so it reads as glass, not a flat circle.
class GlassOrb extends StatefulWidget {
  const GlassOrb({
    super.key,
    this.size = 180,
    this.floating = true,
    this.energy = 0,
    this.showSymbol = true,
  });

  final double size;
  final bool floating;

  /// 0 at rest, up to 1 while it is talking: the glow swells with it.
  final double energy;
  final bool showSymbol;

  @override
  State<GlassOrb> createState() => _GlassOrbState();
}

class _GlassOrbState extends State<GlassOrb> with TickerProviderStateMixin {
  late final AnimationController _bob =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 4200))..repeat(reverse: true);
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(seconds: 16))..repeat();

  @override
  void dispose() {
    _bob.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return AnimatedBuilder(
      animation: Listenable.merge([_bob, _spin]),
      builder: (context, _) {
        final t = reduce ? 0.5 : Curves.easeInOut.transform(_bob.value);
        final lift = widget.floating ? lerpDouble(-6, 6, t)! : 0.0;
        return Transform.translate(
          offset: Offset(0, lift),
          child: _orb(reduce ? 0 : _spin.value * 2 * math.pi, t),
        );
      },
    );
  }

  Widget _orb(double angle, double t) {
    final s = widget.size;
    final e = widget.energy.clamp(0.0, 1.0);
    return SizedBox(
      width: s * 1.5,
      height: s * 1.5,
      child: Stack(alignment: Alignment.center, children: [
        // The glow the sphere sits in: violet with a cool blue edge.
        Container(
          width: s * (1.4 + 0.12 * e),
          height: s * (1.4 + 0.12 * e),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [
              Glass.accent.withValues(alpha: 0.26 + 0.16 * e),
              const Color(0xFF8FB8FF).withValues(alpha: 0.12 + 0.06 * e),
              Glass.accent.withValues(alpha: 0),
            ], stops: const [0.3, 0.6, 1]),
          ),
        ),
        // Soft shadow the sphere casts below itself, breathing with the float.
        Positioned(
          bottom: s * 0.14 - 4 * t,
          child: Container(
            width: s * (0.56 - 0.05 * t),
            height: s * 0.08,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(s),
              boxShadow: [
                BoxShadow(color: const Color(0xFF4B2FD6).withValues(alpha: 0.14), blurRadius: s * 0.16),
              ],
            ),
          ),
        ),
        SizedBox(
          width: s,
          height: s,
          child: ClipOval(
            child: Stack(fit: StackFit.expand, children: [
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: CustomPaint(painter: _SphereBody(angle)),
              ),
              if (widget.showSymbol)
                Center(
                  // Nudged so the g, not the g-and-dot, sits in the middle.
                  child: Transform.translate(
                    offset: Offset(s * 0.04, s * 0.015),
                    child: Image.asset(
                      'assets/brand/glyf-symbol.png',
                      height: s * 0.5,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ),
              // Glass over the symbol: highlights and the rim.
              CustomPaint(painter: _SphereFront()),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// The sphere itself: tinted glass, deeper at the rim, with an iridescent
/// sheen that turns and a caustic of light gathered at the bottom.
class _SphereBody extends CustomPainter {
  _SphereBody(this.angle);
  final double angle;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final c = Offset(s / 2, s / 2);
    final r = s / 2;
    final rect = Offset.zero & size;

    // Body: bright where the light enters (top-left), lavender toward the rim.
    canvas.drawCircle(c, r, Paint()
      ..shader = const RadialGradient(
        center: Alignment(-0.32, -0.38),
        radius: 1.08,
        colors: [Color(0xFFFFFFFF), Color(0xFFF4F1FF), Color(0xFFDDD5FF), Color(0xFFAE9EFF)],
        stops: [0.0, 0.38, 0.74, 1.0],
      ).createShader(rect));

    // Iridescent sheen, slowly turning.
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle);
    canvas.translate(-c.dx, -c.dy);
    canvas.drawCircle(c, r, Paint()
      ..shader = SweepGradient(colors: [
        const Color(0x00FFFFFF),
        const Color(0xFF8FD0FF).withValues(alpha: 0.22),
        const Color(0x00FFFFFF),
        const Color(0xFFFFB3E0).withValues(alpha: 0.18),
        const Color(0x00FFFFFF),
      ], stops: const [0, 0.22, 0.46, 0.72, 1]).createShader(rect));
    canvas.restore();

    // Light gathered at the bottom, as it is in real glass.
    canvas.drawOval(
      Rect.fromCenter(center: Offset(s * 0.55, s * 0.86), width: s * 0.62, height: s * 0.26),
      Paint()
        ..shader = RadialGradient(colors: [
          Colors.white.withValues(alpha: 0.7),
          Colors.white.withValues(alpha: 0),
        ]).createShader(Rect.fromCenter(center: Offset(s * 0.55, s * 0.86), width: s * 0.62, height: s * 0.26)),
    );

    // The rim: deeper colour right at the edge gives the sphere its volume.
    canvas.drawCircle(c, r, Paint()
      ..shader = RadialGradient(colors: [
        Glass.accent.withValues(alpha: 0),
        Glass.accent.withValues(alpha: 0),
        const Color(0xFF5B3FE0).withValues(alpha: 0.28),
      ], stops: const [0, 0.8, 1]).createShader(rect));
  }

  @override
  bool shouldRepaint(_SphereBody old) => old.angle != angle;
}

/// What sits on top of the symbol: the window highlight and a bright rim.
class _SphereFront extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final c = Offset(s / 2, s / 2);

    // A soft window reflection, top-left.
    canvas.save();
    final hc = Offset(s * 0.33, s * 0.22);
    canvas.translate(hc.dx, hc.dy);
    canvas.rotate(-0.62);
    final hr = Rect.fromCenter(center: Offset.zero, width: s * 0.4, height: s * 0.16);
    canvas.drawOval(hr, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.white.withValues(alpha: 0.92), Colors.white.withValues(alpha: 0.05)],
      ).createShader(hr));
    canvas.restore();

    // A small sharp glint beside it.
    canvas.drawCircle(Offset(s * 0.2, s * 0.36), s * 0.025,
        Paint()..color = Colors.white.withValues(alpha: 0.85));

    // Rim light.
    canvas.drawCircle(c, s / 2 - 0.75, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..shader = SweepGradient(colors: [
        Colors.white.withValues(alpha: 0.95),
        Colors.white.withValues(alpha: 0.3),
        Colors.white.withValues(alpha: 0.8),
        Colors.white.withValues(alpha: 0.3),
        Colors.white.withValues(alpha: 0.95),
      ]).createShader(Offset.zero & size));
  }

  @override
  bool shouldRepaint(_SphereFront oldDelegate) => false;
}
