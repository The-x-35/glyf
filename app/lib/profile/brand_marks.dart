import 'package:flutter/material.dart';

/// Logos for the tools Glyf connects to, drawn in code so no image ships and
/// nothing is fetched. Each sits on a rounded tile the size it is given.
class BrandMark extends StatelessWidget {
  const BrandMark(this.brand, {super.key, this.size = 44});

  /// magicblock | calendar | contacts | gmail | gcal | meet | notion | slack |
  /// spotify | calcom | calendly | booking
  final String brand;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (bg, border) = switch (brand) {
      'magicblock' => (const Color(0xFF111111), null),
      'calcom' => (const Color(0xFF111111), null),
      'notion' => (Colors.white, const Color(0x22000000)),
      'spotify' => (const Color(0xFF121212), null),
      'contacts' => (const Color(0xFFE9EAEE), null),
      _ => (Colors.white, const Color(0x1A000000)),
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(size * 0.26),
        border: border == null ? null : Border.all(color: border, width: 0.8),
      ),
      clipBehavior: Clip.antiAlias,
      child: switch (brand) {
        'calendar' => _PhoneCalendar(size),
        'meet' => Center(child: GoogleMeetMark(size: size * 0.58)),
        _ => CustomPaint(painter: _MarkPainter(brand)),
      },
    );
  }
}

