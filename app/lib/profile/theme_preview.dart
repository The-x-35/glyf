import 'dart:math' as math;
import 'dart:typed_data' show Float64List;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../core/themes.dart';

/// The finish textures (assets/themes/textures, the same files the Android
/// keyboard reads from flutter_assets), decoded once for the picker.
class KbTextures {
  KbTextures._();

  static final Map<String, ui.Image> images = {};
  static Future<void>? _loading;

  /// Loads every texture a theme names; a missing one is left out (its key
  /// draws without grain), never an error.
  static Future<void> load() => _loading ??= _load();

  static Future<void> _load() async {
    for (final name in kbTextureNames) {
      try {
        final data = await rootBundle.load('assets/themes/textures/$name.png');
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        images[name] = (await codec.getNextFrame()).image;
      } catch (_) {}
    }
  }
}

/// A theme's keyboard in miniature, drawn the way tools/theme_mock.py draws
/// the real one, simplified: each key's face (fill or fill to fill2, its
/// texture, sheen, metal, gloss, highlight; Typewriter's round caps in their
/// bezel), the theme's 1pt edge and border, the letters in its font and
/// legend (engraved, letterpress, foil, glow), and its ornaments.
class ThemeKeyboardPainter extends CustomPainter {
  ThemeKeyboardPainter(this.v,
      {required this.dark,
      required this.fontFamily,
      required this.fontWeight,
      required this.variableFont,
      required this.textures,
      required this.dpr});

  final KbVariant v;
  final bool dark;
  final String? fontFamily;
  final int fontWeight;
  final bool variableFont;
  final Map<String, ui.Image> textures;
  final double dpr;

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 2.2;
    final unit = (size.width - gap * 9) / 10;
    var keyH = unit * 1.32;
    final rowsH = keyH * 4 + gap * 3 * 1.6;
    if (rowsH > size.height) keyH *= size.height / rowsH;
    final rowGap = gap * 1.6;
    final top = (size.height - (keyH * 4 + rowGap * 3)) / 2;
    // The real keyboard's points, scaled to this one (its keys are 45 tall).
    final s = keyH / 45;
    final radius = unit * 0.22;

    void key(double x, double y, double w, String cls, String on, {String? label}) {
      final rect = Rect.fromLTWH(x, y, w, keyH);
      final o = on == 'shift' ? v.shift : on == 'delete' ? v.delete : null;
      final fill = o?.fill ??
          switch (cls) {
            'letter' => v.letter.fill,
            'space' => v.space.fill,
            'return' => v.returnPrimary.fill,
            _ => v.function.fill,
          };
      final ink = switch (cls) {
        'return' => v.returnPrimary.glyph!,
        'function' => o?.glyph ?? v.functionGlyph,
        _ => v.keyText,
      };
      final f = v.style.face(cls);
      _face(canvas, rect, radius, f, fill, cls, s);
      _ornaments(canvas, rect, radius, cls, on, fill);
      // The return's arrow in its own legend (engraved), never foil or glow.
      if (label != null) {
        _legend(canvas, label, rect.center, keyH * (cls == 'return' ? 0.55 : 0.5), ink, fill, s,
            cls == 'return' ? v.style.returnLegend : v.style.legend,
            family: cls == 'return' ? null : fontFamily);
      }
    }

