import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../profile/brand_marks.dart' show PhantomMark;
import 'solana.dart';
import 'wallet_api.dart';
import 'wallet_flow.dart';
import 'wallet_screen.dart';

/// The flash between the keyboard and Phantom: the keyboard already took
/// the amount, so this builds the payment and opens Phantom at once.
/// Only trouble keeps it on screen — no wallet connected, or something the
/// payment itself refused.
class PayLaunchScreen extends StatefulWidget {
  const PayLaunchScreen({super.key, required this.query});

  /// The keyboard's words: kind=send&to=…&amount=…&token=USDC(&private=1),
  /// or kind=buy&mint=…&symbol=…&usd=10&payWith=SOL.
  final Map<String, String> query;

  @override
  State<PayLaunchScreen> createState() => _PayLaunchScreenState();
}

class _PayLaunchScreenState extends State<PayLaunchScreen> {
  String? _error;
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _error = null;
      _opened = false;
    });
    final q = widget.query;
    await WalletFlow.load();
    final String? error;
    if (q['kind'] == 'buy') {
      error = await _buy(q);
    } else {
      final token = _asset(q, fallback: (q['token'] ?? 'USDC').toUpperCase() == 'SOL' ? TokenInfo.sol : TokenInfo.usdc);
      error = await WalletFlow.send(
        to: q['to'] ?? '',
        amount: q['amount'] ?? '',
        token: token,
        // Private sends are USDC only (MagicBlock's lane for money owed).
        private: q['private'] == '1' && token.mint == Sol.usdc,
      );
    }
    if (!mounted) return;
    setState(() {
      _error = error;
      _opened = error == null;
    });
  }

  /// The keyboard says what to sell and how much of it; Jupiter takes it
  /// from there.
  Future<String?> _buy(Map<String, String> q) async {
    final amount = q['amount'] ?? '';
    if ((double.tryParse(amount) ?? 0) <= 0) return 'Pick an amount';
    try {
      final token = await Jupiter.token(q['mint'] ?? '');
      if (token == null) return 'Jupiter doesn’t list that token';
      return await WalletFlow.buy(token: token, payWith: _asset(q, prefix: 'sell'), amount: amount);
    } on WalletError catch (e) {
      return e.message;
    }
  }

  /// The asset named in the keyboard's link (mint, symbol, decimals).
  TokenInfo _asset(Map<String, String> q, {String prefix = '', TokenInfo? fallback}) {
    final key = prefix.isEmpty ? '' : prefix;
    final mint = q[key.isEmpty ? 'mint' : '${key}Mint'];
    final symbol = q[key.isEmpty ? 'symbol' : '${key}Symbol'];
    final decimals = int.tryParse(q[key.isEmpty ? 'decimals' : '${key}Decimals'] ?? '');
    if (mint == null || symbol == null || decimals == null) return fallback ?? TokenInfo.sol;
    return TokenInfo(mint: mint, symbol: symbol, name: symbol, decimals: decimals, verified: true);
  }

  bool get _needsConnect => _error == 'Connect Phantom first';

  @override
  Widget build(BuildContext context) {
    final q = widget.query;
    final what = q['kind'] == 'buy'
        ? 'Buying ${q['symbol'] ?? 'a token'} with ${q['sellSymbol'] ?? 'SOL'}'
        : 'Sending ${q['amount'] ?? ''} ${q['symbol'] ?? q['token'] ?? 'USDC'}';
    return Scaffold(
      backgroundColor: Glass.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),
              const Center(child: PhantomMark(size: 64)),
              const SizedBox(height: 20),
              Text(
                _error != null
                    ? 'Didn’t reach Phantom'
                    : _opened
                        ? 'Sign in Phantom'
                        : 'Opening Phantom…',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Glass.ink, fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                _error ?? '$what · back here the moment it’s signed',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _error != null ? Glass.danger : Glass.inkSoft,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
              if (!_opened && _error == null) ...[
                const SizedBox(height: 20),
                const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: Glass.ink),
                  ),
                ),
              ],
              const Spacer(flex: 3),
              if (_needsConnect)
                PillButton(
                  label: 'Connect Phantom',
                  onPressed: () => Navigator.of(context)
                      .pushReplacement(MaterialPageRoute(builder: (_) => const WalletScreen())),
                )
              else if (_error != null)
                PillButton(label: 'Try again', onPressed: _run),
              if (_error != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text(
                    'Close',
                    style: TextStyle(color: Glass.inkSoft, fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
