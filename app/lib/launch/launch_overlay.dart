import 'dart:math' as math;
import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/theme.dart';
import '../onboarding/orb.dart';

/// Where the launch hands its bubble over. The first onboarding screen puts
/// [orbKey] on its orb and keeps that orb hidden, still and quiet until [done].
abstract final class LaunchHandoff {
  static final orbKey = GlobalKey(debugLabel: 'launch-orb');
  static final done = ValueNotifier<bool>(false);
}

/// The app's launch, "Lens Focus" from the launch lab.
///
/// A wipe draws the wordmark while the violet dot rides its edge. The dot
/// then swells into a lens: violet at first, clearing into tinted glass that
/// blurs the word behind it as it glides to the middle. The glass fills in
/// and the g comes into focus. The bubble then glides onto the orb of the
/// screen underneath (or, for someone already set up, dissolves into home).
///
/// Time moves on per frame, capped, so a slow frame delays a beat instead of
/// skipping it: every beat is seen. A phone that can't keep up at all falls
/// at most half a second behind and then catches up, so launch never drags. The native launch screens are
/// plain Glass.bg, so the first frame here continues them without a flash.
class LaunchOverlay extends StatefulWidget {
  const LaunchOverlay({
    super.key,
    required this.ready,
    required this.handToOrb,
    required this.onDone,
  });

  /// The app underneath has loaded and can be shown.
  final bool ready;

  /// The screen underneath has a bubble for this one to land on.
  final bool handToOrb;
  final VoidCallback onDone;

  @override
  State<LaunchOverlay> createState() => _LaunchOverlayState();
}

class _LaunchOverlayState extends State<LaunchOverlay> with SingleTickerProviderStateMixin {
  // ── Hard-coded beats, in milliseconds ─────────────────────────────────────
  static const _playMs = 1700.0;
  static const _wipeEnd = 680.0;
  static const _lensAt = 700.0;
  static const _lensEnd = 1300.0;
  static const _leaveMs = 560.0;

  /// The most one frame may move the animation on (a 50 fps frame).
  static const _maxStep = 20.0;

  /// How far behind real time slow frames may push the animation in all.
  static const _maxLag = 500.0;

  static const _orbSize = 170.0;
  static const _fontSize = 60.0;

  static const _easeOut = Cubic(0.23, 1, 0.32, 1);
  static const _easeInOut = Cubic(0.77, 0, 0.175, 1);
  /// The lens's travel and growth: the dot swells gently first, then glides
  /// to the middle and settles with a whisper of overshoot.
  static const _lensCurve = Cubic(0.5, 0, 0.15, 1.04);
  static const _glide = Cubic(0.65, 0, 0.35, 1);

  late final Ticker _ticker = createTicker(_tick);
  Duration _lastTick = Duration.zero;
  double _wall = 0;
  double _ms = 0;
  double _leave = -1;
  Rect? _target;
  bool _finished = false;

