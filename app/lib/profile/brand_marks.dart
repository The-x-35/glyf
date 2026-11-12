import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Logos for the tools Glyf connects to, drawn in code so no image ships and
/// nothing is fetched. Each sits on a rounded tile the size it is given.
class BrandMark extends StatelessWidget {
  const BrandMark(this.brand, {super.key, this.size = 44});

  /// magicblock | calendar | contacts | gmail | gcal | meet | notion | slack |
  /// spotify | calcom | calendly | booking | uniswap | definitive | jupiter | metamask | ethereum | solana
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
      'uniswap' => (uniswapPink, null),
      'definitive' => (Colors.black, null),
      'jupiter' => (const Color(0xFF131A2A), null),
      'metamask' => (Colors.white, const Color(0x1A000000)),
      'ethereum' => (Colors.white, const Color(0x1A000000)),
      'solana' => (Colors.black, null),
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
      case 'uniswap':
        // The unicorn (Uniswap_icon_white.svg, 400x434), 64% of the tile tall.
        final h = s * 0.64, k = h / 434;
        canvas.save();
        canvas.translate((s - 400 * k) / 2, (s - h) / 2 - s * 0.01);
        canvas.scale(k);
        for (final (evenOdd, d) in _uniswap) {
          canvas.drawPath(svgPath(d, fill: evenOdd ? PathFillType.evenOdd : PathFillType.nonZero), fill(Colors.white));
        }
        canvas.restore();
      case 'definitive':
        // Definitive's triangle with its triangular window, measured off the
        // docs' icon.
        final tri = Path()
          ..fillType = PathFillType.evenOdd
          ..addPolygon([Offset(s * 0.5, s * 0.17), Offset(s * 0.87, s * 0.81), Offset(s * 0.13, s * 0.81)], true)
          ..addPolygon([Offset(s * 0.5, s * 0.445), Offset(s * 0.628, s * 0.672), Offset(s * 0.372, s * 0.672)], true);
        canvas.drawPath(tri, fill(Colors.white));
      case 'jupiter':
        // Jupiter's mark (33x32), 66% of the tile wide, in its own gradient.
        final w = s * 0.66, k = w / 33;
        canvas.save();
        canvas.translate((s - w) / 2, (s - 32 * k) / 2);
        canvas.scale(k);
        final paint = Paint()
          ..isAntiAlias = true
          ..shader = const LinearGradient(
                  begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFFACF47D), Color(0xFF00BEF0)])
              .createShader(Rect.fromPoints(const Offset(21.5, 6.5), const Offset(6.67, 32)));
        for (final d in _jupiter) {
          canvas.drawPath(svgPath(d, fill: PathFillType.nonZero), paint);
        }
        canvas.restore();
      case 'metamask':
        // The fox (35x33), 70% of the tile wide.
        final w = s * 0.7, k = w / 35;
        canvas.save();
        canvas.translate((s - w) / 2, (s - 33 * k) / 2);
        canvas.scale(k);
        for (final (color, d) in _metamask) {
          canvas.drawPath(svgPath(d, fill: PathFillType.nonZero), fill(Color(color)));
        }
        canvas.restore();
      case 'ethereum':
        // ethereum.org's diamond (256x417), 58% of the tile tall.
        final h = s * 0.58, k = h / 417;
        canvas.save();
        canvas.translate((s - 256 * k) / 2, (s - h) / 2);
        canvas.scale(k);
        for (final (color, d) in _ethereum) {
          canvas.drawPath(svgPath(d, fill: PathFillType.nonZero), fill(Color(color)));
        }
        canvas.restore();
      case 'solana':
        // The Solana Foundation's gradient mark (120x99), 62% of the tile wide.
        final w = s * 0.62, k = w / 120;
        canvas.save();
        canvas.translate((s - w) / 2, (s - 99 * k) / 2);
        canvas.scale(k);
        final paint = Paint()
          ..isAntiAlias = true
          ..shader = ui.Gradient.linear(const Offset(10.13, 101.37), const Offset(99.83, -8.26), const [
            Color(0xFF9945FF), Color(0xFF8752F3), Color(0xFF5497D5), Color(0xFF43B4CA), Color(0xFF28E0B9), Color(0xFF19FB9B),
          ], const [0.08, 0.3, 0.5, 0.6, 0.72, 0.97]);
        canvas.drawPath(svgPath(_solana, fill: PathFillType.nonZero), paint);
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

