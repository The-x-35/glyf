import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../core/bridge.dart';
import '../core/flavor.dart';
import '../core/glyf_api.dart';
import '../core/telemetry.dart';
import '../core/theme.dart';
import '../core/themes.dart';
import '../wallet/wallet_flow.dart';
import 'theme_preview.dart';

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

  /// The letter layouts both keyboards draw (iOS LetterLayout, Android
  /// LetterLayout): QWERTY is today's keyboard and the default.
  static const _layouts = <String, String>{
    'qwerty': 'QWERTY',
    'qwertz': 'QWERTZ',
    'azerty': 'AZERTY',
    'colemak': 'Colemak',
  };

  @override
  void initState() {
    super.initState();
    _load();
    // The themes' textures for the tiles; they draw without grain until then.
    KbTextures.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _load() async {
    final s = await GlyfBridge.sharedSettings();
    if (mounted) setState(() => _settings = s);
    // The colour and gradient themes are retired for now: iOS draws a band
    // above every keyboard that a painted board can't reach, so it looked
    // cut off. A board picked before goes back to the default look.
    if (((s['themeBg'] as String?) ?? '').isNotEmpty) await _set('themeBg', '');
  }

  /// The last settings write: each waits for the one before, so two taps in
  /// a row can't read the same file and lose one of the changes.
  Future<void> _writes = Future.value();

  Future<void> _set(String key, Object value) {
    setState(() => _settings = Map.of(_settings)..[key] = value);
    final write = _writes.then(
        (_) => GlyfBridge.updateSharedSettings((s) => s..[key] = value));
    _writes = write.catchError((_) {});
    Telemetry.log('kb_setting_changed', {'setting': key});
    return write;
  }

  String get _themeBg => (_settings['themeBg'] as String?) ?? '';
  String get _keyTheme => (_settings['keyTheme'] as String?) ?? 'site';

  /// The picked keyboard theme ("skin"), or null for Glyf or Glass.
  KbTheme? get _skin => KbTheme.byId(_settings['skin'] as String?);

  /// The side of a theme the keyboard shows: Android's Appearance setting,
  /// else the phone's light or dark (the iPhone keyboard follows the app it
  /// types into, which mostly follows the phone).
  bool _previewDark(BuildContext context) {
    final appearance = Platform.isIOS ? 'auto' : (_settings['appearance'] as String?) ?? 'auto';
    if (appearance == 'dark') return true;
    if (appearance == 'light') return false;
    return MediaQuery.platformBrightnessOf(context) == Brightness.dark;
  }

  /// The picker's groups: the themes' categories in the order themes.json
  /// first uses them, each under its plural.
  static final _groups = <String, String>{
    for (final t in kbThemes) t.category: _plural(t.category),
  };

  static String _plural(String category) => switch (category) {
        'material' => 'Materials',
        'story' => 'Stories',
        'archetype' => 'Archetypes',
        'Nature' => 'Nature',
        // themes.json names some groups in the plural already (Objects).
        _ => '${category[0].toUpperCase()}${category.substring(1)}${category.endsWith('s') ? '' : 's'}',
      };

  @override
  Widget build(BuildContext context) {
    final skin = _skin;
    final dark = _previewDark(context);
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
            _tile('Glyf',
                selected: skin == null && _keyTheme == 'site' && _themeBg.isEmpty,
                onTap: () async {
                  await _set('keyTheme', 'site');
                  await _set('themeBg', '');
                  await _set('skin', '');
                }),
            _tile('Glass', board: const Color(0xFFD5D8DE), translucent: true,
                selected: skin == null && _keyTheme == 'glass' && _themeBg.isEmpty,
                onTap: () async {
                  await _set('keyTheme', 'glass');
                  await _set('themeBg', '');
                  await _set('skin', '');
                }),
          ]),
          // The keyboard themes (docs/THEMES.md), in the spec's groups.
          for (final group in _groups.entries) ...[
            const SizedBox(height: 16),
            _label(group.value),
            _grid([
              for (final t in kbThemes.where((t) => t.category == group.key))
                _themeTile(t, dark: dark, selected: skin?.id == t.id),
            ]),
          ],
          const SizedBox(height: 18),
          _card([
            // The iPhone keyboard follows the app it types into, like
            // Apple's: iOS draws the band above it and the bar below it in
            // that app's colour, so a forced light or dark looked cut off.
            if (!Platform.isIOS)
              _segmented('Appearance', 'appearance', const ['auto', 'light', 'dark']),
            // A theme with its own border always draws it (THEMES.md §5.1).
            if (skin?.variant(dark).border == null)
              _switch('Borders around keys', 'keyBorders'),
          ]),
          const SizedBox(height: 18),
          _label('Layout'),
          _card([
            _choiceRow('Letters', 'keyLayout', _layouts),
            _switch('Number row', 'numberRow'),
            _switch('Comma beside space', 'commaKey'),
            _switch('Period beside space', 'periodKey'),
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
            _switch('Glide typing', 'glideTyping', fallback: true),
          ]),
          const SizedBox(height: 18),
          _label('Feel'),
          _card([
            _switch('Sound on keypress', 'keyClicks'),
            if (skin != null && skin.sound != 'system')
              _switch('Theme sound', 'skinSound', fallback: true),
            _switch('Haptic feedback on keypress', 'haptics'),
          ]),
          const SizedBox(height: 18),
          _label('Money'),
          // The wallet is a feature people turn on (Arpit, 2026-10-14: "have
          // wallet as feature which we can enable from settings and not for
          // everyone"): Send, Buy and the Wallet screen appear with it.
          _card([_currencyRow(), _switch('Wallet', 'walletEnabled')]),
          const SizedBox(height: 18),
          _label('Clipboard & AI'),
          _card([
            _switch('Keep what you copy', 'clipboardHistory', fallback: true),
            // The iPhone's paste prompt only; Android has nothing like it.
            if (Platform.isIOS)
              _switch('Capture everything you copy', 'clipboardCaptureAll',
                  fallback: true),
            _switch('Recent screenshots', 'clipboardScreenshots',
                fallback: true,
                onBeforeOn: GlyfBridge.screenshotAccess,
                // Asked before and refused: the system won't ask again, so
                // say where it's allowed rather than let the switch flick back.
                denied: Platform.isIOS
                    ? 'Photos are off for Glyf. Allow them in Settings › Glyf › Photos'
                    : 'Photos are off for Glyf. Allow them in Settings › Apps › Glyf › Permissions'),
            _switch('AI suggestions as you type', 'aiSuggest'),
            if (Flavor.zeroG) _switch('Private AI on 0G', 'privateAI', fallback: true),
            if (Flavor.zeroG && ((_settings['privateAI'] as bool?) ?? true)) _receiptsRow(),
            _switch('Let AI use your saved details', 'aiUsesVault', fallback: true),
          ]),
        ],
      ),
    );
  }

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
            if (key == 'walletEnabled') WalletFlow.enabled.value = v;
            if (key == 'privateAI') GlyfApi.privateAI = v;
          },
        ),
      ]),
    );
  }

  /// Where the last AI answers ran: 0G's request id for each, and whether
  /// 0G checked the TEE's signature on it.
  Widget _receiptsRow() => InkWell(
        key: const ValueKey('ai:receipts'),
        onTap: _showReceipts,
        child: const Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(children: [
            Expanded(child: Text('0G receipts', style: TextStyle(fontSize: 15))),
            Icon(Icons.chevron_right, size: 20, color: Glass.inkSoft),
          ]),
        ),
      );

  Future<void> _showReceipts() async {
    final load = GlyfApi.zeroGReceipts();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Glass.radiusSheet))),
      builder: (ctx) => SafeArea(
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: load,
          builder: (ctx, snap) {
            final list = snap.data ?? const [];
            return ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 10),
                  child: Text('0G receipts',
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                ),
                if (snap.connectionState != ConnectionState.done)
                  const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator.adaptive()))
                else if (snap.hasError)
                  const _ReceiptNote('Couldn’t load them. Check the connection')
                else if (list.isEmpty)
                  const _ReceiptNote('No answers from 0G yet')
                else
                  for (final r in list) _ReceiptTile(r),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Type "$13" and the strip offers it in this currency. Token prices stay
  /// in dollars, which is how the market quotes them.
  Widget _currencyRow() => _choiceRow('Convert money to', 'moneyCurrency', _currencies);

  /// A setting with one value out of [options] (id → label): the row shows
  /// the picked one and opens a sheet of them. The first option is the
  /// default.
  Widget _choiceRow(String title, String key, Map<String, String> options) {
    final value = (_settings[key] as String?) ?? options.keys.first;
    return InkWell(
      key: ValueKey('choice:$key'),
      onTap: () => _pick(title, key, options),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 15))),
          Text(options[value] ?? options.values.first,
              style: const TextStyle(fontSize: 14, color: Glass.inkSoft)),
          const Icon(Icons.chevron_right, size: 18, color: Glass.inkSoft),
        ]),
      ),
    );
  }

  Future<void> _pick(String title, String key, Map<String, String> options) async {
    final current = (_settings[key] as String?) ?? options.keys.first;
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
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 10),
              child: Text(title,
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
            ),
            for (final e in options.entries)
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
    if (picked != null && picked != current) await _set(key, picked);
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

