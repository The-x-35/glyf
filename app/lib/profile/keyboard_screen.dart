import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';

import '../core/bridge.dart';
import '../core/telemetry.dart';
import '../core/theme.dart';

/// Everything about the keyboard on one page: how it looks, then how it types.
///
/// Themes used to be a separate screen behind this one; they live here now,
/// the way Gboard keeps "Theme" inside its own settings rather than as a
/// destination of its own.
class KeyboardScreen extends StatefulWidget {
  const KeyboardScreen({super.key});

  @override
  State<KeyboardScreen> createState() => _KeyboardScreenState();
}

class _KeyboardScreenState extends State<KeyboardScreen> {
  Map<String, dynamic> _settings = {};

  /// What the strip converts a typed amount into. "auto" follows the phone;
  /// the rest are the ECB's own list, which is what the rates come from —
  /// offering a currency it doesn't quote would just give a dead chip.
  static const _currencies = <String, String>{
    'auto': 'Where I am',
    'INR': '₹  Indian rupee',
    'USD': '\$  US dollar',
    'EUR': '€  Euro',
    'GBP': '£  Pound sterling',
    'JPY': '¥  Japanese yen',
    'AUD': 'A\$  Australian dollar',
    'CAD': 'C\$  Canadian dollar',
    'SGD': 'S\$  Singapore dollar',
    'CHF': 'CHF  Swiss franc',
    'CNY': 'CN¥  Chinese yuan',
    'HKD': 'HK\$  Hong Kong dollar',
    'NZD': 'NZ\$  New Zealand dollar',
    'ZAR': 'R  South African rand',
    'BRL': 'R\$  Brazilian real',
    'MXN': 'MX\$  Mexican peso',
    'KRW': '₩  South Korean won',
    'THB': '฿  Thai baht',
    'PHP': '₱  Philippine peso',
    'IDR': 'Rp  Indonesian rupiah',
    'MYR': 'RM  Malaysian ringgit',
    'SEK': 'kr  Swedish krona',
    'NOK': 'kr  Norwegian krone',
    'PLN': 'zł  Polish złoty',
    'TRY': '₺  Turkish lira',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await GlyfBridge.sharedSettings();
    if (mounted) setState(() => _settings = s);
    // The colour and gradient themes are retired for now: iOS draws a band
    // above every keyboard that a painted board can't reach, so it looked
    // cut off. A board picked before goes back to the default look.
    if (((s['themeBg'] as String?) ?? '').isNotEmpty) await _set('themeBg', '');
  }

  Future<void> _set(String key, Object value) async {
    setState(() => _settings = Map.of(_settings)..[key] = value);
    await GlyfBridge.updateSharedSettings((s) => s..[key] = value);
    Telemetry.log('kb_setting_changed', {'setting': key});
  }