class _PhoneCalendar extends StatelessWidget {
  const _PhoneCalendar(this.size);
  final double size;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(days[now.weekday - 1],
          style: TextStyle(fontSize: size * 0.2, height: 1, fontWeight: FontWeight.w700, color: const Color(0xFFFF3B30))),
      SizedBox(height: size * 0.02),
      Text('${now.day}',
          style: TextStyle(fontSize: size * 0.46, height: 1, fontWeight: FontWeight.w400, color: Colors.black, letterSpacing: -1)),
    ]);
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.brand);
  final String brand;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    Paint fill(Color c) => Paint()..color = c..isAntiAlias = true;
    switch (brand) {
      case 'magicblock':
        // MagicBlock's mark (tryglyf.com brands), on its black tile.
        canvas.save();
        canvas.translate(s * 0.14, s * 0.14);
        canvas.scale(s * 0.72 / 32);
        for (final d in _magicBlock) {
          canvas.drawPath(svgPath(d), fill(Colors.white));
        }
        canvas.restore();
      case 'gmail':
        final l = s * 0.18, r = s * 0.82, t = s * 0.27, b = s * 0.75;
        final w = s * 0.12;
        canvas.drawRRect(RRect.fromLTRBR(l, t, l + w, b, Radius.circular(s * 0.03)), fill(const Color(0xFF4285F4)));
        canvas.drawRRect(RRect.fromLTRBR(r - w, t, r, b, Radius.circular(s * 0.03)), fill(const Color(0xFF34A853)));
        final red = Path()
          ..moveTo(l, t)
          ..lineTo(s / 2, s * 0.52)
          ..lineTo(r, t)
          ..lineTo(r, t + w * 1.1)
          ..lineTo(s / 2, s * 0.64)
          ..lineTo(l, t + w * 1.1)
          ..close();
        canvas.drawPath(red, fill(const Color(0xFFEA4335)));
        canvas.drawPath(
            Path()
              ..moveTo(r - w, t + w * 0.35)
              ..lineTo(r, t)
              ..lineTo(r, t + w * 1.1)
              ..lineTo(r - w, t + w * 1.8)
              ..close(),
            fill(const Color(0xFFFBBC04)));
        canvas.drawPath(
            Path()
              ..moveTo(l, t)
              ..lineTo(l + w, t + w * 0.35)
              ..lineTo(l + w, t + w * 1.8)
              ..lineTo(l, t + w * 1.1)
              ..close(),
            fill(const Color(0xFFC5221F)));
      case 'gcal':
        final r = RRect.fromLTRBR(s * 0.2, s * 0.2, s * 0.8, s * 0.8, Radius.circular(s * 0.08));
        canvas.drawRRect(r, fill(Colors.white));
        canvas.drawRRect(r, Paint()..color = const Color(0xFF4285F4)..style = PaintingStyle.stroke..strokeWidth = s * 0.06);
        canvas.drawRect(Rect.fromLTRB(s * 0.2, s * 0.2, s * 0.8, s * 0.34), fill(const Color(0xFF4285F4)));
        _text(canvas, '31', Offset(s / 2, s * 0.57), s * 0.26, const Color(0xFF1967D2), FontWeight.w700);
      case 'notion':
        _text(canvas, 'N', Offset(s / 2, s / 2 + s * 0.01), s * 0.58, Colors.black, FontWeight.w800, serif: true);
      case 'slack':
        const colors = [Color(0xFF36C5F0), Color(0xFF2EB67D), Color(0xFFECB22E), Color(0xFFE01E5A)];
        final w = s * 0.12, len = s * 0.42, c = s / 2, gap = s * 0.09;
        canvas.drawRRect(RRect.fromLTRBR(c - gap - w, c - len / 2 - gap, c - gap, c + len / 2 - gap, Radius.circular(w / 2)), fill(colors[0]));
        canvas.drawRRect(RRect.fromLTRBR(c - len / 2 + gap, c - gap - w, c + len / 2 + gap, c - gap, Radius.circular(w / 2)), fill(colors[1]));
        canvas.drawRRect(RRect.fromLTRBR(c + gap, c - len / 2 + gap, c + gap + w, c + len / 2 + gap, Radius.circular(w / 2)), fill(colors[2]));
        canvas.drawRRect(RRect.fromLTRBR(c - len / 2 - gap, c + gap, c + len / 2 - gap, c + gap + w, Radius.circular(w / 2)), fill(colors[3]));
      case 'spotify':
        canvas.drawCircle(Offset(s / 2, s / 2), s * 0.34, fill(const Color(0xFF1ED760)));
        final arc = Paint()
          ..color = Colors.black
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
        for (final (y, w, t) in [(0.40, 0.40, 0.055), (0.52, 0.34, 0.048), (0.63, 0.27, 0.04)]) {
          arc.strokeWidth = s * t;
          final rect = Rect.fromCenter(center: Offset(s / 2, s * y + s * 0.12), width: s * w * 1.4, height: s * 0.3);
          canvas.drawArc(rect, 3.14159 * 1.18, 3.14159 * 0.64, false, arc);
        }
      case 'calcom':
        // Cal.com's wordmark, white on its black tile.
        _text(canvas, 'Cal', Offset(s / 2, s / 2 + s * 0.01), s * 0.36, Colors.white, FontWeight.w800);
      case 'calendly':
        // Calendly's blue ring, open on the right like its C.
        final ring = Paint()
          ..color = const Color(0xFF006BFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.12
          ..strokeCap = StrokeCap.round;
        canvas.drawArc(Rect.fromCircle(center: Offset(s / 2, s / 2), radius: s * 0.24),
            3.14159 * 0.28, 3.14159 * 1.44, false, ring);
      case 'booking':
        // Two links of a chain: a page people book from.
        final link = Paint()
          ..color = const Color(0xFF1C1C1E)
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.07;
        canvas.save();
        canvas.translate(s / 2, s / 2);
        canvas.rotate(-0.785);
        canvas.drawRRect(RRect.fromLTRBR(-s * 0.3, -s * 0.1, s * 0.02, s * 0.1, Radius.circular(s * 0.1)), link);
        canvas.drawRRect(RRect.fromLTRBR(-s * 0.02, -s * 0.1, s * 0.3, s * 0.1, Radius.circular(s * 0.1)), link);
        canvas.restore();
      case 'contacts':
        canvas.drawCircle(Offset(s / 2, s * 0.4), s * 0.14, fill(const Color(0xFF8E8E93)));
        canvas.drawOval(Rect.fromLTRB(s * 0.24, s * 0.58, s * 0.76, s * 0.92), fill(const Color(0xFF8E8E93)));
    }
  }

  void _text(Canvas canvas, String text, Offset center, double size, Color color, FontWeight weight,
      {bool serif = false}) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(fontSize: size, color: color, fontWeight: weight, height: 1, fontFamily: serif ? 'Georgia' : null)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.brand != brand;
}

