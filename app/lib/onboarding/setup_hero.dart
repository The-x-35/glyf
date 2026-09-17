import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Keyboard setup, shown instead of told: the Glyf keyboard at work above a
/// copy of the exact Settings rows to flip, with the one to tap animating on.
/// When the phone reports it done, the switch stays on and a check lands.
class SetupHero extends StatefulWidget {
  const SetupHero({super.key, required this.step, required this.done, required this.android});

  /// 'enable' (add the keyboard) or 'access' (Full Access / switch to it).
  final String step;
  final bool done;
  final bool android;

  @override
  State<SetupHero> createState() => _SetupHeroState();
}

class _SetupHeroState extends State<SetupHero> with TickerProviderStateMixin {
  late final AnimationController _loop =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))..repeat();

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final w = math.min(box.maxWidth, 380.0);
      final kw = w;
      final kh = kw * 0.66;
      return AnimatedBuilder(
        animation: _loop,
        builder: (context, _) {
          final t = _loop.value;
          // The Settings card sits over the lower part of the keyboard, the
          // two read as one picture.
          return SizedBox(
            width: w,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned(top: 0, left: (w - kw) / 2, child: _AiKeyboard(width: kw, t: t)),
              Padding(
                padding: EdgeInsets.only(top: kh * 0.8, left: w * 0.06, right: w * 0.06),
                child: widget.android ? _androidCard(t) : _iosCard(t),
              ),
            ]),
          );
        },
      );
    });
  }

  /// How far the "tap it" demo is: 0 off, 1 on. Held on once done.
  double _toggle(double t) {
    if (widget.done) return 1;
    if (t < 0.35) return 0;
    if (t < 0.5) return Curves.easeOut.transform((t - 0.35) / 0.15);
    if (t < 0.9) return 1;
    return 1 - (t - 0.9) / 0.1;
  }

  Widget _iosCard(double t) {
    final enable = widget.step == 'enable';
    final on = _toggle(t);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _card([
        _row(icon: _SettingsIcon(Icons.keyboard_alt_outlined, const Color(0xFF8E8E93)), title: 'Keyboards', chevron: true),
      ]),
      const SizedBox(height: 10),
      _card([
        _row(
          icon: _GlyfAppIcon(),
          title: 'Glyf',
          toggle: enable ? on : 1,
          focus: enable,
          tapAt: enable ? t : null,
        ),
        _divider(),
        _row(
          icon: _SettingsIcon(Icons.lock_open_rounded, const Color(0xFF34C759)),
          title: 'Allow Full Access',
          toggle: enable ? 0 : on,
          focus: !enable,
          tapAt: enable ? null : t,
        ),
      ]),
    ]);
  }

  Widget _androidCard(double t) {
    final enable = widget.step == 'enable';
    final on = _toggle(t);
    if (enable) {
      return _card([
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(children: const [
            Text('On-screen keyboard', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Glass.inkSoft)),
          ]),
        ),
        _row(icon: _SettingsIcon(Icons.keyboard_rounded, const Color(0xFF4285F4)), title: 'Gboard', toggle: 1),
        _divider(),
        _row(icon: _GlyfAppIcon(), title: 'Glyf', toggle: on, focus: true, tapAt: t),
      ]);
    }
    // The system's keyboard picker, with Glyf being chosen.
    return _card([
      const Padding(
        padding: EdgeInsets.fromLTRB(18, 14, 18, 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('Choose input method', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Glass.ink)),
        ),
      ),
      _radio('Gboard', 1 - on),
      _radio('Glyf', on, focus: true, tapAt: t),
      const SizedBox(height: 6),
    ]);
  }

  Widget _card(List<Widget> children) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Glass.accent.withValues(alpha: 0.12), blurRadius: 28, offset: const Offset(0, 12)),
            const BoxShadow(color: Color(0x0F000000), blurRadius: 6, offset: Offset(0, 1)),
          ],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      );

  Widget _divider() => const Padding(
        padding: EdgeInsets.only(left: 56),
        child: Divider(height: 0.5, thickness: 0.5, color: Color(0x1F000000)),
      );

  Widget _row({
    required Widget icon,
    required String title,
    bool chevron = false,
    double? toggle,
    bool focus = false,
    double? tapAt,
  }) {
    return SizedBox(
      height: 50,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(children: [
          SizedBox(width: 30, height: 30, child: icon),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: focus ? FontWeight.w600 : FontWeight.w400,
                    color: Glass.ink)),
          ),
          if (chevron) const Icon(Icons.chevron_right_rounded, color: Color(0xFFC4C4C7)),
          if (toggle != null) _Switch(on: toggle, focus: focus && !widget.done, tapAt: widget.done ? null : tapAt),
        ]),
      ),
    );
  }

  Widget _radio(String title, double on, {bool focus = false, double? tapAt}) {
    return SizedBox(
      height: 48,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(children: [
          Stack(alignment: Alignment.center, children: [
            if (tapAt != null && !widget.done) _TapRing(t: tapAt, size: 38),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Color.lerp(const Color(0xFF8E8E93), Glass.accent, on)!, width: 2),
              ),
              alignment: Alignment.center,
              child: Container(
                width: 11 * on,
                height: 11 * on,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Glass.accent),
              ),
            ),
          ]),
          const SizedBox(width: 16),
          Text(title, style: TextStyle(fontSize: 16, fontWeight: focus ? FontWeight.w600 : FontWeight.w400, color: Glass.ink)),
        ]),
      ),
    );
  }
}

