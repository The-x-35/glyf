import 'package:flutter/material.dart';

import '../core/theme.dart';

/// The Home centerpiece: a live map of YOUR keyboard. Bound keys carry the
/// accent dot and lift slightly; every key is tappable — bound opens its
/// glyf, free opens recommendations. Our own take, not a screenshot of the
/// real keyboard: flat white keycaps on the app ground, no chrome.
class KeyboardVisual extends StatelessWidget {
  const KeyboardVisual({
    super.key,
    required this.bindings,
    required this.onKeyTap,
    this.highlight,
  });

  final Map<String, String> bindings;
  final void Function(String letter) onKeyTap;
  final String? highlight;

  static const _rows = ['qwertyuiop', 'asdfghjkl', 'zxcvbnm'];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      // 10 keys, each wrapped in 2.5px side padding → 10×5px of gutters.
      final keyW = (box.maxWidth - 10 * 5) / 10;
      final keyH = keyW * 1.18;
      Widget keycap(String c) {
        final bound = bindings.containsKey(c);
        final lit = highlight == c;
        return Semantics(
          identifier: 'homekey:$c',
          button: true,
          child: GestureDetector(
            onTap: () => onKeyTap(c),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: keyW,
              height: keyH,
              decoration: BoxDecoration(
                color: lit
                    ? Glass.accent.withValues(alpha: 0.14)
                    : Colors.white,
                borderRadius: BorderRadius.circular(keyW * 0.24),
                border: Border.all(
                    color: bound
                        ? Glass.accent.withValues(alpha: 0.5)
                        : Glass.hairline,
                    width: bound ? 1.2 : 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black
                        .withValues(alpha: bound ? 0.10 : 0.05),
                    blurRadius: bound ? 5 : 2,
                    offset: Offset(0, bound ? 2.5 : 1.5),
                  ),
                ],
              ),
              child: Stack(alignment: Alignment.center, children: [
                Text(c.toUpperCase(),
                    style: TextStyle(
                        color: bound ? Glass.ink : const Color(0xFF9AA0AA),
                        fontSize: keyW * 0.42,
                        fontWeight:
                            bound ? FontWeight.w700 : FontWeight.w500)),
                if (bound)
                  Positioned(
                    right: keyW * 0.14,
                    top: keyW * 0.14,
                    child: Container(
                      width: 4.5,
                      height: 4.5,
                      decoration: const BoxDecoration(
                          color: Glass.accent, shape: BoxShape.circle),
                    ),
                  ),
              ]),
            ),
          ),
        );
      }

      return Column(children: [
        for (final (i, row) in _rows.indexed)
          Padding(
            padding: EdgeInsets.only(
                bottom: 6, left: i * keyW * 0.5, right: i * keyW * 0.5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final c in row.split(''))
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2.5),
                    child: keycap(c),
                  ),
              ],
            ),
          ),
      ]);
    });
  }
}