  final _word = TextPainter(
    text: TextSpan(
      text: 'glyf',
      style: TextStyle(
        fontFamily: 'Inter',
        fontSize: _fontSize,
        fontWeight: GlyfWordmark.weight,
        letterSpacing: _fontSize * GlyfWordmark.trackingRatio,
        color: Glass.ink,
        height: 1,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      precacheImage(const AssetImage('assets/brand/glyf-symbol.png'), context);
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) _ms = _playMs;
      _ticker.start();
    });
  }

  @override
  void didUpdateWidget(LaunchOverlay old) {
    super.didUpdateWidget(old);
    if (widget.ready && !old.ready) _startLeaving();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _word.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    final real = (elapsed - _lastTick).inMicroseconds / 1000.0;
    _lastTick = elapsed;
    double stepFrom(double shown) {
      _wall += real;
      return _wall - shown > _maxLag ? real : math.min(real, _maxStep);
    }

    if (_ms < _playMs) {
      final step = stepFrom(_ms);
      setState(() => _ms = math.min(_playMs, _ms + step));
      if (_ms >= _playMs) _startLeaving();
      return;
    }
    if (_leave >= 0) {
      final step = stepFrom(_playMs + _leave);
      setState(() => _leave = math.min(_leaveMs, _leave + step));
      if (_leave >= _leaveMs) _finish();
      return;
    }
    // Played, waiting for the app: keep the sheen turning.
    setState(() {});
  }

  void _startLeaving() {
    if (_leave >= 0 || _ms < _playMs || !widget.ready) return;
    _target = _measureTarget();
    _leave = 0;
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    _ticker.stop();
    LaunchHandoff.done.value = true;
    widget.onDone();
  }

  /// The sphere of the orb underneath, in this overlay's coordinates. It is
  /// held still until the hand-off, so one measurement is exact.
  Rect? _measureTarget() {
    if (!widget.handToOrb) return null;
    final box = LaunchHandoff.orbKey.currentContext?.findRenderObject();
    final me = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || me is! RenderBox) return null;
    final topLeft = me.globalToLocal(box.localToGlobal(Offset.zero));
    final sphere = box.size.width / 1.5;
    return Rect.fromCenter(center: (topLeft & box.size).center, width: sphere, height: sphere);
  }

  static double _span(double ms, double from, double to, [Curve curve = _easeOut]) =>
      curve.transform(((ms - from) / (to - from)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      child: LayoutBuilder(builder: (context, c) => _frame(Size(c.maxWidth, c.maxHeight))),
    );
  }

  Widget _frame(Size size) {
    final ms = _ms;
    final center = Offset(size.width / 2, size.height * 0.46);

    // The mark: word, gap, dot, centred as one.
    final wordW = _word.width;
    final wordH = _word.height;
    final dotD = _fontSize * GlyfWordmark.dotRatio;
    final markW = wordW + _fontSize * GlyfWordmark.gapRatio + dotD;
    final wordLeft = center.dx - markW / 2;
    final wordTop = center.dy - wordH / 2;
    final dotRest = Offset(
      wordLeft + wordW + _fontSize * GlyfWordmark.gapRatio + dotD / 2,
      wordTop + _fontSize * (0.80 - GlyfWordmark.riseRatio) - dotD / 2,
    );

    // 0–680: the wipe, the dot riding its edge.
    final wipe = _span(ms, 0, _wipeEnd, _easeInOut);
    final wordOpacity = 1 - _span(ms, 1040, 1340);
    final wordBlur = 6 * _span(ms, 1040, 1340);
    final rider = Offset(lerpDouble(wordLeft, dotRest.dx, wipe)!, dotRest.dy);

    // 700–1300: the dot swells into a lens on its way to the middle.
    final grow = _span(ms, _lensAt, _lensEnd, _lensCurve);
    final lensOn = ms >= _lensAt;
    var orbCenter = Offset.lerp(dotRest, center, grow)!;
    var orbSize = lerpDouble(dotD, _orbSize, grow)!;
    var orbOpacity = 1.0;

    // Then glide onto the orb underneath, or dissolve into home.
    var backdrop = 1.0;
    if (_leave >= 0) {
      final b = _leave / _leaveMs;
      final target = _target;
      if (target != null) {
        final k = _glide.transform(b);
        orbCenter = Offset.lerp(center, target.center, k)!;
        orbSize = lerpDouble(_orbSize, target.width, k)!;
        backdrop = 1 - Curves.easeOut.transform((b / 0.75).clamp(0.0, 1.0));
      } else {
        final k = Curves.easeOut.transform(b);
        orbSize = _orbSize * lerpDouble(1, 0.92, k)!;
        orbOpacity = 1 - k;
        backdrop = 1 - k;
      }
    }

    return Stack(children: [
      Positioned.fill(child: ColoredBox(color: Glass.bg.withValues(alpha: backdrop))),
      if (wordOpacity > 0 && wipe > 0)
        Positioned(
          left: wordLeft,
          top: wordTop,
          child: _blurred(
            wordBlur,
            Opacity(
              opacity: wordOpacity,
              child: ClipRect(
                clipper: _WipeClipper(wipe * markW),
                child: CustomPaint(size: Size(wordW, wordH), painter: _WordPainter(_word)),
              ),
            ),
          ),
        ),
      if (!lensOn) _dot(rider, dotD, _span(ms, 40, 160)),
      if (lensOn && orbOpacity > 0)
        Positioned(
          left: orbCenter.dx - orbSize * 0.75,
          top: orbCenter.dy - orbSize * 0.75,
          child: Opacity(
            opacity: orbOpacity,
            child: OrbVisual(
              size: orbSize,
              angle: orbSheenAngle(),
              // Violet at the start, clearing into glass as it grows.
              fill: 1 - _span(ms, 760, 1020),
              frontOpacity: _span(ms, 800, 1040),
              lensBlur: 16 * _span(ms, 740, 1180),
              lensTint: _span(ms, 740, 900) * (1 - _span(ms, 1320, 1560)),
              bodyOpacity: 0.35 * _span(ms, 820, 1040) + 0.65 * _span(ms, 1100, 1360),
              glowOpacity: _span(ms, 760, 1180),
              symbolOpacity: _span(ms, 1280, 1440),
              symbolBlur: 14 * (1 - _span(ms, 1280, 1680)),
              symbolScale: lerpDouble(0.96, 1, _span(ms, 1280, 1680))!,
            ),
          ),
        ),
    ]);
  }

  Widget _dot(Offset c, double d, double opacity) => Positioned(
        left: c.dx - d / 2,
        top: c.dy - d / 2,
        child: Opacity(
          opacity: opacity,
          child: Container(
            width: d,
            height: d,
            decoration: const BoxDecoration(color: Glass.accent, shape: BoxShape.circle),
          ),
        ),
      );

  static Widget _blurred(double sigma, Widget child) => sigma < 0.05
      ? child
      : ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.decal),
          child: child,
        );
}

/// Reveals the word from its left edge up to [width].
class _WipeClipper extends CustomClipper<Rect> {
  _WipeClipper(this.width);
  final double width;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(-size.height, -size.height, math.max(0, width), size.height * 2);

  @override
  bool shouldReclip(_WipeClipper old) => old.width != width;
}

class _WordPainter extends CustomPainter {
  _WordPainter(this.word);
  final TextPainter word;

  @override
  void paint(Canvas canvas, Size size) => word.paint(canvas, Offset.zero);

  @override
  bool shouldRepaint(_WordPainter old) => false;
}
