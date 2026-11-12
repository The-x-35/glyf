import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/glyf_api.dart';
import '../core/theme.dart';
import 'evm_chains.dart';
import 'evm_signer.dart';
import 'flash_orders.dart';

/// Profile → Wallet → Ethereum: the balances, on each chain, of the
/// MetaMask wallet that signs the keyboard's swaps (Uniswap) and orders
/// (Flash), and its Flash orders. MetaMask is connected on the Wallet
/// screen; Glyf only reads here.
class EvmWalletScreen extends StatefulWidget {
  const EvmWalletScreen({super.key});

  @override
  State<EvmWalletScreen> createState() => _EvmWalletScreenState();
}

class _EvmWalletScreenState extends State<EvmWalletScreen> {
  EvmChain _chain = EvmChain.base;
  List<Map<String, dynamic>>? _balances;
  String? _error;

  static const _chains = [
    EvmChain.base, EvmChain.ethereum, EvmChain.arbitrum, EvmChain.optimism, EvmChain.unichain,
  ];

  @override
  void initState() {
    super.initState();
    EvmSigner.load().then((_) => _refresh());
  }

  Future<void> _refresh() async {
    final address = EvmSigner.address.value;
    if (address == null) return;
    setState(() => _balances = null);
    try {
      final res = await GlyfApi.evmGet('/evm/balances?chain=${_chain.name}&address=$address');
      if (!mounted) return;
      setState(() {
        _balances = (res['balances'] as List? ?? const []).map((b) => Map<String, dynamic>.from(b as Map)).toList();
        _error = null;
      });
    } on Exception catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Glass.bg,
      appBar: AppBar(
        backgroundColor: Glass.bg,
        surfaceTintColor: Colors.transparent,
        title: const Text('Ethereum', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: ValueListenableBuilder<String?>(
        valueListenable: EvmSigner.address,
        builder: (context, address, _) => RefreshIndicator(
          color: Glass.ink,
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              if (address == null)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Text(EvmSigner.missing,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Glass.inkSoft, fontSize: 15, fontWeight: FontWeight.w600)),
                )
              else ...[
                _walletCard(address),
                const SizedBox(height: 18),
                FlashOrdersList(address: address),
              ],
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
      ),
    );
  }

  Widget _walletCard(String address) {
    final rows = _balances;
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(EvmSigner.kind.value.label,
                        style: const TextStyle(color: Glass.ink, fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Semantics(
                      identifier: 'evm:address',
                      child: Text(
                        '${address.substring(0, 6)}…${address.substring(address.length - 4)}',
                        style: const TextStyle(
                          color: Glass.inkSoft,
                          fontSize: 13.5,
                          fontFeatures: [FontFeature.disable('calt')],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Copy address',
                icon: const Icon(Icons.copy_rounded, size: 19, color: Glass.inkSoft),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: address));
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _chains.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final c = _chains[i];
                final on = c.id == _chain.id;
                return Semantics(
                  identifier: 'evm:chain:${c.name}',
                  button: true,
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _chain = c);
                      _refresh();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: on ? Glass.pill : Glass.bg,
                        borderRadius: BorderRadius.circular(17),
                      ),
                      child: Text(
                        c.label,
                        style: TextStyle(
                          color: on ? Colors.white : Glass.ink,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          if (rows == null)
            const SizedBox(
              height: 74,
              child: Center(
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Glass.ink)),
              ),
            )
          else
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.3,
              children: [for (final b in _shown(rows)) _balance(b)],
            ),
        ],
      ),
    );
  }

  /// Native and the dollar coin always; anything else only when held.
  List<Map<String, dynamic>> _shown(List<Map<String, dynamic>> rows) {
    final keep = <Map<String, dynamic>>[];
    for (final b in rows) {
      final symbol = (b['symbol'] as String? ?? '').toUpperCase();
      final amount = double.tryParse('${b['amount']}') ?? 0;
      if (symbol == _chain.native || symbol == 'USDC' || amount > 0) {
        keep.add(b);
      }
    }
    return keep.take(6).toList();
  }

  Widget _balance(Map<String, dynamic> b) {
    final amount = double.tryParse('${b['amount']}') ?? 0;
    final shown = amount == 0
        ? '0'
        : amount >= 1000
            ? amount.toStringAsFixed(2)
            : amount >= 1
                ? amount.toStringAsFixed(4)
                : amount.toStringAsFixed(6);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: Glass.bg, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('${b['symbol']}', style: const TextStyle(color: Glass.inkSoft, fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(
            shown,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Glass.ink,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
