import 'package:flutter/material.dart';

import '../core/bridge.dart';
import '../core/catalog.dart';
import '../core/telemetry.dart';
import '../core/theme.dart';
import '../home/keyboard_visual.dart';

/// The key picker: the same QWERTY keyboard as Home, so a key is found
/// where the thumb already knows it is. Keys already holding something show
/// their dot and can still be picked (rebinding is allowed).
Future<String?> pickKey(BuildContext context, {required String title}) async {
  final settings = await GlyfBridge.sharedSettings();
  final bindings = ((settings['bindings'] as Map<String, dynamic>?) ?? {})
      .map((k, v) => MapEntry(k, v.toString()));
  if (!context.mounted) return null;
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Glass.bg,
    shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(Glass.radiusSheet))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(title,
              style: const TextStyle(
                  color: Glass.ink, fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          KeyboardVisual(
            bindings: bindings,
            onKeyTap: (c) => Navigator.of(ctx).pop(c),
          ),
        ]),
      ),
    ),
  );
}

/// Which key each glyf sits on, from shared settings.
Future<Map<String, String>> boundKeys() async {
  final settings = await GlyfBridge.sharedSettings();
  final bindings =
      (settings['bindings'] as Map<String, dynamic>?) ?? <String, dynamic>{};
  final byGlyf = <String, String>{};
  for (final e in bindings.entries) {
    if (e.value is String) byGlyf.putIfAbsent(e.value as String, () => e.key);
  }
  return byGlyf;
}

/// Take a deleted glyf off every key it was on, so no key fires nothing.
Future<void> unbindGlyf(String glyfId) async {
  await GlyfBridge.updateSharedSettings((s) {
    final b =
        Map<String, dynamic>.from((s['bindings'] as Map<String, dynamic>?) ?? {});
    b.removeWhere((_, target) => target == glyfId);
    s['bindings'] = b;
    return s;
  });
}

/// Bind [glyfId] to [letter] in shared settings; custom glyfs also record
/// their display name (the keyboard's GlyfCatalog reads customTitles §6.8).
Future<void> bindGlyf({
  required String letter,
  required String glyfId,
  String? displayName,
}) async {
  await GlyfBridge.updateSharedSettings((s) {
    final b =
        Map<String, dynamic>.from((s['bindings'] as Map<String, dynamic>?) ?? {});
    b[letter] = glyfId;
    s['bindings'] = b;
    if (displayName != null) {
      final titles = Map<String, dynamic>.from(
          (s['customTitles'] as Map<String, dynamic>?) ?? {});
      titles[glyfId] = displayName;
      s['customTitles'] = titles;
      Catalog.rememberCustomTitles(titles);
    }
    return s;
  });
  Telemetry.log('key_bound', {'glyfId': glyfId, 'key': letter});
}