/// An iOS-style switch at any point between off (0) and on (1).
class _Switch extends StatelessWidget {
  const _Switch({required this.on, this.focus = false, this.tapAt});
  final double on;
  final bool focus;
  final double? tapAt;

  @override
  Widget build(BuildContext context) {
    return Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
      if (tapAt != null) Positioned(right: -4, child: _TapRing(t: tapAt!, size: 40)),
      Container(
        width: 51,
        height: 31,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Color.lerp(const Color(0xFFE9E9EA), const Color(0xFF34C759), on),
          boxShadow: focus ? [BoxShadow(color: Glass.accent.withValues(alpha: 0.35), spreadRadius: 3)] : null,
        ),
        child: Align(
          alignment: Alignment(-1 + 2 * on, 0),
          child: Container(
            width: 27,
            height: 27,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 2))],
            ),
          ),
        ),
      ),
    ]);
  }
}

/// A finger's tap: a ring that lands just before the switch flips.
class _TapRing extends StatelessWidget {
  const _TapRing({required this.t, required this.size});
  final double t;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (t < 0.25 || t > 0.55) return SizedBox(width: size, height: size);
    final p = (t - 0.25) / 0.3;
    return Opacity(
      opacity: (1 - p).clamp(0.0, 1.0),
      child: Container(
        width: size * (0.6 + 0.6 * p),
        height: size * (0.6 + 0.6 * p),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Glass.accent.withValues(alpha: 0.22),
          border: Border.all(color: Glass.accent.withValues(alpha: 0.6), width: 2),
        ),
      ),
    );
  }
}

class _SettingsIcon extends StatelessWidget {
  const _SettingsIcon(this.icon, this.color);
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(7)),
        child: Icon(icon, color: Colors.white, size: 19),
      );
}

class _GlyfAppIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: const Color(0x1A000000), width: 0.5),
        ),
        padding: const EdgeInsets.all(5),
        child: Image.asset('assets/brand/glyf-symbol.png', filterQuality: FilterQuality.high),
      );
}

/// The Glyf keyboard mid-thought: the strip offering an AI rewrite with a
/// shimmer running over it, keys lighting as they are typed, a glow under it.
class _AiKeyboard extends StatelessWidget {
  const _AiKeyboard({required this.width, required this.t});
  final double width;
  final double t;

  @override
  Widget build(BuildContext context) {
    final h = width * 0.66;
    return Container(
      width: width,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF2EFFF), Color(0xFFE3E4EC)],
        ),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(color: Glass.accent.withValues(alpha: 0.25), blurRadius: 40, spreadRadius: -4, offset: const Offset(0, 18)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(painter: _KeyboardPainter(t)),
    );
  }
}

class _KeyboardPainter extends CustomPainter {
  _KeyboardPainter(this.t);
  final double t;

  static const _typed = [13, 2, 22, 5, 17, 9, 12, 0];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final pad = w * 0.03;
    final stripH = h * 0.2;

    // Strip: the g pill, then the AI suggestion chip.
    final g = RRect.fromRectAndRadius(Rect.fromLTWH(pad, pad * 1.1, stripH * 0.95, stripH * 0.72), Radius.circular(stripH * 0.2));
    canvas.drawRRect(g, Paint()..color = const Color(0xFF141418));
    _text(canvas, 'g', g.center + Offset(-stripH * 0.02, -stripH * 0.04), stripH * 0.46, Colors.white, FontWeight.w700);
    canvas.drawCircle(Offset(g.right - stripH * 0.2, g.top + stripH * 0.18), stripH * 0.06, Paint()..color = Glass.accent);

