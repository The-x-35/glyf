import 'dart:convert';
import 'dart:io';

import 'bridge.dart';
import 'telemetry.dart';

/// The setup funnel, counts only (GO-TO-MARKET.md, "Do this first" 1): the
/// keyboard added in Settings, opened, given Full Access, a first strip answer
/// used, a first AI run. The keyboard writes its milestones once each to
/// bridge/funnel.json; this sends each as an event name, once, and never
/// anything typed.
abstract final class Funnel {
  static const steps = ['keyboard_opened', 'full_access', 'first_answer', 'first_ai'];

  static Future<void> report() async {
    try {
      final docs = await GlyfBridge.documentsPath();
      final base = await GlyfBridge.groupPath();
      if (docs == null || base == null) return;
      final sentFile = File('$docs/funnel_sent.json');
      final sent = <String>{
        if (sentFile.existsSync()) ...(jsonDecode(sentFile.readAsStringSync()) as List).cast<String>(),
      };
      final fresh = <String>[];
      if (!sent.contains('keyboard_added') && await GlyfBridge.keyboardEnabled()) fresh.add('keyboard_added');
      final file = File(Platform.isIOS ? '$base/bridge/funnel.json' : '$base/funnel.json');
      if (file.existsSync()) {
        final marks = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        for (final step in steps) {
          if (marks.containsKey(step) && !sent.contains(step)) fresh.add(step);
        }
      }
      if (fresh.isEmpty) return;
      for (final step in fresh) {
        await Telemetry.log('funnel_$step');
        sent.add(step);
      }
      sentFile.writeAsStringSync(jsonEncode(sent.toList()));
    } catch (_) {
      // A count is never worth an error on screen.
    }
  }
}