const _magicBlock = [
  'M8.05507 9.70891C8.27906 10.2925 8.7056 10.6964 9.2287 10.9191C9.59622 11.0748 10.012 11.068 10.3836 10.9218C11.804 10.365 13.317 9.8632 14.889 9.4352C16.7534 8.92669 18.6004 8.54699 20.3628 8.3028L8.69084 3.10371C7.87131 2.74816 6.95654 3.35058 6.95923 4.24416L6.98069 12.4272C7.87399 11.8529 8.34076 10.7688 8.05641 9.70891H8.05507Z',
  'M31.4071 11.2009C31.0758 9.98395 29.2073 9.1682 26.2806 8.96024C24.9876 8.869 23.5511 8.89986 22.026 9.04342C19.8598 9.2487 17.5152 9.68207 15.1331 10.3315C13.718 10.7179 12.3539 11.1633 11.0649 11.6544C10.8745 11.7268 10.6867 11.7993 10.5003 11.8744C10.1944 11.9952 9.93154 12.2098 9.76388 12.4916C9.45404 13.0149 9.3521 13.6441 9.54391 14.2895C9.44331 14.0064 9.30516 13.7783 9.1375 13.5998C8.67475 13.1061 7.92362 13.0108 7.32406 13.3248C6.416 13.7998 5.57903 14.2962 4.83461 14.8101C3.70658 15.5869 2.50746 16.5234 1.84217 17.7524C1.63025 18.1455 1.47198 18.591 1.50417 19.0431C1.54843 19.6616 1.9468 20.087 2.43235 20.4318C2.69256 20.6169 2.97423 20.7726 3.26932 20.8947C4.20018 21.2811 5.26114 21.4582 6.26712 21.5508V18.9666C6.26712 18.7144 6.45624 18.489 6.70706 18.4769C6.97532 18.4635 7.19664 18.6755 7.19664 18.9412C7.19664 18.9412 7.19664 21.9747 7.19664 21.9734V25.3115C7.19664 25.8885 7.50648 26.4278 8.00544 26.7177L14.2183 30.3309C14.4678 30.4758 14.7522 30.5509 15.0379 30.5509C15.2471 30.5509 15.4564 30.5106 15.6535 30.4301L24.7556 26.6989C25.3685 26.448 25.7656 25.8563 25.7656 25.1935V17.1486L25.8675 17.1003C29.7197 15.0435 31.8416 12.7881 31.4084 11.2009H31.4071ZM19.263 20.4573C19.263 21.4059 18.9612 21.9573 18.426 21.9573C17.8908 21.9573 17.5367 21.4474 17.5367 20.2855V18.438C17.5367 17.4894 17.8385 16.938 18.3737 16.938C18.9089 16.938 19.263 17.4478 19.263 18.6098V20.4573ZM22.9918 19.5288C22.9918 20.4774 22.69 21.0288 22.1548 21.0288C21.6196 21.0288 21.2655 20.519 21.2655 19.3571V17.5096C21.2655 16.561 21.5673 16.0095 22.1025 16.0095C22.6377 16.0095 22.9918 16.5194 22.9918 17.6813V19.5288Z',
];

/// SVG path data (M L H V C S Q Z, absolute or relative) to a Flutter Path.
Path svgPath(String d, {PathFillType fill = PathFillType.evenOdd}) {
  final path = Path()..fillType = fill;
  final tokens = RegExp(r'[MmLlHhVvCcSsQqZz]|-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?')
      .allMatches(d)
      .map((m) => m.group(0)!)
      .toList();
  bool isCmd(String t) => RegExp(r'^[A-Za-z]$').hasMatch(t);
  var i = 0;
  var cmd = 'M';
  var x = 0.0, y = 0.0, sx = 0.0, sy = 0.0;
  // The last cubic control point, for S (smooth) curves.
  double? cx2, cy2;
  double next() => double.parse(tokens[i++]);
  while (i < tokens.length) {
    if (isCmd(tokens[i])) cmd = tokens[i++];
    final rel = cmd == cmd.toLowerCase();
    final ox = rel ? x : 0.0, oy = rel ? y : 0.0;
    switch (cmd.toUpperCase()) {
      case 'M':
        x = ox + next();
        y = oy + next();
        sx = x;
        sy = y;
        path.moveTo(x, y);
        cmd = rel ? 'l' : 'L';
        cx2 = null;
      case 'L':
        x = ox + next();
        y = oy + next();
        path.lineTo(x, y);
        cx2 = null;
      case 'H':
        x = ox + next();
        path.lineTo(x, y);
        cx2 = null;
      case 'V':
        y = (rel ? y : 0.0) + next();
        path.lineTo(x, y);
        cx2 = null;
      case 'C':
        final x1 = ox + next(), y1 = oy + next();
        final x2 = ox + next(), y2 = oy + next();
        final nx = ox + next(), ny = oy + next();
        path.cubicTo(x1, y1, x2, y2, nx, ny);
        cx2 = x2;
        cy2 = y2;
        x = nx;
        y = ny;
      case 'S':
        // First control point mirrors the previous curve's second one.
        final x1 = cx2 == null ? x : 2 * x - cx2;
        final y1 = cy2 == null ? y : 2 * y - cy2;
        final x2 = ox + next(), y2 = oy + next();
        final nx = ox + next(), ny = oy + next();
        path.cubicTo(x1, y1, x2, y2, nx, ny);
        cx2 = x2;
        cy2 = y2;
        x = nx;
        y = ny;
      case 'Q':
        final x1 = ox + next(), y1 = oy + next();
        final nx = ox + next(), ny = oy + next();
        path.quadraticBezierTo(x1, y1, nx, ny);
        x = nx;
        y = ny;
        cx2 = null;
      case 'Z':
        path.close();
        x = sx;
        y = sy;
        cx2 = null;
        if (i < tokens.length && !isCmd(tokens[i])) cmd = 'L';
      default:
        i++;
    }
  }
  return path;
}

