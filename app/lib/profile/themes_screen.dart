import 'package:flutter/cupertino.dart' show CupertinoSwitch, CupertinoSlider;
import 'package:flutter/material.dart';

import '../core/bridge.dart';
import '../core/theme.dart';

/// Gboard-style theme picker (studied from the ref recording): categories
/// with live mini-previews, a check on the active theme, and an Edit sheet
/// (key borders, background dim) on the selected tile. Everything writes
/// straight into shared settings — the keyboard re-skins on next show.
class ThemesScreen extends StatefulWidget {
  const ThemesScreen({super.key});

  @override
  State<ThemesScreen> createState() => _ThemesScreenState();
}

class _ThemesScreenState extends State<ThemesScreen> {
  Map<String, dynamic> _settings = {};

  static const gradients = <String, List<Color>>{
    'dusk': [Color(0xFF7C5CFF), Color(0xFFEC6ADE)],
    'ocean': [Color(0xFF3D8BFF), Color(0xFF41E0C8)],
    'ember': [Color(0xFFFF7847), Color(0xFFFFC53D)],
    'forest': [Color(0xFF1FA968), Color(0xFF9BE15D)],
  };

  static const colors = <Color>[
    Color(0xFF17181C), Color(0xFF7C5CFF), Color(0xFF1F72E0),
    Color(0xFF1FA968), Color(0xFFE0568C), Color(0xFF8A5A2E),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await GlyfBridge.sharedSettings();
    if (!mounted) return;
    setState(() => _settings = s);
  }

  String get _keyTheme => (_settings['keyTheme'] as String?) ?? 'glass';
  String get _themeBg => (_settings['themeBg'] as String?) ?? '';
  bool get _keyBorders => _settings['keyBorders'] == true;
  double get _dim => (_settings['themeBrightness'] as num?)?.toDouble() ?? 0;

  Future<void> _apply({String? keyTheme, String? themeBg}) async {
    await GlyfBridge.updateSharedSettings((s) {
      if (keyTheme != null) s['keyTheme'] = keyTheme;
      if (themeBg != null) s['themeBg'] = themeBg;
      return s;
    });
    _load();
  }

  Future<void> _set(String key, Object value) async {
    await GlyfBridge.updateSharedSettings((s) {
      s[key] = value;
      return s;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Glass.bg,
      appBar: AppBar(
        backgroundColor: Glass.bg,
        surfaceTintColor: Colors.transparent,
        title: const Text('Keyboard themes',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 30),
        children: [
          _section('Default'),
          Row(children: [
            _themeTile('Glass', keyTheme: 'glass', bg: ''),
            const SizedBox(width: 12),
            _themeTile('Classic', keyTheme: 'classic', bg: ''),
            const SizedBox(width: 12),
            _themeTile('Glow', keyTheme: 'glow', bg: ''),
          ]),
          const SizedBox(height: 22),
          _section('Colors'),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final c in colors)
                _colorTile('#${c.toARGB32().toRadixString(16).substring(2)}'),
            ],
          ),
          const SizedBox(height: 22),
          _section('Gradients'),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final id in gradients.keys) _gradientTile(id),
            ],
          ),
          const SizedBox(height: 26),
          _section('Edit'),
          _editCard(),
        ],
      ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10, left: 2),
        child: Text(t,
            style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: Glass.inkSoft)),
      );

  /// Mini keyboard preview, Gboard-thumbnail style.
  Widget _preview({Color? bg, List<Color>? grad, required bool darkKeys}) {
    final keyColor = darkKeys
        ? Colors.white.withValues(alpha: 0.42)
        : Colors.white.withValues(alpha: 0.92);
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: grad == null ? (bg ?? const Color(0xFFD1D4D9)) : null,
        gradient: grad == null
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: grad),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
      child: Column(
        children: [
          for (final n in [8, 7]) ...[
            Row(
              children: [
                for (var i = 0; i < n; i++)
                  Expanded(
                    child: Container(
                      height: 15,
                      margin: const EdgeInsets.symmetric(
                          horizontal: 1.6, vertical: 1.6),
                      decoration: BoxDecoration(
                        color: keyColor,
                        borderRadius: BorderRadius.circular(3.5),
                        border: _keyBorders
                            ? Border.all(
                                color: Colors.black.withValues(alpha: 0.18),
                                width: 0.7)
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _tileShell({
    required Widget preview,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 104,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: active ? Glass.accent : Glass.hairline,
              width: active ? 1.6 : 1),
          boxShadow: const [
            BoxShadow(
                color: Color(0x0D000000), blurRadius: 6, offset: Offset(0, 3)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(children: [
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(11)),
                child: preview,
              ),
              if (active)
                const Positioned(
                  right: 6,
                  top: 6,
                  child: CircleAvatar(
                    radius: 9,
                    backgroundColor: Glass.accent,
                    child: Icon(Icons.check, size: 12, color: Colors.white),
                  ),
                ),
            ]),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _themeTile(String label,
      {required String keyTheme, required String bg}) {
    final active = _keyTheme == keyTheme && _themeBg.isEmpty;
    return _tileShell(
      preview: _preview(darkKeys: false),
      label: label,
      active: active,
      onTap: () => _apply(keyTheme: keyTheme, themeBg: ''),
    );
  }

  Widget _colorTile(String hex) {
    final id = 'color:$hex';
    final color = Color(int.parse('FF${hex.substring(1)}', radix: 16));
    return _tileShell(
      preview: _preview(bg: color, darkKeys: true),
      label: hex.toUpperCase(),
      active: _themeBg == id,
      onTap: () => _apply(themeBg: id),
    );
  }

  Widget _gradientTile(String id) {
    return _tileShell(
      preview: _preview(grad: gradients[id], darkKeys: true),
      label: id[0].toUpperCase() + id.substring(1),
      active: _themeBg == 'grad:$id',
      onTap: () => _apply(themeBg: 'grad:$id'),
    );
  }

  /// The Gboard "Customize theme" essentials: borders + background dim.
  Widget _editCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Glass.hairline),
      ),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Borders around keys',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
                CupertinoSwitch(
                  value: _keyBorders,
                  activeTrackColor: Glass.accent,
                  onChanged: (v) => _set('keyBorders', v),
                ),
              ],
            ),
          ),
          Row(
            children: [
              const Text('Background dim',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              Expanded(
                child: CupertinoSlider(
                  value: _dim.clamp(0, 0.6),
                  max: 0.6,
                  activeColor: Glass.accent,
                  onChanged: (v) => setState(() => _settings['themeBrightness'] = v),
                  onChangeEnd: (v) =>
                      _set('themeBrightness', double.parse(v.toStringAsFixed(2))),
                ),
              ),
            ],
          ),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Dim applies to color and gradient themes.',
                style: TextStyle(fontSize: 12, color: Glass.inkSoft)),
          ),
        ],
      ),
    );
  }
}
