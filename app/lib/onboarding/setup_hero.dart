import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// The Glyf keyboard mid-thought, for the setup steps: an AI rewrite on offer
/// in the strip with light running round it, keys lighting as they are typed.
class AiKeyboard extends StatefulWidget {
  const AiKeyboard({super.key});

  @override
  State<AiKeyboard> createState() => _AiKeyboardState();
}

class _AiKeyboardState extends State<AiKeyboard> with SingleTickerProviderStateMixin {
  late final AnimationController _loop =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))..repeat();

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return LayoutBuilder(builder: (context, box) {
      final w = math.min(box.maxWidth, 380.0);
      return Center(
        child: still
            ? _AiKeyboard(width: w, t: 0.2)
            : AnimatedBuilder(
                animation: _loop,
                builder: (context, _) => _AiKeyboard(width: w, t: _loop.value),
              ),
      );
    });
  }
}

/// What a setup step still needs, as a list that ticks itself off. The
/// switches live in Settings; drawing fakes of them here only asked to be
/// flipped, so each row just shows where it stands.
class SetupChecklist extends StatelessWidget {
  const SetupChecklist({super.key, required this.step, required this.done, required this.android});

  /// 'enable' (add the keyboard) or 'access' (Full Access / switch to it).
  final String step;
  final bool done;
  final bool android;

  @override
  Widget build(BuildContext context) {
    final enable = step == 'enable';
    final header = !android ? 'In Settings' : (enable ? 'On-screen keyboard' : 'Choose input method');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 8),
          child: Text(header,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Glass.inkSoft)),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 18, offset: Offset(0, 6))],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: _rows(enable)),
        ),
      ],
    );
  }

  List<Widget> _rows(bool enable) {
    if (!android) {
      // Full Access comes after the keyboard itself, so on the first step
      // the keyboard is the only thing that can be ticked.
      return [
        _row(icon: _GlyfAppIcon(), title: 'Glyf keyboard', done: enable ? done : true),
        _divider(),
        _row(
          icon: const _SettingsIcon(Icons.lock_open_rounded, Color(0xFF34C759)),
          title: 'Allow Full Access',
          done: !enable && done,
        ),
      ];
    }
    return [
      _row(
        icon: _GlyfAppIcon(),
        title: enable ? 'Glyf keyboard' : 'Glyf in use',
        done: done,
      ),
    ];
  }

  Widget _divider() => const Padding(
        padding: EdgeInsets.only(left: 58),
        child: Divider(height: 0.5, thickness: 0.5, color: Color(0x1F000000)),
      );

  Widget _row({required Widget icon, required String title, required bool done}) {
    return SizedBox(
      height: 54,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(children: [
          SizedBox(width: 30, height: 30, child: icon),
          const SizedBox(width: 14),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 16, color: Glass.ink))),
          _Mark(done: done),
        ]),
      ),
    );
  }
}

/// Where one thing stands: an empty ring until the phone reports it on, then
/// a tick that lands as soon as it is.
class _Mark extends StatelessWidget {
  const _Mark({required this.done});
  final bool done;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: done ? 1 : 0),
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutBack,
      builder: (context, t, _) => SizedBox(
        width: 26,
        height: 26,
        child: Stack(alignment: Alignment.center, children: [
          Opacity(
            opacity: (1 - t).clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFD6D9E0), width: 1.6),
              ),
            ),
          ),
          if (t > 0.01)
            Transform.scale(
              scale: t.clamp(0.0, 1.2),
              child: Container(
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Glass.success),
                child: const Icon(Icons.check_rounded, size: 17, color: Colors.white),
              ),
            ),
        ]),
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