/// Google Meet's mark (the 2020 camera, 87.5x72), from Google's own icon,
/// for wherever the app says Google Meet.
class GoogleMeetMark extends StatelessWidget {
  const GoogleMeetMark({super.key, this.size = 22});

  /// The width; the mark is a little wider than tall.
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(size, size * 72 / 87.5), painter: _GoogleMeetPainter());
}

class _GoogleMeetPainter extends CustomPainter {
  static const _parts = <(int, String)>[
    (0xFF00832D, 'M49.5 36l8.53 9.75 11.47 7.33 2-17.02-2-16.64-11.69 6.44z'),
    (0xFF0066DA, 'M0 51.5V66c0 3.315 2.685 6 6 6h14.5l3-10.96-3-9.54-9.95-3z'),
    (0xFFE94235, 'M20.5 0L0 20.5l10.55 3 9.95-3 2.95-9.41z'),
    (0xFF2684FC, 'M20.5 20.5H0v31h20.5z'),
    (0xFF00AC47, 'M82.6 8.68L69.5 19.42v33.66l13.16 10.79c1.97 1.54 4.85.135 4.85-2.37V11c0-2.535-2.945-3.925-4.91-2.32zM49.5 36v15.5h-29V72h43c3.315 0 6-2.685 6-6V53.08z'),
    (0xFFFFBA00, 'M63.5 0h-43v20.5h29V36l20-16.57V6c0-3.315-2.685-6-6-6z'),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 87.5, size.height / 72);
    for (final (color, d) in _parts) {
      canvas.drawPath(svgPath(d, fill: PathFillType.nonZero), Paint()..color = Color(color)..isAntiAlias = true);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GoogleMeetPainter oldDelegate) => false;
}

/// Google's "G", in its standard colours: the pre-approved logo geometry
/// from Google's Sign in with Google assets (48x48), never redrawn.
class GoogleG extends StatelessWidget {
  const GoogleG({super.key, this.size = 20});
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _GoogleGPainter());
}

class _GoogleGPainter extends CustomPainter {
  static const _parts = <(int, String)>[
    (0xFFEA4335, 'M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z'),
    (0xFF4285F4, 'M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z'),
    (0xFFFBBC05, 'M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z'),
    (0xFF34A853, 'M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z'),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 48, size.height / 48);
    for (final (color, d) in _parts) {
      canvas.drawPath(svgPath(d, fill: PathFillType.nonZero), Paint()..color = Color(color)..isAntiAlias = true);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GoogleGPainter oldDelegate) => false;
}

/// Phantom's icon, from Phantom's own integration asset
/// (docs.phantom.com/resources/assets, Phantom_SVG_Icon.svg, 128x128): the
/// ghost on its lavender, in a rounded square like an app icon.
class PhantomMark extends StatelessWidget {
  const PhantomMark({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.26),
        child: CustomPaint(size: Size.square(size), painter: _PhantomPainter()),
      );
}

class _PhantomPainter extends CustomPainter {
  static const _ghost =
      'M55.6416 82.1477C50.8744 89.4525 42.8862 98.6966 32.2568 98.6966C27.232 98.6966 22.4004 96.628 22.4004 87.6424C22.4004 64.7584 53.6445 29.3335 82.6339 29.3335C99.1257 29.3335 105.697 40.7755 105.697 53.7689C105.697 70.4471 94.8739 89.5171 84.1156 89.5171C80.7013 89.5171 79.0264 87.6424 79.0264 84.6688C79.0264 83.8931 79.1552 83.0527 79.4129 82.1477C75.7409 88.4182 68.6546 94.2361 62.0192 94.2361C57.1877 94.2361 54.7397 91.1979 54.7397 86.9314C54.7397 85.3799 55.0618 83.7638 55.6416 82.1477ZM80.6133 53.3182C80.6133 57.1044 78.3795 58.9975 75.8806 58.9975C73.3438 58.9975 71.1479 57.1044 71.1479 53.3182C71.1479 49.532 73.3438 47.6389 75.8806 47.6389C78.3795 47.6389 80.6133 49.532 80.6133 53.3182ZM94.8102 53.3184C94.8102 57.1046 92.5763 58.9977 90.0775 58.9977C87.5407 58.9977 85.3447 57.1046 85.3447 53.3184C85.3447 49.5323 87.5407 47.6392 90.0775 47.6392C92.5763 47.6392 94.8102 49.5323 94.8102 53.3184Z';

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFAB9FF2));
    canvas.save();
    canvas.scale(size.width / 128, size.height / 128);
    canvas.drawPath(svgPath(_ghost, fill: PathFillType.evenOdd),
        Paint()..color = const Color(0xFFFFFDF8)..isAntiAlias = true);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PhantomPainter oldDelegate) => false;
}