    final chip = RRect.fromRectAndRadius(
        Rect.fromLTWH(g.right + pad, g.top, w - g.right - pad * 2, g.height), Radius.circular(g.height / 2));
    canvas.drawRRect(chip, Paint()..color = Colors.white);
    canvas.drawRRect(chip, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..shader = SweepGradient(
        transform: GradientRotation(t * 2 * math.pi),
        colors: const [Color(0xFF7C5CFF), Color(0xFF5AB8FF), Color(0xFFFF7AC6), Color(0xFF7C5CFF)],
      ).createShader(chip.outerRect));
    _sparkle(canvas, Offset(chip.left + chip.height * 0.55, chip.center.dy), chip.height * 0.26, Glass.accent);
    _text(canvas, 'Make it sound polite', Offset(chip.left + chip.width * 0.5 + chip.height * 0.2, chip.center.dy),
        stripH * 0.3, Glass.ink, FontWeight.w600);

    // Keys: 10 / 9 / 7 with shift and delete / space row.
    final top = stripH + pad * 0.6;
    final rowGap = h * 0.025;
    final keyH = (h - top - pad - rowGap * 3) / 4;
    final gap = w * 0.012;
    final unit = (w - pad * 2 - gap * 9) / 10;
    final keyPaint = Paint()..color = Colors.white;
    final fnPaint = Paint()..color = const Color(0xFFC9CAD4);
    final lit = _typed[(t * _typed.length).floor() % _typed.length];
    var index = 0;
    RRect key(double x, double y, double kw) =>
        RRect.fromRectAndRadius(Rect.fromLTWH(x, y, kw, keyH), Radius.circular(unit * 0.18));
    void letter(double x, double y) {
      final r = key(x, y, unit);
      canvas.drawRRect(r.shift(const Offset(0, 1)), Paint()..color = const Color(0x22000000));
      final isLit = index == lit;
      canvas.drawRRect(r, isLit ? (Paint()..color = const Color(0xFFE4DCFF)) : keyPaint);
      index++;
    }

    var y = top;
    for (var i = 0; i < 10; i++) {
      letter(pad + i * (unit + gap), y);
    }
    y += keyH + rowGap;
    for (var i = 0; i < 9; i++) {
      letter(pad + (unit + gap) / 2 + i * (unit + gap), y);
    }
    y += keyH + rowGap;
    final side = unit * 1.35;
    canvas.drawRRect(key(pad, y, side), fnPaint);
    final lettersX = (w - (unit * 7 + gap * 6)) / 2;
    for (var i = 0; i < 7; i++) {
      letter(lettersX + i * (unit + gap), y);
    }
    canvas.drawRRect(key(w - pad - side, y, side), fnPaint);
    y += keyH + rowGap;
    final mode = unit * 2.3;
    canvas.drawRRect(key(pad, y, mode), fnPaint);
    canvas.drawRRect(key(w - pad - mode, y, mode), fnPaint);
    final space = key(pad + mode + gap, y, w - pad * 2 - mode * 2 - gap * 2);
    canvas.drawRRect(space, keyPaint);
    _text(canvas, 'glyf', space.center, keyH * 0.42, const Color(0x55000000), FontWeight.w600);

    // The AI shimmer: a soft band of colour sweeping across the keys.
    final sweep = (t * 1.4) % 1.4 - 0.2;
    final band = Rect.fromLTWH(w * sweep - w * 0.25, 0, w * 0.5, h);
    canvas.drawRect(
      Rect.fromLTWH(0, top, w, h - top),
      Paint()
        ..blendMode = BlendMode.srcATop
        ..shader = LinearGradient(colors: [
          Glass.accent.withValues(alpha: 0),
          Glass.accent.withValues(alpha: 0.12),
          const Color(0xFF5AB8FF).withValues(alpha: 0.10),
          Glass.accent.withValues(alpha: 0),
        ]).createShader(band),
    );
  }

  void _sparkle(Canvas canvas, Offset c, double r, Color color) {
    final k = r * 0.28;
    final p = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + k, c.dy - k, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx + k, c.dy + k, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - k, c.dy + k, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx - k, c.dy - k, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }

  void _text(Canvas canvas, String s, Offset center, double size, Color color, FontWeight weight) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: size, color: color, fontWeight: weight, height: 1, fontFamily: 'Inter')),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_KeyboardPainter old) => old.t != t;
}
