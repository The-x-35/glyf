import 'package:flutter/material.dart';

/// Logos for the tools Glyf connects to, drawn in code so no image ships and
/// nothing is fetched. Each sits on a rounded tile the size it is given.
class BrandMark extends StatelessWidget {
  const BrandMark(this.brand, {super.key, this.size = 44});

  /// magicblock | calendar | contacts | gmail | gcal | notion | slack | spotify
  final String brand;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (bg, border) = switch (brand) {
      'magicblock' => (const Color(0xFF111111), null),
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
      child: brand == 'calendar'
          ? _PhoneCalendar(size)
          : CustomPaint(painter: _MarkPainter(brand)),
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

/// SVG path data (M L H V C Z, absolute or relative) to a Flutter Path.
Path svgPath(String d) {
  final path = Path()..fillType = PathFillType.evenOdd;
  final tokens = RegExp(r'[MmLlHhVvCcZz]|-?\d*\.?\d+(?:e-?\d+)?').allMatches(d).map((m) => m.group(0)!).toList();
  var i = 0;
  var cmd = 'M';
  var x = 0.0, y = 0.0, sx = 0.0, sy = 0.0;
  double next() => double.parse(tokens[i++]);
  while (i < tokens.length) {
    if (RegExp(r'^[A-Za-z]$').hasMatch(tokens[i])) cmd = tokens[i++];
    final rel = cmd == cmd.toLowerCase();
    switch (cmd.toUpperCase()) {
      case 'M':
        final nx = next(), ny = next();
        x = rel ? x + nx : nx;
        y = rel ? y + ny : ny;
        sx = x;
        sy = y;
        path.moveTo(x, y);
        cmd = rel ? 'l' : 'L';
      case 'L':
        final nx = next(), ny = next();
        x = rel ? x + nx : nx;
        y = rel ? y + ny : ny;
        path.lineTo(x, y);
      case 'H':
        final nx = next();
        x = rel ? x + nx : nx;
        path.lineTo(x, y);
      case 'V':
        final ny = next();
        y = rel ? y + ny : ny;
        path.lineTo(x, y);
      case 'C':
        var x1 = next(), y1 = next(), x2 = next(), y2 = next(), nx = next(), ny = next();
        if (rel) {
          x1 += x; y1 += y; x2 += x; y2 += y; nx += x; ny += y;
        }
        path.cubicTo(x1, y1, x2, y2, nx, ny);
        x = nx;
        y = ny;
      case 'Z':
        path.close();
        x = sx;
        y = sy;
        if (i < tokens.length && !RegExp(r'^[A-Za-z]$').hasMatch(tokens[i])) cmd = 'L';
      default:
        i++;
    }
  }
  return path;
}