extension on _KeyboardScreenState {
  /// A theme's tile: its keyboard in miniature in the side the keyboard
  /// would show, on its own board on Android and on the system sheet on the
  /// iPhone (which paints no board, THEMES.md §0.3), and its name in its
  /// key-face font.
  Widget _themeTile(KbTheme t, {required bool dark, required bool selected}) {
    final v = t.variant(dark);
    final ios = Platform.isIOS;
    final sheet = dark ? const Color(0xFF1B1B1D) : const Color(0xFFE2E4E8);
    return GestureDetector(
      key: ValueKey('theme:${t.id}'),
      onTap: () => _set('skin', t.id),
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
                  color: ios || v.board.length < 2 ? (ios ? sheet : v.board.first) : null,
                  gradient: ios || v.board.length < 2
                      ? null
                      : LinearGradient(
                          begin: _cssBegin(v.boardAngle ?? 180),
                          end: _cssEnd(v.boardAngle ?? 180),
                          colors: v.board),
                ),
                padding: const EdgeInsets.fromLTRB(7, 8, 7, 7),
                child: CustomPaint(
                  painter: ThemeKeyboardPainter(v,
                      dark: dark,
                      fontFamily: t.fontFamily,
                      fontWeight: t.fontWeight,
                      variableFont: t.variableFont,
                      textures: Map.of(KbTextures.images),
                      dpr: MediaQuery.devicePixelRatioOf(context)),
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
              Flexible(
                child: Text(t.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        fontFamily: t.fontFamily,
                        fontWeight: t.fontFamily == null ? FontWeight.w600 : null,
                        fontVariations: t.variableFont
                            ? [FontVariation('wght', t.fontWeight.toDouble())]
                            : null)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  /// A CSS gradient angle (0 points up, clockwise) as Flutter's ends.
  Alignment _cssBegin(double deg) => -_cssEnd(deg);
  Alignment _cssEnd(double deg) {
    final r = deg * math.pi / 180;
    return Alignment(math.sin(r), -math.cos(r));
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


class _ReceiptNote extends StatelessWidget {
  const _ReceiptNote(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
        child: Text(text, style: const TextStyle(fontSize: 15, color: Glass.inkSoft)),
      );
}

/// One answer: the model, when, 0G's request id (tap to copy) and the TEE check.
class _ReceiptTile extends StatelessWidget {
  const _ReceiptTile(this.r);
  final Map<String, dynamic> r;

  @override
  Widget build(BuildContext context) {
    final id = '${r['requestId'] ?? ''}';
    final at = DateTime.fromMillisecondsSinceEpoch((r['at'] as num?)?.toInt() ?? 0);
    final tee = r['teeVerified'];
    final when = '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Text('${r['model'] ?? '0G'} · $when', style: const TextStyle(fontSize: 15)),
      subtitle: Text(id,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontFamily: 'Menlo', color: Glass.inkSoft)),
      trailing: Text(tee == true ? 'TEE ✓' : tee == false ? 'TEE ✕' : 'TEE –',
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: tee == true ? const Color(0xFF34C759) : Glass.inkSoft)),
      onTap: () {
        Clipboard.setData(ClipboardData(text: id));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request id copied')));
      },
    );
  }
}
