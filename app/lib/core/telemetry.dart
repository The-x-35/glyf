import 'dart:convert';
import 'dart:io';

import 'auth.dart';
import 'bridge.dart';
import 'glyf_api.dart';

/// §12: events + timings only — NEVER content. JSONL on device is the source
/// of truth; batches also flush to POST /telemetry (M7 sink) best-effort —
/// the server counts events per day, so a lost batch only dents a count.
/// §6.18: "Instrument every step. Report the funnel weekly."
abstract final class Telemetry {
  static File? _file;
  static final List<String> _pending = [];
  static final List<Map<String, dynamic>> _unflushed = [];
  static DateTime _lastFlush = DateTime.fromMillisecondsSinceEpoch(0);

  static Future<void> _ensure() async {
    if (_file != null) return;
    final dir = await GlyfBridge.documentsPath();
    if (dir == null) return;
    _file = File('$dir/telemetry.jsonl');
  }

  static Future<void> log(String event, [Map<String, Object?> props = const {}]) async {
    final entry = {
      'event': event,
      'ts': DateTime.now().toUtc().toIso8601String(),
      ...props,
    };
    _pending.add(jsonEncode(entry));
    _unflushed.add(entry);
    await _ensure();
    final f = _file;
    if (f != null) {
      try {
        await f.writeAsString('${_pending.join('\n')}\n', mode: FileMode.append);
        _pending.clear();
      } catch (_) {/* keep pending for next flush */}
    }
    await flush();
  }

  /// Delete account: events not yet written or sent are dropped (the file
  /// itself goes with the phone's erase).
  static void forget() {
    _pending.clear();
    _unflushed.clear();
  }

  /// Throttled server flush — at most one batch per 15s, fire-and-forget.
  static Future<void> flush({bool force = false}) async {
    if (_unflushed.isEmpty) return;
    if (!force &&
        DateTime.now().difference(_lastFlush) < const Duration(seconds: 15)) {
      return;
    }
    _lastFlush = DateTime.now();
    final batch = List<Map<String, dynamic>>.from(_unflushed.take(500));
    // Signed in, the same events are kept with the account (names and
    // counts only, like everything here).
    if (Auth.signedIn) await Auth.sendEvents(batch.take(100).toList());
    if (await GlyfApi.telemetryPost(batch)) {
      _unflushed.removeRange(0, batch.length);
    }
  }

  static Future<List<Map<String, dynamic>>> recent({int limit = 200}) async {
    await _ensure();
    final f = _file;
    if (f == null || !f.existsSync()) return [];
    final lines = await f.readAsLines();
    return lines.reversed
        .take(limit)
        .map((l) {
          try {
            return jsonDecode(l) as Map<String, dynamic>;
          } catch (_) {
            return <String, dynamic>{};
          }
        })
        .where((m) => m.isNotEmpty)
        .toList();
  }
}
