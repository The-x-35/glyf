import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/bridge.dart';
import '../core/theme.dart';
import 'evm_wallet.dart';
import 'pay_request.dart';

/// Someone's request, opened from its link: who asks, how much, for what,
/// and one button that pays it from the Glyf wallet. Read from Whitechain,
/// never from the link, so an edited link can't change what's paid.
class PayRequestScreen extends StatefulWidget {
  const PayRequestScreen({super.key, required this.contract, required this.id});

  final String contract;
  final BigInt id;

  @override
  State<PayRequestScreen> createState() => _PayRequestScreenState();
}

class _PayRequestScreenState extends State<PayRequestScreen> {
  PayRequest? _request;
  String? _balance;
  String? _error;
  bool _paying = false;
  String? _paidTx;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await EvmWallet.load();
      final r = await PayRequests.load(widget.contract, widget.id);
      final b = await PayRequests.balance();
      if (!mounted) return;
      setState(() {
        _request = r;
        _balance = b;
        _error = null;
      });
    } on Exception catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _pay() async {
    final r = _request;
    if (r == null) return;
    setState(() {
      _paying = true;
      _error = null;
    });
    try {
      final hash = await PayRequests.pay(widget.contract, r);
      HapticFeedback.mediumImpact();
      if (mounted) setState(() => _paidTx = hash);
      await _load();
    } on Exception catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _paying = false);
  }

  static String _short(String a) => '${a.substring(0, 6)}…${a.substring(a.length - 4)}';

  @override
  Widget build(BuildContext context) {
    final r = _request;
    final me = EvmWallet.address.value;
    return Scaffold(
      backgroundColor: Glass.bg,
      appBar: AppBar(
        backgroundColor: Glass.bg,
        surfaceTintColor: Colors.transparent,
        title: const Text('Request', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          if (r == null && _error == null)
            const Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(
                child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.4, color: Glass.ink)),
              ),
            ),
          if (r != null)
            GlassCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    r.payee == me ? 'You asked for' : '${_short(r.payee)} asks for',
                    style: const TextStyle(color: Glass.inkSoft, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Semantics(
                    identifier: 'request:amount',
                    child: Text(
                      '${r.amount} USDT',
                      style: const TextStyle(
                        color: Glass.ink,
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  if (r.memo.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(r.memo, style: const TextStyle(color: Glass.ink, fontSize: 16)),
                  ],
                  const SizedBox(height: 16),
                  _row('Status', switch (r.status) {
                    PayRequestStatus.open => r.expired ? 'Expired' : 'Waiting to be paid',
                    PayRequestStatus.paid => 'Paid',
                    PayRequestStatus.cancelled => 'Cancelled',
                    PayRequestStatus.refunded => 'Refunded',
                    PayRequestStatus.none => 'Not found',
                  }),
                  _row('Network', 'Whitechain'),
                  if (r.paidBy != null) _row('Paid by', _short(r.paidBy!)),
                  if (r.status == PayRequestStatus.open && r.payee != me && _balance != null)
                    _row('Your USDT', _balance!),
                ],
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Glass.danger, fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 20),
          if (r != null && r.status == PayRequestStatus.open && !r.expired && r.payee != me)
            Semantics(
              identifier: 'request:pay',
              button: true,
              child: _paying
                  ? const SizedBox(
                      height: 52,
                      child: Center(
                        child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Glass.ink)),
                      ),
                    )
                  : PillButton(label: 'Pay ${r.amount} USDT', onPressed: _pay),
            ),
          if (_paidTx != null)
            TextButton(
              onPressed: () => GlyfBridge.openURL(PayRequests.chain.txUrl(_paidTx!)),
              child: const Text(
                'View the receipt on Whitechain',
                style: TextStyle(color: Glass.ink, fontSize: 15, fontWeight: FontWeight.w700, decoration: TextDecoration.underline),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(String key, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Text(key, style: const TextStyle(color: Glass.inkSoft, fontSize: 14.5)),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(
                color: Glass.ink,
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.disable('calt')],
              ),
            ),
          ],
        ),
      );
}
