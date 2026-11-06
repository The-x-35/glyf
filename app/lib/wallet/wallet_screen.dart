import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/bridge.dart';
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
import 'wallet_secrets_screen.dart';

/// Profile → Wallet. Two kinds of wallet:
/// - the Glyf wallet (internal): one recovery phrase on this phone, an
///   Ethereum and a Solana address from it, the phrase and both private keys
///   shown only after the phone's own unlock;
/// - outside wallets (external): Phantom for Solana, MetaMask for Ethereum
///   and its L2s, each signing in its own app.
/// Which of them signs is one switch, Profile › Keyboard › Sign with
/// (WalletModes); below are the Solana wallet that signs (balances, Send,
/// Buy) and the Ethereum screen (balances, orders).
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
    EvmSigner.load().then((_) => mounted ? setState(() {}) : null);
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
          WalletFlow.link,
          WalletFlow.external,
          GlyfKeys.evmAddress,
          GlyfKeys.solanaAddress,
          EvmSigner.address,
        ]),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            _glyfCard(),
            const SizedBox(height: 18),
            _label('Outside wallets'),
            _outsideCard(),
            if (WalletFlow.link.value != null) ...[
              const SizedBox(height: 18),
              _solanaCard(WalletFlow.link.value!),
            ],
            const SizedBox(height: 18),
            _ethereumRow(),
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

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(text, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Glass.inkSoft)),
      );

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

  /// The Glyf wallet: made here, its two addresses, its secrets.
  Widget _glyfCard() {
    final evm = GlyfKeys.evmAddress.value;
    final sol = GlyfKeys.solanaAddress.value;
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
      child: Row(children: [
        _glyfMark(),
        const SizedBox(width: 12),
        const Text('Glyf wallet', style: TextStyle(color: Glass.ink, fontSize: 17, fontWeight: FontWeight.w800)),
      ]),
    );
    if (evm == null) {
      return GlassCard(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Semantics(
                identifier: 'wallet:make',
                button: true,
                child: _making
                    ? SizedBox(height: 52, child: Center(child: _spinner()))
                    : PillButton(label: 'Make my wallet', onPressed: _make),
              ),
            ),
          ],
        ),
      );
    }
    final legacy = GlyfKeys.isLegacyOnly;
    final rows = <Widget>[
      _row('Ethereum', EvmSigner.short(evm), id: 'wallet:glyf:evm', copied: _copied == evm, onTap: () => _copyAddress(evm)),
      if (sol != null)
        _row('Solana', Sol.short(sol), id: 'wallet:glyf:solana', copied: _copied == sol, onTap: () => _copyAddress(sol)),
      if (legacy)
        _row('Recovery phrase', _making ? null : 'Make one',
            id: 'wallet:switch', chevron: true, busy: _making, onTap: _making ? null : _switchToPhrase)
      else
        _row('Recovery phrase', null, id: 'wallet:phrase:show', chevron: true, onTap: _showPhrase),
      _row('Private keys', null, id: 'wallet:keys:show', chevron: true, onTap: _showKeys),
    ];
    return GlassCard(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 18, color: Glass.hairline),
            rows[i],
          ],
        ],
      ),
    );
  }

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

  /// Phantom (Solana) and MetaMask (Ethereum and its L2s): connect,
  /// disconnect, and the address each one signs as.
  Widget _outsideCard() {
    final phantom = WalletFlow.external.value;
    final mm = EvmSigner.connected(EvmSignerKind.metamask);
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _outsideRow(
            id: 'wallet:phantom',
            mark: _mwaHere ? _plainMark(Icons.account_balance_wallet_rounded) : const PhantomMark(size: 34),
            name: _mwaHere ? 'Your wallet' : 'Phantom',
            chain: 'Solana',
            address: phantom == null ? null : Sol.short(phantom.address),
            busy: _connecting,
            onConnect: _connectPhantom,
            onDisconnect: () async {
              await WalletFlow.disconnect();
              if (mounted) setState(() {});
            },
          ),
          const Divider(height: 1, indent: 18, color: Glass.hairline),
          _outsideRow(
            id: 'wallet:metamask',
            mark: _plainMark(Icons.account_balance_wallet_rounded),
            name: 'MetaMask',
            chain: 'Ethereum and L2s',
            address: mm == null ? null : EvmSigner.short(mm),
            busy: _mmWaiting,
            onConnect: _connectMetaMask,
            onDisconnect: _disconnectMetaMask,
          ),
          if (_mmReopen != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
              child: Row(children: [
                TextButton(
                  onPressed: () => GlyfBridge.openMetaMask(_mmReopen!),
                  child: const Text('Open MetaMask',
                      style: TextStyle(color: Glass.ink, fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                const Spacer(),
                TextButton(
                  onPressed: EvmSigner.stopWaiting,
                  child: const Text('Stop', style: TextStyle(color: Glass.inkSoft, fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
        ],
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

  Widget _outsideRow({
    required String id,
    required Widget mark,
    required String name,
    required String chain,
    required String? address,
    required bool busy,
    required VoidCallback onConnect,
    required VoidCallback onDisconnect,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
      child: Row(children: [
        mark,
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(color: Glass.ink, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 1),
            Text(address ?? chain,
                style: const TextStyle(color: Glass.inkSoft, fontSize: 13.5, fontFeatures: [FontFeature.disable('calt')])),
          ]),
        ),
        if (busy)
          Padding(padding: const EdgeInsets.only(right: 12), child: _spinner())
        else
          Semantics(
            identifier: address == null ? '$id:connect' : '$id:disconnect',
            button: true,
            child: TextButton(
              onPressed: address == null ? onConnect : onDisconnect,
              child: Text(address == null ? 'Connect' : 'Disconnect',
                  style: TextStyle(
                      color: address == null ? Glass.ink : Glass.inkSoft, fontSize: 14.5, fontWeight: FontWeight.w700)),
            ),
          ),
      ]),
    );
  }

  /// The Solana wallet that signs: its balances, Send and Buy.
  Widget _solanaCard(WalletLink link) {
    String usd(BigInt? units, int decimals, double? price) {
      if (units == null || price == null) return '';
      final value = units.toDouble() / BigInt.from(10).pow(decimals).toDouble() * price;
      return '\$${value.toStringAsFixed(2)}';
    }

    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Expanded(
              child: Text('Solana', style: TextStyle(color: Glass.ink, fontSize: 17, fontWeight: FontWeight.w800)),
            ),
            Semantics(
              identifier: 'wallet:solana:signer',
              child: Text(
                '${link.internal ? 'Glyf wallet' : link.viaMwa ? 'Your wallet' : 'Phantom'} · ${Sol.short(link.address)}',
                style: const TextStyle(color: Glass.inkSoft, fontSize: 13.5, fontFeatures: [FontFeature.disable('calt')]),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _balance('SOL', _sol == null ? '…' : Sol.format(_sol!, 9), usd(_sol, 9, _solPrice))),
              const SizedBox(width: 10),
              Expanded(
                child: _balance('USDC', _usdc == null ? '…' : Sol.format(_usdc!, 6, maxDecimals: 2), usd(_usdc, 6, 1)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
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
            ],
          ),
        ],
      ),
    );
  }

  /// Ethereum and its L2s, Whitechain: balances and Flash orders.
  Widget _ethereumRow() => Semantics(
        identifier: 'wallet:ethereum',
        button: true,
        child: GestureDetector(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EvmWalletScreen())),
          child: GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Ethereum', style: TextStyle(color: Glass.ink, fontSize: 17, fontWeight: FontWeight.w800)),
                      SizedBox(height: 2),
                      Text('Base, Arbitrum, Optimism, Whitechain',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Glass.inkSoft, fontSize: 13.5)),
                    ],
                  ),
                ),
                Builder(builder: (_) {
                  final a = EvmSigner.address.value;
                  return Text(
                    a == null ? '' : EvmSigner.short(a),
                    style: const TextStyle(color: Glass.inkSoft, fontSize: 13.5, fontFeatures: [FontFeature.disable('calt')]),
                  );
                }),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right_rounded, color: Glass.inkSoft),
              ],
            ),
          ),
        ),
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
