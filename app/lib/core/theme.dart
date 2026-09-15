import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// Design system — WHITE ONLY (decision 2026-09-12, Acti-reference).
/// Near-white ground, white cards, ink text, BLACK pill CTAs. The accent
/// (#7C5CFF) survives only as the bound-key dot / selection highlights,
/// exactly like the logo sheet.
abstract final class Glass {
  static const accent = Color(0xFF7C5CFF);
  static const success = Color(0xFF1FA968);
  static const warning = Color(0xFFB77909);
  static const danger = Color(0xFFE0382C);

  static const bg = Color(0xFFF4F5F8);
  static const card = Colors.white;
  static const ink = Color(0xFF17181C);
  static const inkSoft = Color(0xFF8A8F98);
  static const hairline = Color(0x0F000000);
  static const pill = Color(0xFF141418);

  static const radiusCard = 22.0;
  static const radiusSheet = 28.0;

  static ThemeData theme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.light,
      surface: bg,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: bg,
      // Inter everywhere: SF-metric type so iOS and Android are twins.
      fontFamily: 'Inter',
      // iOS-style push/pop on BOTH platforms.
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      }),
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: ink,
        elevation: 0,
      ),
    );
  }
}

/// Plain light ground (the purple night is gone).
class GlyfBackground extends StatelessWidget {
  const GlyfBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: Glass.bg, child: child);
  }
}

/// White card — the one container style (Acti-soft: big radius, whisper
/// shadow, hairline).
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Glass.card,
        borderRadius: BorderRadius.circular(Glass.radiusCard),
        border: Border.all(color: borderColor ?? Glass.hairline, width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(Glass.radiusCard),
        onTap: onTap,
        child: card,
      ),
    );
  }
}

/// The pill CTA — black, Acti-style. `primary:false` = white with hairline.
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: primary ? Glass.pill : Colors.white,
          foregroundColor: primary ? Colors.white : Glass.ink,
          disabledBackgroundColor:
              primary ? const Color(0xFFC9CBD1) : Colors.white,
          disabledForegroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
            side: primary
                ? BorderSide.none
                : const BorderSide(color: Glass.hairline),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }
}

/// Brand wordmark: "glyf" with the accent dot riding above the f.
class GlyfWordmark extends StatelessWidget {
  const GlyfWordmark({super.key, this.size = 30});
  final double size;

  // CANONICAL MARK — identical on app, keyboard and site. Every number is a
  // fraction of `size`, so it never drifts between platforms:
  //   dot diameter 0.18em
  //   gap after the f 0.16em — clear of the letter, never touching it
  //   dot BOTTOM at the f's top (0.74em) so the whole dot rides ABOVE the
  //   letter: top-right, not alongside it.
  static const dotRatio = 0.18;
  static const gapRatio = 0.16;
  static const riseRatio = 0.74;
  static const weight = FontWeight.w700;
  static const trackingRatio = -0.045;

  @override
  Widget build(BuildContext context) {
    return Stack(clipBehavior: Clip.none, children: [
      Text('glyf',
          style: TextStyle(
              fontSize: size,
              fontWeight: weight,
              letterSpacing: size * trackingRatio,
              color: Glass.ink,
              height: 1)),
      Positioned(
        // height:1 puts the baseline 0.80em below the box top, so the dot's
        // top lands at 0.80 - rise - diameter above it (i.e. above the cap).
        right: -size * (gapRatio + dotRatio),
        top: size * (0.80 - riseRatio - dotRatio),
        child: Container(
          width: size * dotRatio,
          height: size * dotRatio,
          decoration:
              const BoxDecoration(color: Glass.accent, shape: BoxShape.circle),
        ),
      ),
    ]);
  }
}

/// Brand mark: the bound keycap (concept 01) — white key, ink g, accent dot.
class KeycapGMark extends StatelessWidget {
  const KeycapGMark({super.key, this.size = 56});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.30),
        border: Border.all(color: Glass.hairline),
        boxShadow: const [
          BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Stack(alignment: Alignment.center, children: [
        Text('g',
            style: TextStyle(
                fontSize: size * 0.52,
                fontWeight: FontWeight.w600,
                color: Glass.ink,
                height: 1)),
        Positioned(
          right: size * 0.16,
          top: size * 0.14,
          child: Container(
            width: size * 0.13,
            height: size * 0.13,
            decoration: const BoxDecoration(
                color: Glass.accent, shape: BoxShape.circle),
          ),
        ),
      ]),
    );
  }
}
