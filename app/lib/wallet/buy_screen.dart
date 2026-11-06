import 'dart:async';

import 'package:flutter/material.dart';

import '../core/flavor.dart';
import '../core/theme.dart';
import '../profile/brand_marks.dart' show PhantomMark;
import 'solana.dart';
import 'wallet_api.dart';
import 'pay_status_screen.dart';
import 'wallet_flow.dart';

/// Buy a token through Jupiter, paid in SOL or USDC and signed in Phantom.
/// Opened with a contract address or a ticker the keyboard saw, or empty to
/// search.
class BuyScreen extends StatefulWidget {
  const BuyScreen({super.key, this.query});

  /// A contract address, or a ticker ("BONK", "\$sol").
  final String? query;

  @override
  State<BuyScreen> createState() => _BuyScreenState();
}

class _BuyScreenState extends State<BuyScreen> {
  static const _presets = [5, 10, 25, 50];

  late final _search = TextEditingController(text: widget.query ?? '');
  final _custom = TextEditingController();
  TokenInfo? _token;
  bool _looking = false;
  String? _lookError;
  TokenInfo _payWith = TokenInfo.sol;
  double? _solPrice;
  int? _preset = 10;
  JupiterOrder? _quote;
  bool _quoting = false;
  bool _busy = false;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _custom.addListener(() {
      if (_custom.text.isNotEmpty && _preset != null) setState(() => _preset = null);
      _requote();
    });
    WalletFlow.load();
    Jupiter.token(Sol.wsol)
        .then((t) {
          if (mounted) setState(() => _solPrice = t?.usdPrice);
          _requote();
        })
        .catchError((_) {});
    // After the first frame: looking up touches focus, which isn't there yet.
    if ((widget.query ?? '').isNotEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _look());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _custom.dispose();
    super.dispose();
  }

  Future<void> _look() async {
    final q = _search.text.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _looking = true;
      _lookError = null;
      _token = null;
      _quote = null;
    });
    try {
      final found = await Jupiter.token(q);
      if (!mounted) return;
      // No stock buys in the dApp Store build: say so, show no Buy.
      final token = found != null && found.stock && !Flavor.stockBuys ? null : found;
      setState(() {
        _looking = false;
        _token = token;
        _lookError = token != null
            ? null
            : found != null
                ? WalletFlow.noStockBuys
                : 'Jupiter doesn’t list that token';
        // SOL is bought with USDC; everything else defaults to SOL.
        if (token?.mint == Sol.wsol) _payWith = TokenInfo.usdc;
        if (token?.mint == Sol.usdc) _payWith = TokenInfo.sol;
      });
      _requote();
    } catch (e) {
      // Anything, a gateway's error page included: say so, never spin.
      if (mounted) {
        setState(() {
          _looking = false;
          _lookError = e is WalletError ? e.message : 'Couldn’t reach Jupiter. Try again';
        });
      }
    }
  }

  /// The amount in dollars. A comma keypad's "12,50" is twelve and a half.
  double? get _usd {
    if (_preset != null) return _preset!.toDouble();
    final text = Sol.plainAmount(_custom.text.replaceAll('\$', ''));
    return text == null ? null : double.tryParse(text);
  }

  /// The dollars as the token paid with, in whole tokens.
  String? get _payAmount {
    final usd = _usd;
    if (usd == null || usd <= 0) return null;
    if (_payWith.mint == Sol.usdc) return usd.toStringAsFixed(2);
    final price = _solPrice;
    if (price == null || price <= 0) return null;
    return (usd / price).toStringAsFixed(6);
  }

  void _requote() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final token = _token, amount = _payAmount;
      final units = amount == null ? null : Sol.units(amount, _payWith.decimals);
      if (token == null || units == null) {
        if (mounted) setState(() => _quote = null);
        return;
      }
      setState(() => _quoting = true);
      try {
        final quote = await Jupiter.order(inputMint: _payWith.mint, outputMint: token.mint, amount: units);
        if (mounted) {
          setState(() {
            _quote = quote;
            _quoting = false;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _quote = null;
            _quoting = false;
          });
        }
      }
    });
  }

  Future<void> _buy() async {
    final token = _token, amount = _payAmount;
    if (token == null) return;
    if (amount == null) return setState(() => _error = 'Pick an amount');
    setState(() {
      _busy = true;
      _error = null;
    });
    final start = await WalletFlow.buy(token: token, payWith: _payWith, amount: amount);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = start.error;
    });
    final progress = start.progress;
    if (progress != null) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => PayStatusScreen(progress: progress)),
      );
    }
  }

  Future<void> _connect() async {
    setState(() => _busy = true);
    final error = await WalletFlow.connect();
    if (mounted) {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final token = _token;
    return Scaffold(
      backgroundColor: Glass.bg,
      appBar: AppBar(
        backgroundColor: Glass.bg,
        surfaceTintColor: Colors.transparent,
        title: const Text('Buy', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: ValueListenableBuilder<WalletLink?>(
        valueListenable: WalletFlow.link,
        builder: (context, link, _) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            if (link == null) ...[
              GlassCard(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const PhantomMark(size: 38),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Connect Phantom to buy',
                        style: TextStyle(color: Glass.ink, fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ),
                    TextButton(
                      onPressed: _busy ? null : _connect,
                      child: const Text(
                        'Connect',
                        style: TextStyle(color: Glass.ink, fontSize: 15, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (token == null) _searchCard() else _tokenCard(token),
            // A pasted contract address can be anything, copies of real
            // tokens included: say so before money goes in.
            if (token != null && !token.verified) ...[
              const SizedBox(height: 10),
              const Text(
                'Jupiter hasn’t verified this token. Make sure the address is the one you meant.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Glass.warning, fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.35),
              ),
            ],
            if (_lookError != null) ...[
              const SizedBox(height: 10),
              Text(
                _lookError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Glass.danger, fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
            if (token != null) ...[
              const SizedBox(height: 18),
              _label('Amount'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in _presets)
                    _chip('\$$p', _preset == p, () {
                      _custom.clear();
                      setState(() => _preset = p);
                      _requote();
                    }),
                  SizedBox(
                    width: 92,
                    child: TextField(
                      controller: _custom,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(color: Glass.ink, fontSize: 15, fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        hintText: 'Other',
                        prefixText: '\$',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Glass.hairline),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Glass.hairline),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _label('Pay with'),
              Row(
                children: [
                  if (token.mint != Sol.wsol)
                    _chip('SOL', _payWith.mint == Sol.wsol, () {
                      setState(() => _payWith = TokenInfo.sol);
                      _requote();
                    }),
                  if (token.mint != Sol.wsol && token.mint != Sol.usdc) const SizedBox(width: 8),
                  if (token.mint != Sol.usdc)
                    _chip('USDC', _payWith.mint == Sol.usdc, () {
                      setState(() => _payWith = TokenInfo.usdc);
                      _requote();
                    }),
                ],
              ),
              const SizedBox(height: 18),
              _quoteLine(token),
              const SizedBox(height: 20),
              Semantics(
                identifier: 'buy:go',
                button: true,
                child: _busy
                    ? const SizedBox(
                        height: 52,
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: Glass.ink),
                          ),
                        ),
                      )
                    : PillButton(
                        label: link?.internal ?? false ? 'Buy' : 'Buy with Phantom',
                        onPressed: link == null || _payAmount == null ? null : _buy,
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
            ],
          ],
        ),
      ),
    );
  }

  Widget _searchCard() => GlassCard(
    padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: _search,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _look(),
            style: const TextStyle(color: Glass.ink, fontSize: 15, fontFeatures: [FontFeature.disable('calt')]),
            decoration: const InputDecoration(border: InputBorder.none, hintText: 'Ticker or contract address'),
          ),
        ),
        _looking
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Glass.ink),
                ),
              )
            : IconButton(
                icon: const Icon(Icons.arrow_forward_rounded, color: Glass.ink),
                onPressed: _look,
              ),
      ],
    ),
  );

  Widget _tokenCard(TokenInfo token) => GlassCard(
    padding: const EdgeInsets.all(16),
    child: Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: token.icon == null
              ? Container(width: 44, height: 44, color: Glass.bg)
              : Image.network(
                  token.icon!,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(width: 44, height: 44, color: Glass.bg),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      token.symbol,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Glass.ink, fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (token.verified) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.verified_rounded, size: 16, color: Glass.ink),
                  ],
                ],
              ),
              Text(
                token.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Glass.inkSoft, fontSize: 13.5),
              ),
            ],
          ),
        ),
        if (token.usdPrice != null)
          Text(
            _price(token.usdPrice!),
            style: const TextStyle(
              color: Glass.ink,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        if (widget.query == null)
          IconButton(
            tooltip: 'Another token',
            icon: const Icon(Icons.close_rounded, size: 18, color: Glass.inkSoft),
            onPressed: () => setState(() {
              _token = null;
              _quote = null;
            }),
          ),
      ],
    ),
  );

  Widget _quoteLine(TokenInfo token) {
    final quote = _quote;
    final String text;
    if (_quoting && quote == null) {
      text = 'Getting a price…';
    } else if (quote == null) {
      text = _payAmount == null ? 'Pick an amount' : 'No price right now';
    } else {
      // Whole tokens once there are thousands of them; decimals only when
      // they are most of the amount.
      final whole = quote.outAmount ~/ BigInt.from(10).pow(token.decimals);
      final places = whole >= BigInt.from(1000) ? 0 : (whole >= BigInt.one ? 2 : 6);
      text = 'You get ≈ ${_group(Sol.format(quote.outAmount, token.decimals, maxDecimals: places))} ${token.symbol}';
    }
    final impact = quote?.priceImpact?.abs();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Glass.ink, fontSize: 16, fontWeight: FontWeight.w700),
        ),
        if (quote?.glyfFeeBps case final fee?)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              SwapFee.label(fee),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Glass.inkSoft, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        if (impact != null && impact >= 3)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Price moves ${impact.toStringAsFixed(1)}% on this trade',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Glass.warning, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );
  }

  static String _price(double usd) {
    if (usd >= 1) return '\$${usd.toStringAsFixed(2)}';
    if (usd >= 0.01) return '\$${usd.toStringAsFixed(4)}';
    return '\$${usd.toStringAsPrecision(3)}';
  }

  /// "333174.81" → "333,174.81".
  static String _group(String number) {
    final parts = number.split('.');
    final whole = parts.first.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    return parts.length > 1 ? '$whole.${parts[1]}' : whole;
  }

  Widget _chip(String label, bool on, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        color: on ? Glass.ink : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: on ? Glass.ink : Glass.hairline),
      ),
      child: Text(
        label,
        style: TextStyle(color: on ? Colors.white : Glass.ink, fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
  );

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Text(
      text,
      style: const TextStyle(color: Glass.inkSoft, fontSize: 13.5, fontWeight: FontWeight.w600),
    ),
  );
}