    var y = top;
    const top1 = 'qwertyuiop', top2 = 'asdfghjkl', top3 = 'zxcvbnm';
    for (var i = 0; i < 10; i++) {
      key(i * (unit + gap), y, unit, 'letter', 'letter', label: top1[i]);
    }
    y += keyH + rowGap;
    final inset = (unit + gap) / 2;
    for (var i = 0; i < 9; i++) {
      key(inset + i * (unit + gap), y, unit, 'letter', 'letter', label: top2[i]);
    }
    y += keyH + rowGap;
    final side = unit * 1.4;
    key(0, y, side, 'function', 'shift');
    final lettersX = (size.width - (unit * 7 + gap * 6)) / 2;
    for (var i = 0; i < 7; i++) {
      key(lettersX + i * (unit + gap), y, unit, 'letter', 'letter', label: top3[i]);
    }
    key(size.width - side, y, side, 'function', 'delete');
    y += keyH + rowGap;
    final mode = unit * 2.2;
    key(0, y, mode, 'function', 'function');
    key(size.width - mode, y, mode, 'return', 'return', label: '\u21B5');
    key(mode + gap, y, size.width - mode * 2 - gap * 2, 'space', 'space');
  }

  Paint? _texture(KbFace f) {
    final img = f.texture == null ? null : textures[f.texture];
    if (img == null) return null;
    // One image pixel per device pixel, as on the keyboard.
    final m = Matrix4Storage.scale(1 / dpr);
    return Paint()
      ..shader = ImageShader(img, TileMode.repeated, TileMode.repeated, m)
      ..color = Color.fromRGBO(0, 0, 0, f.textureAlpha.clamp(0, 1).toDouble());
  }

  static Color _white(double a) => Color.fromRGBO(255, 255, 255, a.clamp(0, 1).toDouble());
  static Color _black(double a) => Color.fromRGBO(0, 0, 0, a.clamp(0, 1).toDouble());

  void _face(Canvas c, Rect r, double radius, KbFace f, Color fill, String cls, double s) {
    if (f.round) {
      final cx = r.center.dx, cy = r.center.dy;
      final big = math.min(r.width, r.height) / 2;
      c.drawCircle(Offset(cx, cy + 1.4 * s), big, Paint()..color = _black(dark ? 0.6 : 0.3));
      c.drawCircle(
          Offset(cx, cy),
          big,
          Paint()
            ..shader = ui.Gradient.linear(Offset(cx, cy - big), Offset(cx, cy + big), [
              const Color(0xFFF4F4F2),
              f.ring ?? const Color(0xFFA9A9A4),
              const Color(0xFF6E6E6A),
              const Color(0xFFD8D8D4),
            ], const [0, 0.45, 0.55, 1]));
      final ri = big - 2.4 * s;
      final cap = Offset(cx, cy);
      c.drawCircle(cap, ri, Paint()..color = fill);
      final t = _texture(f);
      if (t != null) c.drawCircle(cap, ri, t);
      c.drawCircle(
          cap,
          ri,
          Paint()
            ..shader = ui.Gradient.radial(cap, ri, [
              _white(f.gloss),
              _white(0),
              _black(f.sheenBottom + 0.06),
            ], const [0, 0.7, 1], TileMode.clamp, null, Offset(cx, cy - ri * 0.35), ri * 0.1));
      return;
    }
    final rr = RRect.fromRectAndRadius(r, Radius.circular(radius));
    final sh = v.shadow;
    if (sh.radius == 0 && sh.offsetY > 0 && sh.alpha > 0) {
      c.drawRRect(rr.shift(Offset(0, 1.0 * s)), Paint()..color = sh.color.withValues(alpha: sh.alpha));
    }
    c.save();
    c.clipRRect(rr);
    final p = Paint();
    if (f.fill2 != null) {
      p.shader = ui.Gradient.linear(r.topLeft, r.bottomRight, [fill, f.fill2!]);
    } else {
      p.color = fill;
    }
    c.drawRect(r, p);
    final t = _texture(f);
    if (t != null) c.drawRect(r, t);
    if (f.sheenTop > 0 || f.sheenBottom > 0) {
      c.drawRect(
          r,
          Paint()
            ..shader = ui.Gradient.linear(r.topLeft, r.bottomLeft,
                [_white(f.sheenTop), _white(0), _black(0), _black(f.sheenBottom)], const [0, 0.5, 0.5, 1]));
    }
    if (f.metal > 0) {
      for (final (at, half) in const [(0.22, 0.10), (0.58, 0.16), (0.84, 0.08)]) {
        final band = Rect.fromLTRB(r.left, r.top + r.height * (at - half), r.right, r.top + r.height * (at + half));
        c.drawRect(
            band,
            Paint()
              ..shader = ui.Gradient.linear(band.topLeft, band.bottomLeft,
                  [_white(0), _white(f.metal), _white(0)], const [0, 0.5, 1]));
      }
    }
    if (f.gloss > 0) {
      final g = Rect.fromLTWH(r.left, r.top, r.width, r.height * 0.48);
      c.drawRect(g, Paint()..shader = ui.Gradient.linear(g.topLeft, g.bottomLeft, [_white(f.gloss), _white(0)]));
    }
    if (f.highlight > 0) {
      c.drawRect(Rect.fromLTWH(r.left, r.top, r.width, 1 / dpr), Paint()..color = _white(f.highlight));
    }
    c.restore();
    final b = v.border;
    if (b != null && b.appliesTo.contains(cls)) {
      c.drawRRect(
          rr.deflate(0.4),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8
            ..color = b.color);
    }
  }

  Color _role(String role, String cls, Color fill) {
    if (role.startsWith('#')) {
      return Color(int.parse('FF${role.substring(1)}', radix: 16));
    }
    return switch (role) {
      'ink' => cls == 'function' ? v.functionGlyph : v.keyText,
      'fnInk' => v.functionGlyph,
      'accent' => v.returnPrimary.fill,
      'accentInk' => v.returnPrimary.glyph!,
      'fill' => fill,
      _ => v.keyText,
    };
  }

  void _ornaments(Canvas c, Rect r, double radius, String cls, String on, Color fill) {
    final h = r.height;
    for (final o in v.style.ornaments) {
      if (!(o.on == on || (o.on == 'function' && cls == 'function' && on != 'return'))) continue;
      final ax = switch (o.anchor) { 'left' => r.left, 'right' => r.right, _ => r.center.dx };
      double X(double u) => ax + u * h;
      double Y(double u) => r.top + u * h;
      c.save();
      c.clipRRect(RRect.fromRectAndRadius(r, Radius.circular(radius)));
      for (final op in o.ops) {
        final col = _role(op.color ?? o.color, cls, fill);
        final alpha = (op.color?.startsWith('#') ?? false) && o.alpha < 0.9 ? math.max(o.alpha, 0.9) : o.alpha;
        final paint = Paint()
          ..color = col.withValues(alpha: alpha)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;
        if (op.w > 0) {
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = op.w * h;
        }
        final q = op.p;
        switch (op.t) {
          case 'line':
            c.drawLine(Offset(X(q[0]), Y(q[1])), Offset(X(q[2]), Y(q[3])), paint);
          case 'poly':
            final path = Path()..moveTo(X(q[0]), Y(q[1]));
            for (var i = 2; i + 1 < q.length; i += 2) {
              path.lineTo(X(q[i]), Y(q[i + 1]));
            }
            c.drawPath(path..close(), paint..style = PaintingStyle.fill);
          case 'circle':
            c.drawCircle(Offset(X(q[0]), Y(q[1])), q[2] * h, paint);
          case 'rect':
            c.drawRRect(
                RRect.fromRectAndRadius(Rect.fromLTWH(X(q[0]), Y(q[1]), q[2] * h, q[3] * h),
                    Radius.circular(math.max(0.01, q[4] * h))),
                paint);
          case 'text':
            final tp = TextPainter(
                text: TextSpan(
                    // Suits and dingbats in their text form, never emoji.
                    text: op.s?.replaceAllMapped(RegExp('[\u2600-\u27BF]'), (m) => '${m[0]}\uFE0E'),
                    style: TextStyle(
                        color: col.withValues(alpha: alpha),
                        fontSize: op.size * h,
                        letterSpacing: op.tracking * op.size * h,
                        fontWeight: FontWeight.values[((op.weight ~/ 100) - 1).clamp(0, 8)],
                        fontFamily: switch (op.font) {
                          'mono' => 'monospace',
                          'theme' => fontFamily,
                          _ => null,
                        })),
                textDirection: TextDirection.ltr)
              ..layout();
            tp.paint(c, Offset(X(q[0]) - tp.width / 2, Y(q[1]) - tp.height / 2));
        }
      }
      c.restore();
    }
  }

  static double _lum(Color c) {
    double ch(double v) => v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }

  /// Canvas's shadowBlur is twice the sigma; Flutter's blurRadius r has
  /// sigma 0.57735 r + 0.5.
  static double _blur(double canvasBlur) => math.max(0, (canvasBlur / 2 - 0.5) / 0.57735);

  void _legend(Canvas c, String text, Offset at, double size, Color ink, Color fill, double s, KbLegend lg,
      {String? family}) {
    TextStyle style(Color? color, {Paint? fg, List<Shadow>? shadows}) => TextStyle(
        color: fg == null ? color : null,
        foreground: fg,
        shadows: shadows,
        fontSize: size,
        height: 1,
        fontFamily: family,
        fontVariations: variableFont && family != null ? [FontVariation('wght', fontWeight.toDouble())] : null);
    void draw(TextStyle st, double dy) {
      final tp = TextPainter(text: TextSpan(text: text, style: st), textDirection: TextDirection.ltr)..layout();
      tp.paint(c, Offset(at.dx - tp.width / 2, at.dy - tp.height / 2 + dy));
    }

    final light = _lum(fill) > 0.45;
    switch (lg.style) {
      case 'engraved':
      case 'letterpress':
        draw(style(light ? _white(0.75) : _black(0.6)), light ? 0.7 * s : -0.6 * s);
        draw(
            style(ink,
                shadows: lg.style == 'letterpress'
                    ? [Shadow(color: ink.withValues(alpha: 0.55), blurRadius: _blur(0.6 * s))]
                    : null),
            0);
      case 'foil':
        draw(style(_black(0.45)), -0.6 * s);
        final foil = lg.foil ?? [ink, ink, ink];
        final fg = Paint()
          ..shader = ui.Gradient.linear(
              Offset(0, at.dy - size * 0.35), Offset(0, at.dy + size * 0.3), foil, const [0, 0.55, 1]);
        draw(style(null, fg: fg), 0);
      case 'glow':
        final g = lg.glow == null || lg.glow == 'self'
            ? ink
            : Color(int.parse('FF${lg.glow!.substring(1)}', radix: 16));
        final shadow = Shadow(color: g.withValues(alpha: 0.9), blurRadius: _blur(6 * s));
        draw(style(ink, shadows: [shadow, shadow]), 0);
      default:
        draw(style(ink), 0);
    }
  }

  @override
  bool shouldRepaint(ThemeKeyboardPainter old) =>
      old.v != v || old.textures.length != textures.length || old.dpr != dpr || old.dark != dark;
}

/// A uniform scale as the column-major list ImageShader takes.
class Matrix4Storage {
  static Float64List scale(double k) =>
      Float64List.fromList([k, 0, 0, 0, 0, k, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);
}
