import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'trade_flow.dart';

/// The trade in flight on the Lock Screen and in the Dynamic Island (iOS):
/// every step the trade screen shows goes to the native Live Activity
/// (app/ios/Runner/TradeActivityHost.swift), which reads the trade's query
/// and the step and draws Placing → Waiting for the wallet → Placed or
/// Confirmed (or Failed). Nothing goes to a server.
abstract final class TradeActivity {
  static const _ch = MethodChannel('so.glyf/bridge');
  static final _ids = Expando<String>('trade-activity');
  static int _n = 0;

  /// What the native side reads: the trade's query and this step.
  @visibleForTesting
  static Map<String, Object?> payload(String id, Map<String, String> query, TradeOutcome o) => {
        'id': id,
        'query': query,
        'state': o.state.name,
        'title': o.title,
        if (o.detail != null) 'detail': o.detail,
        if (o.txUrl != null) 'link': o.txUrl,
        if (o.orderId != null) 'orderId': o.orderId,
        'reopen': o.reopen != null,
      };

  /// One step of the trade [owner] (the screen) is running. Never throws:
  /// an Island that can't show is no reason to stop a trade.
  static Future<void> show(Object owner, Map<String, String> query, TradeOutcome o) async {
    if (defaultTargetPlatform != TargetPlatform.iOS || query['kind'] == 'cancel') return;
    final id = _ids[owner] ??= 'trade-${DateTime.now().millisecondsSinceEpoch}-${_n++}';
    try {
      await _ch.invokeMethod<bool>('liveActivity.update', payload(id, query, o));
    } on PlatformException {
      // Live Activities off for Glyf, or too many running.
    } on MissingPluginException {
      // Tests, and platforms without the bridge.
    }
  }

  /// A Flash order cancelled (from the Island's Cancel or the order list):
  /// its activity says so and goes.
  static Future<void> cancelled(String orderId) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      await _ch.invokeMethod<bool>('liveActivity.cancelled', {'orderId': orderId});
    } on PlatformException {
      // Nothing to end.
    } on MissingPluginException {
      // Tests.
    }
  }
}
