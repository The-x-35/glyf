import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoSlidingSegmentedControl;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/bridge.dart';
import '../core/glyf_api.dart';
import '../core/theme.dart';
import '../evm/evm_signer.dart';
import '../evm/evm_wallet.dart';
import '../evm/evm_wallet_screen.dart';
import '../profile/brand_marks.dart' show PhantomMark;
import 'buy_screen.dart';
import 'glyf_keys.dart';
import 'mwa.dart';
import 'send_screen.dart';
import 'solana.dart';
import 'wallet_api.dart';
import 'wallet_flow.dart';
import 'wallet_mode.dart';
import 'wallet_secrets_screen.dart';

/// Profile → Wallet. Two kinds of wallet:
/// - the Glyf wallet (internal): one recovery phrase on this phone, an
///   Ethereum and a Solana address from it, the phrase and both private keys
///   shown only after the phone's own unlock;
/// - outside wallets (external): Phantom for Solana, MetaMask for Ethereum
///   and its L2s, each signing in its own app.
/// Which of them signs is the one switch at the top (WalletModes); below it,
/// the Ethereum and Solana wallets that sign, each with its balances
/// (Arpit, 2026-11-07: "just have a toggle, internal wallet or external
/// wallet ... it should show the balance of both Ethereum and Solana").
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  BigInt? _sol;
  BigInt? _usdc;
  double? _solPrice;

  /// The Ethereum wallet that signs, on Base; ETH's price in dollars.
  ({double eth, double usdc})? _evm;
  double? _ethPrice;
  bool _connecting = false;
  bool _making = false;
  String? _error;

  /// MetaMask being connected, and the link that opens it again.
  bool _mmWaiting = false;
  String? _mmReopen;

  /// The address row just tapped (copied), for its tick.
  String? _copied;
  Timer? _copiedTimer;

  /// A Mobile Wallet Adapter wallet lives on this phone (Seed Vault on a
  /// Seeker): connect and sign here, with no Phantom round trip.
  bool _mwaHere = false;

  @override
  void initState() {
    super.initState();
    WalletFlow.link.addListener(_refresh);
    WalletFlow.load().then((_) => _refresh());
    EvmSigner.load().then((_) {
      if (mounted) setState(() {});
      _refreshEvm();
    });
    Mwa.isAvailable().then((here) {
      if (mounted && here) setState(() => _mwaHere = true);
    });
  }

  @override
  void dispose() {
    WalletFlow.link.removeListener(_refresh);
    _copiedTimer?.cancel();
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

  /// Everything that follows the Glyf wallet: the signers, the keyboard's
  /// addresses, the balances.
  Future<void> _reload() async {
    await EvmSigner.load();
    await WalletFlow.load();
    if (mounted) setState(() {});
    _refresh();
    _refreshEvm();
  }

  Future<void> _make() async {
    setState(() {
      _making = true;
      _error = null;
    });
    try {
      await EvmWallet.ensure();
    } catch (e) {
      _error = '$e';
    }
    await _reload();
    if (mounted) setState(() => _making = false);
  }

  /// An old one-key wallet gets a recovery phrase: a new wallet, with the
  /// old key kept on this phone (Private keys) so its address stays reachable.
  Future<void> _switchToPhrase() async {
    final old = GlyfKeys.evmAddress.value;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Make a new wallet?'),
        content: Text(
            '${old == null ? 'Your wallet' : EvmSigner.short(old)} stays on this phone and its key stays under Private keys. Move what it holds to the new address.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(
            key: const Key('wallet:switch:confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Make new wallet'),
          ),
        ],
      ),
    );
    if (go != true) return;
    setState(() => _making = true);
    try {
      await EvmWallet.switchToPhrase();
    } catch (e) {
      _error = '$e';
    }
    await _reload();
    if (mounted) setState(() => _making = false);
  }

  Future<void> _showPhrase() async {
    if (!await unlockWalletSecret('Show your recovery phrase')) return;
    final phrase = await GlyfKeys.phrase();
    if (phrase == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => RecoveryPhraseScreen(phrase: phrase)));
  }

  Future<void> _showKeys() async {
    if (!await unlockWalletSecret('Show your private keys')) return;
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrivateKeysScreen()));
  }

  void _copyAddress(String address) {
    Clipboard.setData(ClipboardData(text: address));
    setState(() => _copied = address);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(seconds: 2), () => mounted ? setState(() => _copied = null) : null);
  }

  Future<void> _connectPhantom() async {
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

  Future<void> _connectMetaMask() async {
    if (_mmWaiting) return;
    setState(() {
      _mmWaiting = true;
      _error = null;
    });
    try {
      await for (final e in EvmSigner.connect(EvmSignerKind.metamask)) {
        if (e.reopen != null && mounted) setState(() => _mmReopen = e.reopen);
      }
    } on SignFailed catch (e) {
      if (mounted && !e.cancelled) setState(() => _error = '$e');
    } on Exception catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (!mounted) return;
    setState(() {
      _mmWaiting = false;
      _mmReopen = null;
    });
  }

  Future<void> _disconnectMetaMask() async {
    await EvmSigner.disconnect(EvmSignerKind.metamask);
    if (mounted) setState(() {});
  }

  /// The one switch: the Glyf wallet (one recovery phrase, Ethereum and
  /// Solana from it) or Phantom and MetaMask.
  Future<void> _setMode(WalletMode m) async {
    if (WalletModes.mode.value == m) return;
    setState(() {
      _evm = null;
      _sol = _usdc = null;
      _error = null;
    });
    await WalletModes.set(m);
    await EvmSigner.follow();
    await WalletFlow.load();
    if (mounted) setState(() {});
    _refresh();
    _refreshEvm();
  }

  /// The Ethereum wallet that signs, on Base: ETH and USDC, and ETH's price.
  Future<void> _refreshEvm() async {
    final address = EvmSigner.address.value;
    if (address == null) {
      if (mounted) setState(() => _evm = null);
      return;
    }
    try {
      final res = await GlyfApi.evmGet('/evm/balances?chain=base&address=$address');
      final rows = (res['balances'] as List? ?? const []).map((b) => Map<String, dynamic>.from(b as Map));
      double held(String symbol) =>
          double.tryParse('${rows.where((r) => r['symbol'] == symbol).firstOrNull?['amount'] ?? 0}') ?? 0;
      double? price = _ethPrice;
      if (price == null) {
        final q = await GlyfApi.evmPost('/uniswap/quote', {'chain': 'base', 'sell': 'ETH', 'buy': 'USDC', 'amount': '1'});
        price = double.tryParse('${q['amountOut']}');
      }
      if (!mounted) return;
      setState(() {
        _evm = (eth: held('ETH'), usdc: held('USDC'));
        _ethPrice = price;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Couldn’t read the Ethereum balance');
    }
  }

  double? get _total {
    final e = _evm, sol = _sol, usdc = _usdc;
    double sum = 0;
    var any = false;
    if (e != null && _ethPrice != null) {
      sum += e.eth * _ethPrice! + e.usdc;
      any = true;
    }
    if (sol != null && _solPrice != null) {
      sum += sol.toDouble() / 1e9 * _solPrice!;
      any = true;
    }
    if (usdc != null) {
      sum += usdc.toDouble() / 1e6;
      any = true;
    }
    return any ? sum : null;
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
      body: ListenableBuilder(
        listenable: Listenable.merge([
          WalletModes.mode,
          WalletFlow.link,
          WalletFlow.external,
          GlyfKeys.evmAddress,
          GlyfKeys.solanaAddress,
          EvmSigner.address,
        ]),
        builder: (context, _) {
          final internal = WalletModes.mode.value == WalletMode.internal;
          final made = GlyfKeys.evmAddress.value != null;
          return RefreshIndicator(
            onRefresh: () => Future.wait([_refresh(), _refreshEvm()]),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: [
                _modeSwitch(internal),
                const SizedBox(height: 18),
                if (internal && !made)
                  _makeCard()
                else ...[
                  _totalHeader(),
                  const SizedBox(height: 14),
                  _ethereumCard(internal),
                  const SizedBox(height: 14),
                  _solanaCard(internal),
                  if (internal) ...[
                    const SizedBox(height: 14),
                    _secretsCard(),
                  ],
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Glass.danger, fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _modeSwitch(bool internal) => Semantics(
        identifier: 'wallet:mode',
        child: SizedBox(
          width: double.infinity,
          child: CupertinoSlidingSegmentedControl<WalletMode>(
            groupValue: internal ? WalletMode.internal : WalletMode.external,
            backgroundColor: const Color(0x14000000),
            thumbColor: Colors.white,
            padding: const EdgeInsets.all(3),
            onValueChanged: (m) => m == null ? null : _setMode(m),
            children: {
              for (final m in WalletMode.values)
                m: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Text(m == WalletMode.internal ? 'Glyf wallet' : 'Phantom & MetaMask',
                      key: ValueKey('wallet:mode:${m.name}'),
                      style: const TextStyle(color: Glass.ink, fontSize: 14.5, fontWeight: FontWeight.w700)),
                ),
            },
          ),
        ),
      );

  Widget _makeCard() => GlassCard(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            _glyfMark(),
            const SizedBox(width: 12),
            const Text('Glyf wallet', style: TextStyle(color: Glass.ink, fontSize: 17, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 16),
          Semantics(
            identifier: 'wallet:make',
            button: true,
            child: _making
                ? SizedBox(height: 52, child: Center(child: _spinner()))
                : PillButton(label: 'Make my wallet', onPressed: _make),
          ),
        ]),
      );

  Widget _totalHeader() {
    final total = _total;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Balance', style: TextStyle(color: Glass.inkSoft, fontSize: 13.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(
          total == null ? '…' : '\$${_money(total)}',
          key: const ValueKey('wallet:total'),
          style: const TextStyle(
              color: Glass.ink, fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.8,
              fontFeatures: [FontFeature.tabularFigures()]),
        ),
      ]),
    );
  }

  static String _money(double v) {
    final s = v.toStringAsFixed(2);
    final whole = s.split('.')[0], cents = s.split('.')[1];
    final grouped = whole.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    return '$grouped.$cents';
  }

  /// A chain's card: its name and who signs, the address (tap to copy),
  /// or Connect when an outside wallet isn't linked yet.
  Widget _chainHeader({
    required String chain,
    required String signer,
    required Widget mark,
    required String? address,
    required String short,
    Widget? trailing,
  }) {
    return Row(children: [
      mark,
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(chain, style: const TextStyle(color: Glass.ink, fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 1),
          GestureDetector(
            onTap: address == null ? null : () => _copyAddress(address),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(address == null ? signer : '$signer · $short',
                  style: const TextStyle(color: Glass.inkSoft, fontSize: 13.5, fontFeatures: [FontFeature.disable('calt')])),
              if (address != null) ...[
                const SizedBox(width: 5),
                Icon(_copied == address ? Icons.check_rounded : Icons.copy_rounded, size: 14, color: Glass.inkSoft),
              ],
            ]),
          ),
        ]),
      ),
      ?trailing,
    ]);
  }

  Widget _connectButton(String id, String label, bool busy, VoidCallback onTap) => busy
      ? Padding(padding: const EdgeInsets.only(right: 8), child: _spinner())
      : Semantics(
          identifier: id,
          button: true,
          child: TextButton(
            onPressed: onTap,
            child: Text(label, style: const TextStyle(color: Glass.ink, fontSize: 14.5, fontWeight: FontWeight.w700)),
          ),
        );

  Widget _ethereumCard(bool internal) {
    final address = EvmSigner.address.value;
    final mm = EvmSigner.connected(EvmSignerKind.metamask);
    final linked = internal || mm != null;
    final e = _evm;
    String usd(double amount, double? price) => price == null ? '' : '\$${_money(amount * price)}';
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
          identifier: 'wallet:ethereum',
          child: _chainHeader(
            chain: 'Ethereum',
            signer: internal ? 'Glyf wallet' : 'MetaMask',
            mark: internal ? _glyfMark() : _plainMark(Icons.account_balance_wallet_rounded),
            address: linked ? address : null,
            short: address == null ? '' : EvmSigner.short(address),
            trailing: internal
                ? null
                : mm == null
                    ? _connectButton('wallet:metamask:connect', 'Connect', _mmWaiting, _connectMetaMask)
                    : _connectButton('wallet:metamask:disconnect', 'Disconnect', false, _disconnectMetaMask),
          ),
        ),
        if (_mmReopen != null && !internal)
          Row(children: [
            TextButton(
              onPressed: () => GlyfBridge.openMetaMask(_mmReopen!),
              child: const Text('Open MetaMask', style: TextStyle(color: Glass.ink, fontSize: 15, fontWeight: FontWeight.w700)),
            ),
            const Spacer(),
            TextButton(
              onPressed: EvmSigner.stopWaiting,
              child: const Text('Stop', style: TextStyle(color: Glass.inkSoft, fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ]),
        if (linked && address != null) ...[
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _balance('ETH · Base', e == null ? '…' : _amount(e.eth, 5), e == null ? '' : usd(e.eth, _ethPrice))),
            const SizedBox(width: 10),
            Expanded(child: _balance('USDC · Base', e == null ? '…' : _amount(e.usdc, 2), e == null ? '' : '\$${_money(e.usdc)}')),
          ]),
          const SizedBox(height: 6),
          _row('Other chains and orders', null,
              id: 'wallet:ethereum:more',
              chevron: true,
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const EvmWalletScreen()))
                  .then((_) => _refreshEvm())),
        ],
      ]),
    );
  }

  static String _amount(double v, int digits) {
    if (v == 0) return '0';
    final s = v.toStringAsFixed(digits);
    return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
  }

  Widget _solanaCard(bool internal) {
    final link = WalletFlow.link.value;
    final phantom = WalletFlow.external.value;
    String usd(BigInt? units, int decimals, double? price) {
      if (units == null || price == null) return '';
      return '\$${_money(units.toDouble() / BigInt.from(10).pow(decimals).toDouble() * price)}';
    }

    final signer = internal ? 'Glyf wallet' : (_mwaHere ? 'Your wallet' : 'Phantom');
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
          identifier: 'wallet:solana',
          child: _chainHeader(
            chain: 'Solana',
            signer: signer,
            mark: internal ? _glyfMark() : (_mwaHere ? _plainMark(Icons.account_balance_wallet_rounded) : const PhantomMark(size: 34)),
            address: link?.address,
            short: link == null ? '' : Sol.short(link.address),
            trailing: internal
                ? null
                : phantom == null
                    ? _connectButton('wallet:phantom:connect', 'Connect', _connecting, _connectPhantom)
                    : _connectButton('wallet:phantom:disconnect', 'Disconnect', false, () async {
                        await WalletFlow.disconnect();
                        if (mounted) setState(() {});
                      }),
          ),
        ),
        if (link != null) ...[
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _balance('SOL', _sol == null ? '…' : Sol.format(_sol!, 9), usd(_sol, 9, _solPrice))),
            const SizedBox(width: 10),
            Expanded(child: _balance('USDC', _usdc == null ? '…' : Sol.format(_usdc!, 6, maxDecimals: 2), usd(_usdc, 6, 1))),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: PillButton(
                label: 'Send',
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const SendScreen()))
                    .then((_) => _refresh()),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: PillButton(
                label: 'Buy',
                primary: false,
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const BuyScreen()))
                    .then((_) => _refresh()),
              ),
            ),
          ]),
        ],
      ]),
    );
  }

  /// The Glyf wallet's secrets, each behind the phone's own unlock.
  Widget _secretsCard() {
    final legacy = GlyfKeys.isLegacyOnly;
    final rows = <Widget>[
      if (legacy)
        _row('Recovery phrase', _making ? null : 'Make one',
            id: 'wallet:switch', chevron: true, busy: _making, onTap: _making ? null : _switchToPhrase)
      else
        _row('Recovery phrase', null, id: 'wallet:phrase:show', chevron: true, onTap: _showPhrase),
      _row('Private keys', null, id: 'wallet:keys:show', chevron: true, onTap: _showKeys),
    ];
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const Divider(height: 1, indent: 18, color: Glass.hairline),
          rows[i],
        ],
      ]),
    );
  }

  Widget _glyfMark() => Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Glass.pill, borderRadius: BorderRadius.circular(9)),
        child: const Text('g',
            style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800, height: 1.05)),
      );

  Widget _spinner() => const SizedBox(
      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Glass.ink));

  Widget _row(String title, String? value,
      {required String id, bool chevron = false, bool copied = false, bool busy = false, VoidCallback? onTap}) {
    return Semantics(
      identifier: id,
      button: onTap != null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 13, 14, 13),
          child: Row(children: [
            Expanded(child: Text(title, style: const TextStyle(color: Glass.ink, fontSize: 15.5, fontWeight: FontWeight.w600))),
            if (value != null)
              Text(value,
                  style: const TextStyle(color: Glass.inkSoft, fontSize: 14, fontFeatures: [FontFeature.disable('calt')])),
            if (busy) _spinner(),
            if (copied) ...[
              const SizedBox(width: 6),
              const Icon(Icons.check_rounded, size: 17, color: Glass.ink),
            ] else if (!chevron && value != null) ...[
              const SizedBox(width: 6),
              const Icon(Icons.copy_rounded, size: 15, color: Glass.inkSoft),
            ],
            if (chevron) const Icon(Icons.chevron_right_rounded, color: Glass.inkSoft),
          ]),
        ),
      ),
    );
  }

  Widget _plainMark(IconData icon) => Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Glass.bg, borderRadius: BorderRadius.circular(9)),
        child: Icon(icon, size: 19, color: Glass.ink),
      );

  Widget _balance(String symbol, String amount, String usd) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Glass.bg, borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(symbol, style: const TextStyle(color: Glass.inkSoft, fontSize: 12.5, fontWeight: FontWeight.w600)),
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
