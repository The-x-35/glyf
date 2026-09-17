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

  /// Board colours, each one a whole keyboard (see KeyPalette).
  static const _colors = <String, Color>{
    'Stone': Color(0xFFD5D8DE),
    'Lilac': Color(0xFFE3E1F6),
    'Sky': Color(0xFFD9E7F7),
    'Mint': Color(0xFFD7EBE1),
    'Sand': Color(0xFFF6E3DA),
    'Blush': Color(0xFFF2E2EC),
    'Ink': Color(0xFF1F1F22),
    'Indigo': Color(0xFF232437),
    'Midnight': Color(0xFF14202E),
    'Pine': Color(0xFF15241D),
    'Plum': Color(0xFF2A1D22),
    'Cocoa': Color(0xFF3A2E24),
  };

  static const _gradients = <String, List<Color>>{
    'dusk': [Color(0xFF7C5CFF), Color(0xFFEC6ADE)],
    'ocean': [Color(0xFF3D8BFF), Color(0xFF41E0C8)],
    'ember': [Color(0xFFFF7847), Color(0xFFFFC53D)],
    'forest': [Color(0xFF1FA968), Color(0xFF9BE15D)],
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await GlyfBridge.sharedSettings();
    if (mounted) setState(() => _settings = s);
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
            for (final e in _colors.entries)
              _tile(e.key,
                  board: e.value,
                  selected: _themeBg == _hex(e.value),
                  onTap: () => _set('themeBg', _hex(e.value))),
            for (final e in _gradients.entries)
              _tile(e.key[0].toUpperCase() + e.key.substring(1),
                  gradient: e.value,
                  selected: _themeBg == 'grad:${e.key}',
                  onTap: () => _set('themeBg', 'grad:${e.key}')),
          ]),
          const SizedBox(height: 18),
          _card([
            _segmented('Appearance', 'appearance', const ['auto', 'light', 'dark']),
            _switch('Borders around keys', 'keyBorders'),
          ]),
          const SizedBox(height: 18),
          _label('Typing'),
          _card([
            _switch('Autocorrect', 'autocorrect'),
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
          _label('Clipboard & AI'),
          _card([
            _switch('Keep what you copy', 'clipboardHistory', fallback: true),
            // Gboard's "Save recent screenshots in clipboard".
            _switch('Save recent screenshots', 'clipboardScreenshots',
                onBeforeOn: GlyfBridge.screenshotAccess),
            _switch('Let AI use your saved details', 'aiUsesVault', fallback: true),
          ]),
        ],
      ),
    );
  }

  static String _hex(Color c) =>
      'color:#${c.toARGB32().toRadixString(16).substring(2)}';

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
      {bool fallback = false, Future<bool> Function()? onBeforeOn}) {
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
            if (v && onBeforeOn != null && !await onBeforeOn()) return;
            _set(key, v);
          },
        ),
      ]),
    );
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
        childAspectRatio: 0.82,
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
                padding: const EdgeInsets.all(8),
                // LayoutBuilder sizes the keys to the space there is, so the
                // preview can never overflow its tile.
                child: LayoutBuilder(builder: (context, box) {
                  const rows = 3, gap = 3.0;
                  final keyH = (box.maxHeight - gap * (rows - 1)) / rows;
                  return Column(children: [
                    for (var r = 0; r < rows; r++) ...[
                      if (r > 0) const SizedBox(height: gap),
                      SizedBox(
                        height: keyH,
                        child: Row(children: [
                          for (var i = 0; i < 5; i++)
                            Expanded(
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                                decoration: BoxDecoration(
                                  color: r == 2 && (i == 0 || i == 4)
                                      ? palette.fn
                                      : keyColor,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                        ]),
                      ),
                    ],
                  ]);
                }),
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