  String get _themeBg => (_settings['themeBg'] as String?) ?? '';
  String get _keyTheme => (_settings['keyTheme'] as String?) ?? 'site';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Glass.bg,
      appBar: AppBar(
        backgroundColor: Glass.bg,
        surfaceTintColor: Colors.transparent,
        title: const Text('Keyboard',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          _label('Look'),
          _grid([
            _tile('Glyf', selected: _keyTheme == 'site' && _themeBg.isEmpty,
                onTap: () async {
                  await _set('keyTheme', 'site');
                  await _set('themeBg', '');
                }),
            _tile('Glass', board: const Color(0xFFD5D8DE), translucent: true,
                selected: _keyTheme == 'glass' && _themeBg.isEmpty,
                onTap: () async {
                  await _set('keyTheme', 'glass');
                  await _set('themeBg', '');
                }),
          ]),
          const SizedBox(height: 18),
          _card([
            // The iPhone keyboard follows the app it types into, like
            // Apple's: iOS draws the band above it and the bar below it in
            // that app's colour, so a forced light or dark looked cut off.
            if (!Platform.isIOS)
              _segmented('Appearance', 'appearance', const ['auto', 'light', 'dark']),
            _switch('Borders around keys', 'keyBorders'),
          ]),
          const SizedBox(height: 18),
          _label('Typing'),
          _card([
            _switch('Autocorrect', 'autocorrect'),
            // Off = the word stays exactly as typed and the fix waits in the
            // strip. (iOS gives no third-party keyboard Apple's underline.)
            _switch('Correct automatically', 'autocorrectApply', fallback: true),
            _switch('Suggestions', 'candidates'),
            _switch('Auto-capitalize', 'autocapitalize'),
            _switch('Double-space for period', 'periodShortcut'),
            _switch('Number row', 'numberRow'),
          ]),
          const SizedBox(height: 18),
          _label('Feel'),
          _card([
            _switch('Sound on keypress', 'keyClicks'),
            _switch('Haptic feedback on keypress', 'haptics'),
          ]),
          const SizedBox(height: 18),
          _label('Money'),
          _card([_currencyRow()]),
          const SizedBox(height: 18),
          _label('Clipboard & AI'),
          _card([
            _switch('Keep what you copy', 'clipboardHistory', fallback: true),
            // The iPhone's paste prompt only; Android has nothing like it.
            if (Platform.isIOS) ...[
              _switch('Capture everything you copy', 'clipboardCaptureAll',
                  fallback: true),
              _note('Every copy lands in the clipboard by itself. iOS asks '
                  'once per copy until you set Settings → Glyf → Paste from '
                  'Other Apps → Allow; after that it never asks again.'),
            ],
            _switch('Recent screenshots', 'clipboardScreenshots',
                fallback: true,
                onBeforeOn: GlyfBridge.screenshotAccess,
                // Asked before and refused: the system won't ask again, so
                // say where it's allowed rather than let the switch flick back.
                denied: Platform.isIOS
                    ? 'Photos are off for Glyf. Allow them in Settings › Glyf › Photos'
                    : 'Photos are off for Glyf. Allow them in Settings › Apps › Glyf › Permissions'),
            _note('Shots from the last hour, beside what you copied. Turning '
                'this on is when Glyf asks for your photos.'),
            _switch('Let AI use your saved details', 'aiUsesVault', fallback: true),
          ]),
        ],
      ),
    );
  }

  /// A line of explanation under the switch it belongs to.
  Widget _note(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Text(text,
            style: const TextStyle(
                fontSize: 12.5, height: 1.35, color: Glass.inkSoft)),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.w600, color: Glass.inkSoft)),
      );

  Widget _card(List<Widget> rows) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Glass.hairline),
        ),
        child: Column(children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 16, color: Glass.hairline),
            rows[i],
          ],
        ]),
      );

  Widget _switch(String title, String key,
      {bool fallback = false, Future<bool> Function()? onBeforeOn, String? denied}) {
    final on = (_settings[key] as bool?) ?? fallback;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
      child: Row(children: [
        Expanded(child: Text(title, style: const TextStyle(fontSize: 15))),
        CupertinoSwitch(
          value: on,
          activeTrackColor: Glass.ink,
          onChanged: (v) async {
            // Turning on something that needs a permission waits for it.
            if (v && onBeforeOn != null && !await onBeforeOn()) {
              if (denied != null && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(denied)));
              }
              return;
            }
            _set(key, v);
          },
        ),
      ]),
    );
  }

  /// Type "$13" and the strip offers it in this currency. Token prices stay
  /// in dollars, which is how the market quotes them.
  Widget _currencyRow() {
    final value = (_settings['moneyCurrency'] as String?) ?? 'auto';
    return InkWell(
      onTap: _pickCurrency,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(children: [
          const Expanded(
              child: Text('Convert money to', style: TextStyle(fontSize: 15))),
          Text(_currencies[value] ?? value,
              style: const TextStyle(fontSize: 14, color: Glass.inkSoft)),
          const Icon(Icons.chevron_right, size: 18, color: Glass.inkSoft),
        ]),
      ),
    );
  }

  Future<void> _pickCurrency() async {
    final current = (_settings['moneyCurrency'] as String?) ?? 'auto';
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      // Fifteen currencies outgrow the screen: keep the sheet under the
      // status bar and let the list scroll instead of the title going under it.
      useSafeArea: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(Glass.radiusSheet))),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 10),
              child: Text('Convert money to',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
            ),
            for (final e in _currencies.entries)
              ListTile(
                title: Text(e.value, style: const TextStyle(fontSize: 15)),
                trailing: e.key == current
                    ? const Icon(Icons.check, size: 19, color: Glass.accent)
                    : null,
                onTap: () => Navigator.of(ctx).pop(e.key),
              ),
          ],
        ),
      ),
    );
    if (picked != null) await _set('moneyCurrency', picked);
  }

  Widget _segmented(String title, String key, List<String> options) {
    final value = (_settings[key] as String?) ?? options.first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Row(children: [
        Expanded(child: Text(title, style: const TextStyle(fontSize: 15))),
        for (final o in options)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: GestureDetector(
              onTap: () => _set(key, o),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: value == o ? Glass.ink : const Color(0xFFF2F3F7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(o,
                    style: TextStyle(
                        fontSize: 13,
                        color: value == o ? Colors.white : Glass.ink)),
              ),
            ),
          ),
      ]),
    );
  }

  /// Three per row, Gboard's theme grid.
  Widget _grid(List<Widget> tiles) => GridView.count(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.02,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: tiles,
      );

  Widget _tile(String label, {
    Color? board,
    List<Color>? gradient,
    bool translucent = false,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final seed = gradient == null
        ? (board ?? const Color(0xFFD5D8DE))
        : KeyPalette.mix(gradient.first, gradient.last, 0.5);
    final palette = KeyPalette(seed);
    final keyColor = translucent
        ? Colors.white.withValues(alpha: 0.6)
        : palette.key;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? Glass.accent : Glass.hairline,
              width: selected ? 1.8 : 1),
        ),
        child: Column(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
              child: Container(
                decoration: BoxDecoration(
                  color: gradient == null ? seed : null,
                  gradient: gradient == null
                      ? null
                      : LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: gradient),
                ),
                padding: const EdgeInsets.fromLTRB(7, 8, 7, 7),
                child: CustomPaint(
                  painter: _MiniKeyboard(key: keyColor, fn: palette.fn),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (selected) ...[
                const Icon(Icons.check_circle, size: 13, color: Glass.accent),
                const SizedBox(width: 4),
              ],
              Text(label,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// A keyboard in miniature, drawn to a real keyboard's proportions: ten keys
/// across, a key a little taller than it is wide, the second row inset, shift
/// and delete wide, a long space bar.
class _MiniKeyboard extends CustomPainter {
  _MiniKeyboard({required this.key, required this.fn});

  final Color key;
  final Color fn;

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 2.2;
    final unit = (size.width - gap * 9) / 10;
    var keyH = unit * 1.32;
    final rowsH = keyH * 4 + gap * 3 * 1.6;
    if (rowsH > size.height) keyH *= size.height / rowsH;
    final rowGap = gap * 1.6;
    final top = (size.height - (keyH * 4 + rowGap * 3)) / 2;
    final keyPaint = Paint()..color = key;
    final fnPaint = Paint()..color = fn;
    final r = Radius.circular(unit * 0.22);

    void keyAt(double x, double y, double w, Paint p) =>
        canvas.drawRRect(RRect.fromLTRBR(x, y, x + w, y + keyH, r), p);

    var y = top;
    for (var i = 0; i < 10; i++) {
      keyAt(i * (unit + gap), y, unit, keyPaint);
    }
    y += keyH + rowGap;
    final inset = (unit + gap) / 2;
    for (var i = 0; i < 9; i++) {
      keyAt(inset + i * (unit + gap), y, unit, keyPaint);
    }
    y += keyH + rowGap;
    final side = unit * 1.4;
    keyAt(0, y, side, fnPaint);
    final lettersX = (size.width - (unit * 7 + gap * 6)) / 2;
    for (var i = 0; i < 7; i++) {
      keyAt(lettersX + i * (unit + gap), y, unit, keyPaint);
    }
    keyAt(size.width - side, y, side, fnPaint);
    y += keyH + rowGap;
    final mode = unit * 2.2;
    keyAt(0, y, mode, fnPaint);
    keyAt(size.width - mode, y, mode, fnPaint);
    keyAt(mode + gap, y, size.width - mode * 2 - gap * 2, keyPaint);
  }

  @override
  bool shouldRepaint(_MiniKeyboard old) => old.key != key || old.fn != fn;
}
