import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../core/bridge.dart';
import '../core/catalog.dart';
import '../build/builder_screen.dart';
import '../core/telemetry.dart';
import '../core/theme.dart';
import 'keyboard_visual.dart';

/// Home — your keyboard, drawn live. Bound keys glow on the visual; tap a
/// free key for recommendations, a bound one to change it. The try field
/// sits right underneath — nothing to scroll for.
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  bool _keyboardEnabled = false;
  bool _keyboardSelected = false;
  Map<String, dynamic>? _ping;
  Map<String, dynamic> _settings = {};
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final enabled = await GlyfBridge.keyboardEnabled();
    final selected =
        Platform.isAndroid ? await GlyfBridge.keyboardSelected() : false;
    final ping = await GlyfBridge.keyboardPing();
    final settings = await GlyfBridge.sharedSettings();
    if (!mounted) return;
    setState(() {
      _keyboardEnabled = enabled;
      _keyboardSelected = selected;
      _ping = ping;
      _settings = settings;
    });
  }

  bool get _fullAccess => _ping?['hasFullAccess'] == true;

  /// Step 2 differs per platform: iOS needs Full Access granted, Android
  /// needs Glyf picked as the current keyboard.
  bool get _step2 => Platform.isAndroid ? _keyboardSelected : _fullAccess;
  bool get _ready => _keyboardEnabled && _step2;

  Map<String, String> get _bindings =>
      ((_settings['bindings'] as Map<String, dynamic>?) ?? const {})
          .map((k, v) => MapEntry(k, v.toString()));

  Future<void> _setBinding(String key, String? glyfId) async {
    await GlyfBridge.updateSharedSettings((s) {
      final b = Map<String, dynamic>.from(
          (s['bindings'] as Map<String, dynamic>?) ?? {});
      if (glyfId == null) {
        b.remove(key);
      } else {
        b[key] = glyfId;
      }
      s['bindings'] = b;
      return s;
    });
    Telemetry.log('binding_changed', {'key': key, 'bound': glyfId != null});
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final bound = _bindings.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          Row(children: [
            const GlyfWordmark(size: 30),
            const Spacer(),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _ready
                  ? const SizedBox.shrink(key: ValueKey('ready'))
                  : Container(
                      key: const ValueKey('setup'),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Glass.hairline),
                      ),
                      child: const Text('setup',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Glass.inkSoft)),
                    ),
            ),
          ]),
          const SizedBox(height: 18),

          // Setup card ONLY while something is missing — it disappears the
          // moment the keyboard is fully live.
          if (!_ready) ...[
            GlassCard(
              child: Column(children: [
                _statusRow('Keyboard enabled', _keyboardEnabled,
                    fix: GlyfBridge.openSettings),
                if (Platform.isAndroid)
                  _statusRow('Switched to Glyf', _keyboardSelected,
                      fix: GlyfBridge.showImePicker)
                else
                  _statusRow('Full Access', _fullAccess,
                      fix: GlyfBridge.openSettings),
              ]),
            ),
            const SizedBox(height: 18),
          ],

          // The keyboard itself, live.
          KeyboardVisual(
            bindings: _bindings,
            onKeyTap: _keyTapped,
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              '${bound.length} keys bound',
              style: const TextStyle(color: Glass.inkSoft, fontSize: 12),
            ),
          ),
          const SizedBox(height: 16),

          // Try field — right here, no scrolling.
          GlassCard(
            padding: const EdgeInsets.all(6),
            child: TextField(
              maxLines: 3,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(color: Glass.ink, fontSize: 15),
              decoration: InputDecoration(
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(12),
                hintText: 'Type something…',
                hintStyle: TextStyle(
                    color: Glass.inkSoft.withValues(alpha: 0.7),
                    fontSize: 14),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Bound keys as full cards — tap to change.
          for (final e in bound)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GlassCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                onTap: () => _keyTapped(e.key),
                child: Row(children: [
                  _keycap(e.key),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(Catalog.byId(e.value).title,
                        style: const TextStyle(
                            color: Glass.ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                  ),
                  Text(Catalog.byId(e.value).emoji,
                      style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right,
                      color: Color(0xFFB9BEC7), size: 20),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _keycap(String letter) {
    // No `alignment` on the Container: it must hand the Stack tight 40×40
    // constraints so the dot pins to the keycap corner, not the letter.
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Glass.hairline),
        boxShadow: const [
          BoxShadow(
              color: Color(0x10000000), blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Stack(children: [
        Center(
          child: Text(letter.toUpperCase(),
              style: const TextStyle(
                  color: Glass.ink, fontSize: 17, fontWeight: FontWeight.w700)),
        ),
        Positioned(
          right: 6,
          top: 6,
          child: Container(
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
                color: Glass.accent, shape: BoxShape.circle),
          ),
        ),
      ]),
    );
  }

  Widget _statusRow(String label, bool ok, {required Future<void> Function() fix}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked,
            color: ok ? Glass.success : const Color(0xFFC5C9D1), size: 20),
        const SizedBox(width: 12),
        Expanded(
            child: Text(label,
                style: const TextStyle(color: Glass.ink, fontSize: 14.5))),
        if (!ok)
          TextButton(
              onPressed: () => fix(),
              child: const Text('Open Settings',
                  style: TextStyle(color: Glass.ink, fontSize: 12.5))),
      ]),
    );
  }

  // ── key sheets ───────────────────────────────────────────────────────────

  void _keyTapped(String letter) {
    final current = _bindings[letter];
    if (current != null) {
      _showBoundSheet(letter, current);
    } else {
      _showKeySheet(letter);
    }
  }

  /// What a key can hold: the three holds built into the keyboard, the glyfs
  /// this person built, or a new one made for this key.
  void _showKeySheet(String letter) {
    final current = _bindings[letter];
    final mine = (_settings['customTitles'] as Map<String, dynamic>?) ?? const {};
    const holds = [
      ('surface:vault', '🗂️', 'Vault', null),
      ('connector:calendar', '📅', 'Calendar', null),
      ('surface:translate-hud', '🌐', 'Translate', null),
      ('surface:tones', '🎚️', 'Rewrite', null),
    ];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(Glass.radiusSheet))),
      builder: (ctx) {
        Widget option(String id, String emoji, String title, String? subtitle) =>
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                borderColor: current == id ? Glass.accent : null,
                onTap: () {
                  Navigator.of(ctx).pop();
                  _setBinding(letter, id);
                },
                child: Row(children: [
                  Text(emoji, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: const TextStyle(
                                  color: Glass.ink,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                          if (subtitle != null)
                            Text(subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Glass.inkSoft, fontSize: 12)),
                        ]),
                  ),
                  Icon(current == id ? Icons.check_circle : Icons.add_circle_outline,
                      size: 20, color: current == id ? Glass.accent : Glass.ink),
                ]),
              ),
            );
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 14),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text.rich(TextSpan(children: [
                const TextSpan(text: 'Hold '),
                TextSpan(
                    text: '‘${letter.toUpperCase()}’',
                    style: const TextStyle(color: Glass.accent)),
                const TextSpan(text: ' to…'),
              ]),
                  style: const TextStyle(
                      color: Glass.ink, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  for (final (id, emoji, title, subtitle) in holds)
                    option(id, emoji, title, subtitle),
                  for (final e in mine.entries)
                    option(e.key, '✨', e.value.toString(), null),
                ]),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => BuilderScreen(initialKey: letter)));
                  _refresh();
                },
                child: const Text('Build your own',
                    style: TextStyle(
                        color: Glass.ink, fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        );
      },
    );
  }

  void _showBoundSheet(String letter, String glyfId) {
    final g = Catalog.byId(glyfId);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(Glass.radiusSheet))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(g.emoji, style: const TextStyle(fontSize: 34)),
            const SizedBox(height: 8),
            Text(g.title,
                style: const TextStyle(
                    color: Glass.ink,
                    fontSize: 19,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text('Hold ${letter.toUpperCase()} to fire',
                style: const TextStyle(color: Glass.inkSoft, fontSize: 13)),
            const SizedBox(height: 18),
            PillButton(
                label: 'Change',
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _showKeySheet(letter);
                }),
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _setBinding(letter, null);
              },
              child: const Text('Unbind',
                  style: TextStyle(color: Glass.danger, fontSize: 14)),
            ),
          ]),
        ),
      ),
    );
  }

}
