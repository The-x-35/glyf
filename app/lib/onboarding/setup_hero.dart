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

/// The two things Glyf needs from the phone, as a list that ticks itself
/// off. Each row that isn't done yet is the button for it — tapping it opens
/// the place that turns it on — and a tick lands the moment the phone says so.
class SetupChecklist extends StatelessWidget {
  const SetupChecklist({
    super.key,
    required this.android,
    required this.keyboardOn,
    required this.inUseOn,
    required this.onKeyboard,
    required this.onInUse,
  });

  final bool android;

  /// Glyf is one of the phone's keyboards.
  final bool keyboardOn;

  /// iPhone: Full Access is on. Android: Glyf is the keyboard in use.
  final bool inUseOn;

  final VoidCallback onKeyboard;
  final VoidCallback onInUse;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 8),
          // iOS gives apps no way into a Settings page any more, so the
          // shortest way there is written down: both switches live together
          // under the app, not under General.
          child: Text(android ? 'On this phone' : 'Settings › Apps › Glyf › Keyboards',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Glass.inkSoft)),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 18, offset: Offset(0, 6))],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _row(
              id: 'onb:setup:keyboard',
              icon: _GlyfAppIcon(),
              title: 'Glyf keyboard',
              done: keyboardOn,
              action: 'Open',
              onTap: onKeyboard,
            ),
            _divider(),
            _row(
              id: 'onb:setup:in-use',
              icon: android
                  ? const _SettingsIcon(Icons.keyboard_rounded, Glass.accent)
                  : const _SettingsIcon(Icons.lock_open_rounded, Color(0xFF34C759)),
              title: android ? 'Glyf in use' : 'Allow Full Access',
              done: inUseOn,
              action: android ? 'Choose' : 'Open',
              onTap: onInUse,
              // The switch only exists once the keyboard is added, so the row
              // waits its turn rather than sending anyone to look for it.
              waiting: !keyboardOn,
            ),
          ]),
        ),
      ],
    );
  }

  Widget _divider() => const Padding(
        padding: EdgeInsets.only(left: 58),
        child: Divider(height: 0.5, thickness: 0.5, color: Color(0x1F000000)),
      );

  Widget _row({
    required String id,
    required Widget icon,
    required String title,
    required bool done,
    required String action,
    required VoidCallback onTap,
    String? hint,
    bool waiting = false,
  }) {
    final showHint = hint != null && !done;
    final row = SizedBox(
      height: showHint ? 64 : 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Opacity(
          opacity: waiting ? 0.45 : 1,
          child: Row(children: [
            SizedBox(width: 30, height: 30, child: icon),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16, color: Glass.ink)),
                  if (showHint)
                    Text(hint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, color: Glass.inkSoft)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (waiting)
              const _Ring()
            else
              _Mark(done: done, action: action),
          ]),
        ),
      ),
    );
    if (done || waiting) return row;
    return Semantics(
      identifier: id,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(onTap: onTap, child: row),
      ),
    );
  }
}

/// A row whose turn hasn't come: nothing to do here yet.
class _Ring extends StatelessWidget {
  const _Ring();

  @override
  Widget build(BuildContext context) => Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFD6D9E0), width: 1.6),
        ),
      );
}

/// Where one thing stands: what to tap until the phone reports it on, then a
/// tick that lands the moment it is.
class _Mark extends StatelessWidget {
  const _Mark({required this.done, required this.action});
  final bool done;
  final String action;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutBack,
      transitionBuilder: (child, anim) =>
          ScaleTransition(scale: anim, child: FadeTransition(opacity: anim, child: child)),
      child: done
          ? Container(
              key: const ValueKey('on'),
              width: 26,
              height: 26,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Glass.success),
              child: const Icon(Icons.check_rounded, size: 17, color: Colors.white),
            )
          : Row(key: const ValueKey('off'), mainAxisSize: MainAxisSize.min, children: [
              Text(action,
                  style: const TextStyle(
                      fontSize: 14.5, color: Glass.accent, fontWeight: FontWeight.w700)),
              const Icon(Icons.chevron_right_rounded, size: 20, color: Glass.accent),
            ]),
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