/// Uniswap pink, from the Uniswap brand assets' pink icon.
const uniswapPink = Color(0xFFF50DB4);

/// Uniswap's unicorn: github.com/Uniswap/brand-assets, Uniswap_icon_white.svg
/// (400x434). The keyboard draws the same paths (SponsorMarks.swift).
const _uniswap = <(bool, String)>[
  (false, 'M325.144 65.7698C325.727 55.5419 327.119 48.7957 329.918 42.6348C331.025 40.1962 332.063 38.2003 332.223 38.2003C332.383 38.2003 331.902 40.0003 331.153 42.1999C329.118 48.1791 328.784 56.3572 330.186 65.872C331.965 77.9447 332.976 79.6866 345.782 92.7278C351.788 98.8446 358.775 106.559 361.307 109.871L365.912 115.894L361.307 111.59C355.676 106.327 342.724 96.0618 339.863 94.5945C337.945 93.6104 337.66 93.6274 336.477 94.801C335.387 95.8823 335.157 97.5072 335.005 105.189C334.77 117.16 333.132 124.845 329.18 132.528C327.042 136.684 326.705 135.797 328.64 131.106C330.084 127.604 330.231 126.064 330.22 114.475C330.198 91.1888 327.424 85.5906 311.153 76.0005C307.032 73.5711 300.24 70.0674 296.062 68.2141C291.883 66.3608 288.564 64.7467 288.685 64.6261C289.146 64.1691 305.013 68.7839 311.399 71.2318C320.899 74.8731 322.467 75.3449 323.621 74.9057C324.394 74.6113 324.768 72.367 325.144 65.7698Z'),
  (false, 'M124.431 31.8931C118.795 31.0236 118.557 30.9216 121.209 30.5162C126.292 29.7389 138.292 30.7983 146.562 32.754C165.867 37.3182 183.434 49.0103 202.186 69.7754L207.168 75.2919L214.295 74.1524C244.318 69.3537 274.861 73.1675 300.407 84.9049C307.435 88.134 318.516 94.5618 319.9 96.2136C320.341 96.7401 321.151 100.129 321.699 103.745C323.597 116.255 322.647 125.843 318.8 133.005C316.707 136.903 316.59 138.138 317.997 141.473C319.121 144.135 322.253 146.105 325.355 146.1C331.703 146.092 338.536 135.885 341.702 121.683L342.96 116.042L345.452 118.849C359.117 134.248 369.85 155.248 371.694 170.196L372.174 174.093L369.877 170.55C365.924 164.454 361.952 160.303 356.866 156.956C347.697 150.922 338.002 148.868 312.327 147.523C289.139 146.307 276.015 144.337 263.002 140.117C240.861 132.937 229.699 123.375 203.399 89.0559C191.717 73.8123 184.497 65.3784 177.314 58.5864C160.994 43.1536 144.958 35.0599 124.431 31.8931Z'),
  (false, 'M135.377 105.713C123.937 90.0473 116.858 66.0289 118.391 48.0742L118.864 42.518L121.469 42.9906C126.359 43.8778 134.791 46.9992 138.739 49.3844C149.574 55.9291 154.265 64.5458 159.037 86.6722C160.435 93.1531 162.269 100.487 163.113 102.97C164.472 106.967 169.605 116.302 173.779 122.365C176.785 126.731 174.788 128.8 168.143 128.204C157.994 127.293 144.246 117.856 135.377 105.713Z'),
  (false, 'M311.254 222.301C257.789 200.891 238.958 182.307 238.958 150.95C238.958 146.336 239.118 142.56 239.313 142.56C239.507 142.56 241.576 144.083 243.909 145.945C254.751 154.593 266.891 158.287 300.501 163.164C320.279 166.034 331.408 168.352 341.675 171.738C374.308 182.502 394.497 204.345 399.312 234.098C400.711 242.743 399.891 258.955 397.623 267.5C395.832 274.248 390.367 286.413 388.918 286.879C388.516 287.009 388.122 285.477 388.019 283.393C387.469 272.221 381.793 261.345 372.26 253.197C361.421 243.934 346.859 236.559 311.254 222.301Z'),
  (false, 'M273.719 231.195C273.049 227.231 271.888 222.168 271.138 219.944L269.773 215.901L272.307 218.73C275.814 222.645 278.585 227.654 280.933 234.325C282.726 239.417 282.927 240.932 282.914 249.206C282.9 257.33 282.676 259.032 281.021 263.616C278.411 270.843 275.172 275.967 269.737 281.468C259.971 291.354 247.415 296.828 229.295 299.098C226.145 299.492 216.965 300.157 208.895 300.574C188.556 301.626 175.17 303.8 163.142 308C161.412 308.605 159.868 308.972 159.711 308.816C159.225 308.334 167.414 303.479 174.178 300.238C183.716 295.668 193.211 293.175 214.484 289.651C224.992 287.91 235.844 285.799 238.6 284.958C264.624 277.023 278.001 256.544 273.719 231.195Z'),
  (false, 'M298.228 274.486C291.125 259.299 289.493 244.635 293.385 230.959C293.802 229.498 294.471 228.302 294.874 228.302C295.276 228.302 296.953 229.203 298.598 230.305C301.872 232.496 308.437 236.188 325.928 245.672C347.754 257.507 360.198 266.672 368.66 277.142C376.071 286.312 380.658 296.755 382.865 309.49C384.115 316.704 383.383 334.061 381.521 341.325C375.653 364.229 362.015 382.22 342.562 392.718C339.712 394.256 337.153 395.519 336.876 395.524C336.599 395.53 337.638 392.904 339.184 389.688C345.728 376.083 346.473 362.849 341.526 348.118C338.496 339.099 332.32 328.094 319.849 309.493C305.35 287.868 301.795 282.113 298.228 274.486Z'),
  (false, 'M97.4084 356.432C117.249 339.771 141.935 327.934 164.422 324.301C174.113 322.735 190.257 323.357 199.231 325.641C213.616 329.302 226.484 337.503 233.176 347.273C239.716 356.823 242.522 365.144 245.443 383.659C246.596 390.962 247.849 398.296 248.228 399.957C250.422 409.552 254.691 417.222 259.982 421.074C268.385 427.191 282.854 427.571 297.087 422.049C299.503 421.111 301.6 420.464 301.748 420.61C302.264 421.12 295.097 425.892 290.04 428.404C283.237 431.784 277.827 433.09 270.638 433.09C257.602 433.09 246.779 426.495 237.748 413.046C235.971 410.399 231.976 402.471 228.871 395.429C219.336 373.799 214.628 367.21 203.556 359.998C193.922 353.723 181.496 352.599 172.148 357.158C159.87 363.146 156.444 378.752 165.238 388.642C168.733 392.573 175.251 395.964 180.581 396.623C190.552 397.856 199.121 390.312 199.121 380.299C199.121 373.798 196.609 370.088 190.284 367.249C181.646 363.372 172.36 367.904 172.405 375.975C172.424 379.417 173.931 381.578 177.4 383.139C179.625 384.14 179.677 384.22 177.862 383.845C169.936 382.21 168.079 372.707 174.452 366.398C182.103 358.824 197.924 362.166 203.357 372.504C205.64 376.847 205.905 385.495 203.915 390.717C199.461 402.405 186.475 408.552 173.302 405.207C164.333 402.93 160.681 400.464 149.867 389.386C131.077 370.135 123.782 366.405 96.6926 362.198L91.5016 361.393L97.4084 356.432Z'),
  (true, 'M9.2415 11.8782C71.9927 87.6272 115.213 118.88 120.016 125.483C123.981 130.935 122.489 135.836 115.695 139.678C111.917 141.813 104.15 143.977 100.261 143.977C95.8623 143.977 94.3522 142.29 94.3522 142.29C91.8018 139.884 90.3654 140.305 77.2685 117.183C59.0858 89.1221 43.8693 65.8442 43.4542 65.4545C42.4943 64.5531 42.5108 64.5836 75.4146 123.138C80.7309 135.342 76.472 139.822 76.472 141.56C76.472 145.096 75.5021 146.955 71.1164 151.82C63.8053 159.933 60.537 169.047 58.1777 187.911C55.5328 209.058 48.0957 223.995 27.485 249.56C15.4202 264.526 13.446 267.269 10.4018 273.3C6.56722 280.896 5.51286 285.15 5.08553 294.742C4.63386 304.883 5.51354 311.434 8.62869 321.13C11.3559 329.619 14.2026 335.224 21.4801 346.435C27.7605 356.109 31.3768 363.299 31.3768 366.111C31.3768 368.349 31.8063 368.352 41.5383 366.166C64.8282 360.936 83.7395 351.736 94.3756 340.462C100.958 333.483 102.503 329.63 102.554 320.067C102.587 313.812 102.365 312.503 100.665 308.904C97.898 303.048 92.8603 298.178 81.7568 290.629C67.2082 280.737 60.9944 272.774 59.2779 261.822C57.8699 252.836 59.5033 246.496 67.5518 229.719C75.8822 212.353 77.9466 204.953 79.3431 187.449C80.245 176.141 81.4941 171.681 84.761 168.101C88.1682 164.368 91.2354 163.104 99.6675 161.958C113.414 160.09 122.168 156.552 129.363 149.958C135.605 144.238 138.217 138.725 138.618 130.427L138.922 124.138L135.434 120.093C122.802 105.445 0.782165 0.363281 0.00480791 0.363281C-0.161257 0.363281 3.99542 5.54535 9.2415 11.8782ZM38.4675 306.217C41.3235 301.186 39.8061 294.719 35.0288 291.56C30.515 288.574 23.503 289.98 23.503 293.87C23.503 295.057 24.163 295.921 25.6504 296.683C28.155 297.965 28.3368 299.406 26.3662 302.352C24.3705 305.335 24.5316 307.958 26.8207 309.741C30.5099 312.614 35.7324 311.034 38.4675 306.217Z'),
  (true, 'M147.597 165.257C141.144 167.228 134.87 174.031 132.928 181.164C131.744 185.515 132.416 193.149 134.19 195.506C137.057 199.314 139.829 200.317 147.336 200.264C162.033 200.162 174.809 193.893 176.294 186.056C177.512 179.632 171.901 170.729 164.172 166.82C160.183 164.804 151.701 164.004 147.597 165.257ZM164.778 178.619C167.044 175.416 166.053 171.954 162.198 169.613C154.858 165.155 143.757 168.844 143.757 175.741C143.757 179.174 149.546 182.92 154.852 182.92C158.384 182.92 163.217 180.825 164.778 178.619Z'),
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

/// Jupiter's mark (jup.ag/svg/jupiter-logo.svg, viewBox 0 0 33 32), every path
/// filled with its one gradient, #ACF47D to #00BEF0.
const _jupiter = [
  'M3.09074 25.1666C4.44267 27.0471 6.17683 28.6205 8.1795 29.7838C10.1822 30.947 12.4081 31.6738 14.7114 31.9165C13.5264 30.1333 11.8039 28.4928 9.65354 27.2438C7.50318 25.9948 5.22592 25.3125 3.09074 25.1666Z',
  'M12.543 22.2705C8.40015 19.8636 3.91612 19.2502 0.707663 20.3338C1.0174 21.3575 1.42589 22.3487 1.92738 23.2934C4.71498 23.2288 7.75856 23.9859 10.5906 25.6308C13.4227 27.2757 15.5888 29.5459 16.9143 32C17.9839 31.9672 19.0479 31.8309 20.0913 31.5932C19.4426 28.2698 16.6849 24.6779 12.543 22.2705Z',
  'M32.2852 12.5009C31.7585 10.3584 30.8054 8.34403 29.4829 6.57804C28.1604 4.81205 26.4956 3.33067 24.5879 2.22235C22.6802 1.11403 20.5687 0.401504 18.3796 0.127309C16.1904 -0.146885 13.9684 0.0228794 11.8463 0.626465C15.3915 1.06033 19.3267 2.39122 23.1859 4.63324C27.0452 6.87525 30.1533 9.63411 32.2852 12.5009Z',
  'M27.1271 20.3583C25.3124 17.3446 22.2038 14.4588 18.3743 12.2342C14.5449 10.0095 10.4991 8.7388 6.98531 8.65474C3.894 8.58152 1.57389 9.48017 0.621548 11.1197C0.616125 11.1294 0.608532 11.1386 0.602566 11.1484C0.516877 11.4559 0.44312 11.7639 0.37587 12.0731C1.70568 11.5481 3.24645 11.2558 4.95969 11.2232C8.76959 11.1517 13.0334 12.3703 16.9681 14.6562C20.9027 16.9422 24.0759 20.0438 25.9003 23.3878C26.7182 24.8944 27.2285 26.3777 27.4308 27.7948C27.6662 27.5844 27.8972 27.3669 28.1212 27.1408C28.1272 27.1305 28.131 27.1196 28.1369 27.1088C29.0893 25.4677 28.721 23.0076 27.1271 20.3583Z',
  'M15.4609 17.2485C9.59662 13.8416 3.11626 13.3079 0 15.6855C0.00612096 16.4297 0.0630166 17.1726 0.170292 17.9091C1.08699 17.6312 2.03177 17.4562 2.98718 17.3874C6.46952 17.1254 10.3087 18.0957 13.7927 20.1207C17.2766 22.1458 20.023 25.0018 21.5209 28.1543C21.935 29.018 22.2508 29.9254 22.4624 30.8595C23.1555 30.5878 23.8294 30.2694 24.4794 29.9066C25.0011 26.0213 21.3268 20.656 15.4609 17.2485Z',
  'M30.1434 15.3141C28.3082 12.3036 25.1724 9.40969 21.3158 7.17039C17.4593 4.93109 13.3977 3.64033 9.87257 3.53674C7.1853 3.45919 5.10382 4.11053 4.02457 5.34109C8.50588 4.58182 14.4168 5.85794 20.146 9.18625C25.8753 12.5146 29.9135 17.0181 31.4722 21.2868C32.0064 19.7406 31.5416 17.6098 30.1434 15.3141Z',
];

/// MetaMask's fox (github.com/MetaMask/metamask-extension, app/images/logo/
/// metamask-fox.svg, viewBox 0 0 35 33): each facet's colour and path.
const _metamask = <(int, String)>[
  (0xFFE17726, 'm32.9582 1-13.1341 9.7183 2.4424-5.72731z'),
  (0xFFE27625, 'm2.66296 1 13.01714 9.809-2.3254-5.81802z'),
  (0xFFE27625, 'm28.2295 23.5335-3.4947 5.3386 7.4829 2.0603 2.1436-7.2823z'),
  (0xFFE27625, 'm1.27281 23.6501 2.13055 7.2823 7.46994-2.0603-3.48166-5.3386z'),
  (0xFFE27625, 'm10.4706 14.5149-2.0786 3.1358 7.405.3369-.2469-7.969z'),
  (0xFFE27625, 'm25.1505 14.5149-5.1575-4.58704-.1688 8.05974 7.4049-.3369z'),
  (0xFFE27625, 'm10.8733 28.8721 4.4819-2.1639-3.8583-3.0062z'),
  (0xFFE27625, 'm20.2659 26.7082 4.4689 2.1639-.6105-5.1701z'),
  (0xFFD5BFB2, 'm24.7348 28.8721-4.469-2.1639.3638 2.9025-.039 1.231z'),
  (0xFFD5BFB2, 'm10.8732 28.8721 4.1572 1.9696-.026-1.231.3508-2.9025z'),
  (0xFF233447, 'm15.1084 21.7842-3.7155-1.0884 2.6243-1.2051z'),
  (0xFF233447, 'm20.5126 21.7842 1.0913-2.2935 2.6372 1.2051z'),
  (0xFFCC6228, 'm10.8733 28.8721.6495-5.3386-4.13117.1167z'),
  (0xFFCC6228, 'm24.0982 23.5335.6366 5.3386 3.4946-5.2219z'),
  (0xFFCC6228, 'm27.2291 17.6507-7.405.3369.6885 3.7966 1.0913-2.2935 2.6372 1.2051z'),
  (0xFFCC6228, 'm11.3929 20.6958 2.6242-1.2051 1.0913 2.2935.6885-3.7966-7.40495-.3369z'),
  (0xFFE27525, 'm8.392 17.6507 3.1049 6.0513-.1039-3.0062z'),
  (0xFFE27525, 'm24.2412 20.6958-.1169 3.0062 3.1049-6.0513z'),
  (0xFFE27525, 'm15.797 17.9876-.6886 3.7967.8704 4.4833.1949-5.9087z'),
  (0xFFE27525, 'm19.8242 17.9876-.3638 2.3584.1819 5.9216.8704-4.4833z'),
  (0xFFF5841F, 'm20.5127 21.7842-.8704 4.4834.6236.4406 3.8584-3.0062.1169-3.0062z'),
  (0xFFF5841F, 'm11.3929 20.6958.104 3.0062 3.8583 3.0062.6236-.4406-.8704-4.4834z'),
  (0xFFC0AC9D, 'm20.5906 30.8417.039-1.231-.3378-.2851h-4.9626l-.3248.2851.026 1.231-4.1572-1.9696 1.4551 1.1921 2.9489 2.0344h5.0536l2.962-2.0344 1.442-1.1921z'),
  (0xFF161616, 'm20.2659 26.7082-.6236-.4406h-3.6635l-.6236.4406-.3508 2.9025.3248-.2851h4.9626l.3378.2851z'),
  (0xFF763E1A, 'm33.5168 11.3532 1.1043-5.36447-1.6629-4.98873-12.6923 9.3944 4.8846 4.1205 6.8983 2.0085 1.52-1.7752-.6626-.4795 1.0523-.9588-.8054-.622 1.0523-.8034z'),
  (0xFF763E1A, 'm1 5.98873 1.11724 5.36447-.71451.5313 1.06527.8034-.80545.622 1.05228.9588-.66255.4795 1.51997 1.7752 6.89835-2.0085 4.8846-4.1205-12.69233-9.3944z'),
  (0xFFF5841F, 'm32.0489 16.5234-6.8983-2.0085 2.0786 3.1358-3.1049 6.0513 4.1052-.0519h6.1318z'),
  (0xFFF5841F, 'm10.4705 14.5149-6.89828 2.0085-2.29944 7.1267h6.11883l4.10519.0519-3.10487-6.0513z'),
  (0xFFF5841F, 'm19.8241 17.9876.4417-7.5932 2.0007-5.4034h-8.9119l2.0006 5.4034.4417 7.5932.1689 2.3842.013 5.8958h3.6635l.013-5.8958z'),
];

/// ethereum.org's diamond (viewBox 0 0 256 417), the same six facets the
/// keyboard draws (ChainLogo.swift).
const _ethereum = <(int, String)>[
  (0xFF343434, 'M127.961 0l-2.795 9.5v275.668l2.795 2.79 127.962-75.638z'),
  (0xFF8C8C8C, 'M127.962 0L0 212.32l127.962 75.639V154.158z'),
  (0xFF3C3C3B, 'M127.961 312.187l-1.575 1.92v98.199l1.575 4.6L256 236.587z'),
  (0xFF8C8C8C, 'M127.962 416.905v-104.72L0 236.585z'),
  (0xFF141414, 'M127.961 287.958l127.96-75.637-127.96-58.162z'),
  (0xFF393939, 'M0 212.32l127.96 75.638v-133.8z'),
];

/// The Solana Foundation's mark (solana-mark-gradient.svg, viewBox 0 0 120 99).
const _solana =
    'M119.37 78.0655L99.5477 97.658C98.6753 98.508 97.4637 99 96.2036 99H2.27787C1.01777 99 0 98.0159 0 96.8529C0 96.3161 0.242326 95.824 0.630048 95.4215L20.4039 75.8289C21.2763 74.979 22.4879 74.487 23.748 74.487H117.674C118.934 74.487 120 75.3816 120 76.5447C120 77.0814 119.806 77.6182 119.37 78.0208M99.5477 38.5226C98.6753 37.6727 97.4637 37.1807 96.2036 37.1807H2.27787C1.01777 37.2254 0 38.1648 0 39.3278C0 39.8646 0.242326 40.3566 0.630048 40.7592L20.4039 60.3965C21.2763 61.2464 22.4879 61.7384 23.748 61.7384H117.674C118.934 61.7384 119.952 60.7543 119.952 59.5913C119.952 59.0545 119.709 58.5625 119.321 58.1599L99.5477 38.5226ZM2.27787 24.4769H96.1551C97.4152 24.4769 98.6268 23.9848 99.4992 23.1349L119.37 3.54238C120.242 2.69248 120.194 1.35052 119.273 0.545352C119.176 0.455888 119.079 0.366425 118.934 0.321693C118.546 0.0980342 118.11 -0.0361611 117.674 0.00857069H23.748C22.4879 0.00857069 21.2763 0.50062 20.4039 1.35052L0.630048 20.943C-0.242326 21.7929 -0.193861 23.1349 0.775444 23.9401C1.21163 24.2979 1.74475 24.5216 2.32633 24.5216';
