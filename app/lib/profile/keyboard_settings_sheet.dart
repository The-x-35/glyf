import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';

import '../core/bridge.dart';
import '../core/telemetry.dart';
import '../core/theme.dart';

/// One key-style option: a mini three-key preview drawn in that style,
/// Snapchat-App-Themes-style card with a check when selected.
class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.id,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final String id;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Widget key(bool bound) {
      final glass = id == 'glass';
      final glow = id == 'glow';
      return Container(
        width: 26,
        height: 34,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: glow && bound
              ? const Color(0xFFF6F3FF)
              : glass
                  ? Colors.white.withValues(alpha: 0.62)
                  : Colors.white,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: Glass.hairline),
          boxShadow: [
            if (glow && bound)
              BoxShadow(
                  color: Glass.accent.withValues(alpha: 0.45),
                  blurRadius: 6,
                  offset: const Offset(0, 2))
            else if (!glass)
              const BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 0,
                  offset: Offset(0, 1)),
          ],
        ),
        child: bound
            ? Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(3.5),
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: const BoxDecoration(
                        color: Glass.accent, shape: BoxShape.circle),
                  ),
                ),
              )
            : null,
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFEDEFF3),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? Glass.ink : Colors.transparent,
              width: 1.8),
        ),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            key(false),
            key(true),
            key(false),
          ]),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (selected) ...[
              const Icon(Icons.check_circle, size: 13, color: Glass.ink),
              const SizedBox(width: 3),
            ],
            Text(name,
                style: TextStyle(
                    color: Glass.ink,
                    fontSize: 12,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w500)),
          ]),
        ]),
      ),
    );
  }
}

/// Keyboard Settings — every typing preference in one sheet, mirrored live
/// into the keyboard through shared settings.
Future<void> showKeyboardSettings(BuildContext context) async {
  var settings = await GlyfBridge.sharedSettings();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(Glass.radiusSheet))),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        Future<void> flip(String key, bool v) async {
          await GlyfBridge.updateSharedSettings((s) => s..[key] = v);
          settings = Map<String, dynamic>.from(settings)..[key] = v;
          setSheet(() {});
          Telemetry.log('kb_setting_changed', {'setting': key});
        }

        Widget switchRow(String label, bool value, ValueChanged<bool> onChanged,
            {String? subtitle}) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
            child: Row(children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style:
                              const TextStyle(color: Glass.ink, fontSize: 15)),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(subtitle,
                              style: const TextStyle(
                                  color: Glass.inkSoft, fontSize: 12.5)),
                        ),
                    ]),
              ),
              CupertinoSwitch(
                value: value,
                activeTrackColor: Glass.ink,
                onChanged: onChanged,
              ),
            ]),
          );
        }

        Widget toggle(String label, String key) =>
            switchRow(label, settings[key] == true, (v) => flip(key, v));

        /// Search paste style is a string, not a bool: on = Gboard's
        /// link + title, off = the bare link.
        Widget pasteToggle() {
          final on = (settings['pasteStyle'] as String? ?? 'titleAndLink') ==
              'titleAndLink';
          return switchRow(
            'Paste title with link',
            on,
            (v) async {
              final value = v ? 'titleAndLink' : 'linkOnly';
              await GlyfBridge.updateSharedSettings(
                  (s) => s..['pasteStyle'] = value);
              settings = Map<String, dynamic>.from(settings)
                ..['pasteStyle'] = value;
              setSheet(() {});
              Telemetry.log('kb_setting_changed', {'setting': 'pasteStyle'});
            },
            subtitle: on
                ? 'Search results paste the link, then the title'
                : 'Search results paste only the link',
          );
        }

        final languages = const [
          'English', 'Hindi', 'Hinglish', 'Spanish', 'French', 'German',
          'Portuguese', 'Japanese',
        ];
        final target = (settings['translateTarget'] as String?) ?? 'English';

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 10),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Keyboard',
                  style: TextStyle(
                      color: Glass.ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Flexible(
                child: ListView(shrinkWrap: true, children: [
                  // Gboard-style key design picker with live mini previews.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    child: Row(children: [
                      for (final (id, name) in const [
                        ('glass', 'Glass'),
                        ('classic', 'Classic'),
                        ('glow', 'Glow'),
                      ])
                        Expanded(
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 4),
                            child: _ThemeCard(
                              id: id,
                              name: name,
                              selected:
                                  (settings['keyTheme'] ?? 'glass') == id,
                              onTap: () async {
                                await GlyfBridge.updateSharedSettings(
                                    (s) => s..['keyTheme'] = id);
                                settings =
                                    Map<String, dynamic>.from(settings)
                                      ..['keyTheme'] = id;
                                setSheet(() {});
                                Telemetry.log('kb_setting_changed',
                                    {'setting': 'keyTheme'});
                              },
                            ),
                          ),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                    child: Row(children: [
                      const Expanded(
                        child: Text('Appearance',
                            style:
                                TextStyle(color: Glass.ink, fontSize: 15)),
                      ),
                      for (final a in const ['auto', 'light', 'dark'])
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: ChoiceChip(
                            label: Text(a,
                                style: const TextStyle(fontSize: 12)),
                            selected:
                                (settings['appearance'] ?? 'auto') == a,
                            selectedColor: Glass.ink,
                            labelStyle: TextStyle(
                                color:
                                    (settings['appearance'] ?? 'auto') == a
                                        ? Colors.white
                                        : Glass.ink),
                            backgroundColor: const Color(0xFFF2F3F7),
                            side: BorderSide.none,
                            showCheckmark: false,
                            onSelected: (v) async {
                              await GlyfBridge.updateSharedSettings(
                                  (s) => s..['appearance'] = a);
                              settings =
                                  Map<String, dynamic>.from(settings)
                                    ..['appearance'] = a;
                              setSheet(() {});
                              Telemetry.log('kb_setting_changed',
                                  {'setting': 'appearance'});
                            },
                          ),
                        ),
                    ]),
                  ),
                  toggle('Key sounds', 'keyClicks'),
                  toggle('Haptics', 'haptics'),
                  toggle('Number row', 'numberRow'),
                  toggle('Autocorrect', 'autocorrect'),
                  toggle('Auto-capitalize', 'autocapitalize'),
                  toggle('“.” shortcut', 'periodShortcut'),
                  toggle('Suggestions', 'candidates'),
                  pasteToggle(),
                  const SizedBox(height: 8),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Translate to',
                        style: TextStyle(
                            color: Glass.ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Wrap(spacing: 6, runSpacing: 4, children: [
                      for (final lang in languages)
                        ChoiceChip(
                          label: Text(lang,
                              style: const TextStyle(fontSize: 12)),
                          selected: target == lang,
                          selectedColor: Glass.ink,
                          labelStyle: TextStyle(
                              color:
                                  target == lang ? Colors.white : Glass.ink),
                          backgroundColor: const Color(0xFFF2F3F7),
                          side: BorderSide.none,
                          showCheckmark: false,
                          onSelected: (v) async {
                            await GlyfBridge.updateSharedSettings(
                                (s) => s..['translateTarget'] = lang);
                            settings = Map<String, dynamic>.from(settings)
                              ..['translateTarget'] = lang;
                            setSheet(() {});
                          },
                        ),
                    ]),
                  ),
                ]),
              ),
            ]),
          ),
        );
      },
    ),
  );
}
