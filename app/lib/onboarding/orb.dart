import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// One clock for every bubble on screen: a bubble handed from the launch
/// animation to the next screen keeps the same sheen angle, so nothing jumps.
final Stopwatch _orbClock = Stopwatch()..start();

double orbSheenAngle() => (_orbClock.elapsedMilliseconds % 16000) / 16000 * 2 * math.pi;

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
    this.sphereKey,
  });

  final double size;
  final bool floating;

  /// 0 at rest, up to 1 while it is talking: the glow swells with it.
  final double energy;
  final bool showSymbol;

  /// On the sphere itself, inside the float: where the launch bubble lands.
  final Key? sphereKey;

  @override
  State<GlassOrb> createState() => _GlassOrbState();
}

class _GlassOrbState extends State<GlassOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _frames =
      AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
  int _born = _orbClock.elapsedMilliseconds;

  @override
  void didUpdateWidget(GlassOrb old) {
    super.didUpdateWidget(old);
    // A bubble that starts floating (the launch just landed on it) starts
    // from rest, not from wherever the clock would put it.
    if (widget.floating && !old.floating) _born = _orbClock.elapsedMilliseconds;
  }

  @override
  void dispose() {
    _frames.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return AnimatedBuilder(
      animation: _frames,
      builder: (context, _) {
        // The float starts from rest (a sine from 0), so a bubble that has
        // just landed here does not jump to the top of its bob.
        final phase = reduce ? 0.0 : ((_orbClock.elapsedMilliseconds - _born) % 8400) / 8400;
        final wave = math.sin(phase * 2 * math.pi);
        return Transform.translate(
          offset: Offset(0, widget.floating ? 6 * wave : 0),
          child: OrbVisual(
            key: widget.sphereKey,
            size: widget.size,
            angle: reduce ? 0 : orbSheenAngle(),
            energy: widget.energy,
            breathe: (wave + 1) / 2,
            showSymbol: widget.showSymbol,
          ),
        );
      },
    );
  }
}

/// The bubble at one moment. Everything the launch animation moves is a
/// parameter; at the defaults this is exactly the resting GlassOrb. Its box
/// is 1.5× the sphere so the glow has room.
class OrbVisual extends StatelessWidget {
  const OrbVisual({
    super.key,
    required this.size,
    this.angle = 0,
    this.energy = 0,
    this.breathe = 0.5,
    this.showSymbol = true,
    this.lensBlur = 16,
    this.lensTint = 0,
    this.fill = 0,
    this.frontOpacity = 1,
    this.bodyOpacity = 1,
    this.glowOpacity = 1,
    this.symbolOpacity = 1,
    this.symbolBlur = 0,
    this.symbolScale = 1,
  });

  final double size;
  final double angle;
  final double energy;

  /// 0 at the top of the float, 1 at the bottom: the shadow breathes with it.
  final double breathe;
  final bool showSymbol;

  /// How much the glass blurs what is behind it (a lens as it grows).
  final double lensBlur;

  /// A pale wash over the lens before the glass body fills in, 0 to 1.
  final double lensTint;

  /// Solid violet over the glass, 0 to 1: the dot the lens swells out of.
  final double fill;

  /// The highlight, glint and rim light, which arrive as the violet clears.
  final double frontOpacity;
  final double bodyOpacity;
  final double glowOpacity;
  final double symbolOpacity;
  final double symbolBlur;
  final double symbolScale;

  @override
  Widget build(BuildContext context) {
    final s = size;
    final e = energy.clamp(0.0, 1.0);
    final t = breathe;
    final glow = glowOpacity.clamp(0.0, 1.0);
    Widget symbol = Image.asset(
      'assets/brand/glyf-symbol.png',
      height: s * 0.5,
      filterQuality: FilterQuality.high,
    );
    if (symbolBlur > 0.05) {
      symbol = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: symbolBlur, sigmaY: symbolBlur, tileMode: TileMode.decal),
        child: symbol,
      );
    }
    return SizedBox(
      width: s * 1.5,
      height: s * 1.5,
      child: Stack(alignment: Alignment.center, children: [
        if (glow > 0) ...[
          // The glow the sphere sits in: violet with a cool blue edge.
          Container(
            width: s * (1.4 + 0.12 * e),
            height: s * (1.4 + 0.12 * e),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                Glass.accent.withValues(alpha: (0.26 + 0.16 * e) * glow),
                const Color(0xFF8FB8FF).withValues(alpha: (0.12 + 0.06 * e) * glow),
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
                  BoxShadow(color: const Color(0xFF4B2FD6).withValues(alpha: 0.14 * glow), blurRadius: s * 0.16),
                ],
              ),
            ),
          ),
        ],
        SizedBox(
          width: s,
          height: s,
          child: ClipOval(
            child: Stack(fit: StackFit.expand, children: [
              if (lensBlur > 0.05)
                BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: lensBlur, sigmaY: lensBlur),
                  child: const SizedBox.expand(),
                ),
              if (lensTint > 0) ColoredBox(color: const Color(0xFFF4F1FF).withValues(alpha: 0.32 * lensTint)),
              if (bodyOpacity > 0)
                Opacity(opacity: bodyOpacity.clamp(0.0, 1.0), child: CustomPaint(painter: _SphereBody(angle))),
              if (fill > 0) ColoredBox(color: Glass.accent.withValues(alpha: fill.clamp(0.0, 1.0))),
              if (showSymbol && symbolOpacity > 0)
                Center(
                  // Nudged so the g, not the g-and-dot, sits in the middle.
                  child: Transform.translate(
                    offset: Offset(s * 0.04, s * 0.015),
                    child: Transform.scale(
                      scale: symbolScale,
                      child: Opacity(opacity: symbolOpacity.clamp(0.0, 1.0), child: symbol),
                    ),
                  ),
                ),
              // Glass over the symbol: highlights and the rim.
              if (frontOpacity >= 0.999)
                CustomPaint(painter: _SphereFront())
              else if (frontOpacity > 0)
                Opacity(opacity: frontOpacity, child: CustomPaint(painter: _SphereFront())),
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
