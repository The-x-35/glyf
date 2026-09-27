import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../profile/brand_marks.dart' show PhantomMark;
import 'buy_screen.dart';
import 'phantom.dart';
import 'send_screen.dart';
import 'solana.dart';
import 'wallet_api.dart';
import 'wallet_flow.dart';

/// Profile → Wallet: connect Phantom, see what's in it, send or buy. Glyf
/// never holds a key; Phantom signs every payment.
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  BigInt? _sol;
  BigInt? _usdc;
  double? _solPrice;
  bool _connecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WalletFlow.link.addListener(_refresh);
    WalletFlow.load().then((_) => _refresh());
  }

  @override
  void dispose() {
    WalletFlow.link.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _refresh() async {
    final link = WalletFlow.link.value;
    if (link == null) {
      if (mounted) setState(() => _sol = _usdc = null);
      return;
    }
    try {
      final results = await Future.wait([
        SolanaRpc.solBalance(link.address),
        SolanaRpc.tokenBalance(link.address, Sol.usdc),
      ]);
      final price = (await Jupiter.token(Sol.wsol))?.usdPrice;
      if (!mounted) return;
      setState(() {
        _sol = results[0];
        _usdc = results[1];
        _solPrice = price;
        _error = null;
      });
    } on WalletError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _error = null;
    });
    final error = await WalletFlow.connect();
    if (!mounted) return;
    setState(() {
      _connecting = false;
      _error = error;
    });
  }

  Future<void> _disconnect() async {
    await WalletFlow.disconnect();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Glass.bg,
      appBar: AppBar(
        backgroundColor: Glass.bg,
        surfaceTintColor: Colors.transparent,
        title: const Text('Wallet', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: ValueListenableBuilder<PhantomLink?>(
        valueListenable: WalletFlow.link,
        builder: (context, link, _) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            if (link == null) _connectCard() else _walletCard(link),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Glass.danger, fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _connectCard() => GlassCard(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            PhantomMark(size: 46),
            SizedBox(width: 14),
            Text(
              'Phantom',
              style: TextStyle(color: Glass.ink, fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const Text(
          'Send and buy from your keyboard. Phantom signs every payment; Glyf never holds your keys.',
          style: TextStyle(color: Glass.inkSoft, fontSize: 14.5, height: 1.4),
        ),
        const SizedBox(height: 18),
        Semantics(
          identifier: 'wallet:connect',
          button: true,
          child: _connecting
              ? const SizedBox(height: 52, child: Center(child: _Spinner()))
              : PillButton(label: 'Connect Phantom', onPressed: _connect),
        ),
      ],
    ),
  );

  Widget _walletCard(PhantomLink link) {
    String usd(BigInt? units, int decimals, double? price) {
      if (units == null || price == null) return '';
      final value = units.toDouble() / BigInt.from(10).pow(decimals).toDouble() * price;
      return '\$${value.toStringAsFixed(2)}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const PhantomMark(size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Phantom',
                          style: TextStyle(color: Glass.ink, fontSize: 17, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          Sol.short(link.address),
                          style: const TextStyle(
                            color: Glass.inkSoft,
                            fontSize: 13.5,
                            fontFeatures: [FontFeature.disable('calt')],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy address',
                    icon: const Icon(Icons.copy_rounded, size: 19, color: Glass.inkSoft),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: link.address));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Address copied')));
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _balance('SOL', _sol == null ? '…' : Sol.format(_sol!, 9), usd(_sol, 9, _solPrice))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _balance(
                      'USDC',
                      _usdc == null ? '…' : Sol.format(_usdc!, 6, maxDecimals: 2),
                      usd(_usdc, 6, 1),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: PillButton(
                      label: 'Send',
                      onPressed: () => Navigator.of(
                        context,
                      ).push(MaterialPageRoute(builder: (_) => const SendScreen())).then((_) => _refresh()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: PillButton(
                      label: 'Buy',
                      primary: false,
                      onPressed: () => Navigator.of(
                        context,
                      ).push(MaterialPageRoute(builder: (_) => const BuyScreen())).then((_) => _refresh()),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: _disconnect,
            child: const Text(
              'Disconnect',
              style: TextStyle(color: Glass.danger, fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  Widget _balance(String symbol, String amount, String usd) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: Glass.bg, borderRadius: BorderRadius.circular(14)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          symbol,
          style: const TextStyle(color: Glass.inkSoft, fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          amount,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Glass.ink,
            fontSize: 19,
            fontWeight: FontWeight.w700,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        if (usd.isNotEmpty) Text(usd, style: const TextStyle(color: Glass.inkSoft, fontSize: 12.5)),
      ],
    ),
  );
}

class _Spinner extends StatelessWidget {
  const _Spinner();
  @override
  Widget build(BuildContext context) =>
      const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Glass.ink));
}
