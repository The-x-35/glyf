import 'package:flutter/material.dart';

import '../core/glyf_api.dart';
import '../core/theme.dart';
import 'evm_chains.dart';
import 'evm_signer.dart';
import 'trade_activity.dart';
import 'trade_flow.dart';

/// Cancels a Flash order: Flash's own cancel message, signed by the wallet
/// that funds the order (EIP-191); no transaction and no fee. The order
/// list's Cancel and the Live Activity's (glyf://open?path=flash-cancel&id=…)
/// both come here.
abstract final class FlashCancel {
  static Future<void> run(String id) async {
    final message = 'Definitive Flash v1 — Cancel Order\nOrder: $id';
    String? signature;
    await for (final e in EvmSigner.run('Cancel a Flash order', [MessageStep(EvmChain.base, 'Cancel the order', message)])) {
      if (e.results != null) signature = e.results!.single.signature;
    }
    await GlyfApi.evmPost('/flash/orders/$id/cancel', {'cancelMessage': message, 'userSignature': signature});
    await TradeActivity.cancelled(id);
  }

  /// The same, as the trade screen's steps.
  static Stream<TradeOutcome> steps(String id) async* {
    yield const TradeOutcome(TradeState.working, 'Cancelling the order…');
    try {
      await run(id);
      yield const TradeOutcome(TradeState.done, 'Order cancelled', detail: 'Flash won’t place it');
    } on SignFailed catch (e) {
      yield TradeOutcome(TradeState.failed, e.cancelled ? 'Not cancelled' : e.title, detail: e.detail);
    } on GlyfApiException catch (e) {
      yield TradeOutcome(TradeState.failed, 'Flash didn’t cancel it', detail: e.message);
    }
  }
}

/// The Flash orders this wallet has waiting (stop-losses, take-profits,
/// limits, trails, TWAPs), newest first, each with a Cancel.
class FlashOrdersList extends StatefulWidget {
  const FlashOrdersList({super.key, required this.address});

  final String address;

  @override
  State<FlashOrdersList> createState() => _FlashOrdersListState();
}

class _FlashOrdersListState extends State<FlashOrdersList> {
  List<Map<String, dynamic>>? _orders;
  final _cancelling = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await GlyfApi.evmGet('/flash/orders?funderAddress=${widget.address}');
      final list = (res['orders'] ?? res['data'] ?? const []) as List;
      if (mounted) setState(() => _orders = list.map((o) => Map<String, dynamic>.from(o as Map)).toList());
    } on Exception {
      if (mounted) setState(() => _orders = const []);
    }
  }

  Future<void> _cancel(String id) async {
    setState(() => _cancelling.add(id));
    try {
      await FlashCancel.run(id);
      await _load();
    } on SignFailed catch (e) {
      if (mounted && !e.cancelled) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } on Exception catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
    if (mounted) setState(() => _cancelling.remove(id));
  }

  static bool _open(Map<String, dynamic> o) {
    final s = '${o['status'] ?? o['state'] ?? ''}'.toLowerCase();
    return !(s.contains('fill') || s.contains('cancel') || s.contains('expire') || s.contains('fail') || s == 'done');
  }

  @override
  Widget build(BuildContext context) {
    final orders = _orders;
    if (orders == null || orders.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text('Orders', style: TextStyle(color: Glass.inkSoft, fontSize: 13, fontWeight: FontWeight.w700)),
        ),
        GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(
            children: [
              for (final (i, o) in orders.take(12).indexed) ...[
                if (i > 0) const Divider(height: 1, color: Glass.hairline),
                _row(o),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(Map<String, dynamic> o) {
    final id = '${o['orderId'] ?? o['id']}';
    final type = '${o['orderType'] ?? o['type'] ?? 'order'}'.replaceAll('-', ' ');
    final status = '${o['status'] ?? o['state'] ?? ''}';
    final pair = [o['targetSymbol'] ?? o['target'], o['contraSymbol'] ?? o['contra']].whereType<Object>().join(' / ');
    final open = _open(o);
    return Semantics(
      identifier: 'flash:order:$id',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    type.isEmpty ? 'Order' : type[0].toUpperCase() + type.substring(1),
                    style: const TextStyle(color: Glass.ink, fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [if (pair.isNotEmpty) pair, if (status.isNotEmpty) status].join(' · '),
                    style: const TextStyle(color: Glass.inkSoft, fontSize: 13),
                  ),
                ],
              ),
            ),
            if (open)
              _cancelling.contains(id)
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Glass.inkSoft),
                    )
                  : TextButton(
                      onPressed: () => _cancel(id),
                      child: const Text('Cancel',
                          style: TextStyle(color: Glass.danger, fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
          ],
        ),
      ),
    );
  }
}
