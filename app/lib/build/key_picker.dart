import 'package:flutter/material.dart';

import '../core/bridge.dart';
import '../core/catalog.dart';
import '../core/telemetry.dart';
import '../core/theme.dart';

/// The letter grid sheet — shared by the catalog, the Builder, and the Hub.
/// Returns the chosen letter, or null. Taken keys render dimmed but stay
/// tappable (rebinding is allowed; the §6.14 diff idea in one key).
Future<String?> pickKey(BuildContext context, {required String title}) async {
  final settings = await GlyfBridge.sharedSettings();
  final bindings =
      (settings['bindings'] as Map<String, dynamic>?) ?? <String, dynamic>{};
  if (!context.mounted) return null;
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(Glass.radiusSheet))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(title,
              style: const TextStyle(
                  color: Glass.ink, fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in 'abcdefghijklmnopqrstuvwxyz'.split(''))
              GestureDetector(
                onTap: () => Navigator.of(ctx).pop(c),
                child: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: bindings.containsKey(c)
                        ? const Color(0xFFEDEEF2)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: bindings.containsKey(c)
                            ? Colors.transparent
                            : Glass.hairline),
                  ),
                  child: Text(c.toUpperCase(),
                      style: TextStyle(
                          color: bindings.containsKey(c)
                              ? const Color(0xFFB6BAC3)
                              : Glass.ink,
                          fontWeight: FontWeight.w700)),
                ),
              ),
          ]),
          const SizedBox(height: 10),
        ]),
      ),
    ),
  );
}

/// Bind [glyfId] to [letter] in shared settings; custom/hub glyfs also record
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
