import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/bridge.dart';
import '../core/glyf_api.dart';
import '../core/text_sheet.dart';
import '../core/theme.dart';
import '../evm/evm_signer.dart';
import '../evm/evm_wallet_screen.dart';
import '../near/hot_wallet.dart';
import '../near/near_pot.dart';
import '../profile/brand_marks.dart' show BrandMark, PhantomMark;
import 'buy_screen.dart';
import 'mwa.dart';
import 'send_screen.dart';
import 'solana.dart';
import 'wallet_api.dart';
import 'wallet_flow.dart';

/// Profile → Wallet: the person's own wallets, each signing in its own app.
/// MetaMask for Ethereum and its L2s, Phantom for Solana (or, on a phone
/// with Mobile Wallet Adapter, the wallet that lives there), HOT Wallet for
/// NEAR, each with its balances. All three stay connected side by side. Glyf holds no key: it builds each request and the wallet signs
/// it (Arpit, 2026-11-12: "the wallet would be external wallet only. Remove
/// the internal wallet thing").
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
  String? _error;

  /// MetaMask being connected, and the link that opens it again.
  bool _mmWaiting = false;
  String? _mmReopen;

  /// HOT Wallet being connected, and the link that opens it again.
  bool _hotWaiting = false;
  String? _hotReopen;

  /// The NEAR account's NEAR, in yocto.
  BigInt? _near;

  /// The group pot (shared settings `nearPot`), a Sputnik DAO on NEAR.
  String _pot = '';

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
    HotWallet.load().then((_) {
      if (mounted) setState(() {});
      _refreshNear();
    });
    _loadPot();
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

  Future<void> _connectHot() async {
    if (_hotWaiting) return;
    setState(() {
      _hotWaiting = true;
      _error = null;
    });
    try {
      await HotWallet.connect(opened: (link) {
        if (mounted) setState(() => _hotReopen = link);
      });
      _refreshNear();
    } on HotError catch (e) {
      if (mounted && !e.stopped) setState(() => _error = e.refused ? 'Cancelled in HOT Wallet' : e.message);
    }
    if (!mounted) return;
    setState(() {
      _hotWaiting = false;
      _hotReopen = null;
    });
  }

  Future<void> _disconnectHot() async {
    await HotWallet.disconnect();
    if (mounted) setState(() => _near = null);
  }

  Future<void> _loadPot() async {
    final pot = (await GlyfBridge.sharedSettings())[NearPot.key];
    if (mounted) setState(() => _pot = pot is String ? pot.trim() : '');
  }

  /// The group pot: a Sputnik DAO, saved where the keyboard reads it for a
  /// pot chip that names none. Saved empty, it is forgotten.
  Future<void> _editPot() async {
    final text = await showTextSheet(
      context,
      title: 'Group pot',
      action: 'Save',
      initial: _pot,
      maxLength: 64,
      autocorrect: false,
      check: (t) => NearPot.normalize(t) == null ? NearPot.invalid : null,
    );
    final pot = text == null ? null : NearPot.normalize(text);
    if (pot == null) return;
    await GlyfBridge.updateSharedSettings((s) {
      if (pot.isEmpty) {
        s.remove(NearPot.key);
      } else {
        s[NearPot.key] = pot;
      }
      return s;
    });
    await _loadPot();
  }

  Future<void> _refreshNear() async {
    final a = HotWallet.account.value;
    final near = a == null ? null : await HotWallet.balance(a.accountId);
    if (mounted) setState(() => _near = near);
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
        listenable: Listenable.merge([WalletFlow.link, EvmSigner.address, HotWallet.account]),
        builder: (context, _) {
          return RefreshIndicator(
            onRefresh: () => Future.wait([_refresh(), _refreshEvm(), _refreshNear()]),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: [
                _totalHeader(),
                const SizedBox(height: 14),
                _ethereumCard(),
                const SizedBox(height: 14),
                _solanaCard(),
                const SizedBox(height: 14),
                _nearCard(),
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
            child: WalletSignerLine(
              text: address == null ? signer : '$signer · $short',
              copyIcon: address == null ? null : (_copied == address ? Icons.check_rounded : Icons.copy_rounded),
            ),
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

  Widget _ethereumCard() {
    final address = EvmSigner.address.value;
    final mm = EvmSigner.connected(EvmSignerKind.metamask);
    final linked = mm != null;
    final e = _evm;
    String usd(double amount, double? price) => price == null ? '' : '\$${_money(amount * price)}';
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
          identifier: 'wallet:ethereum',
          child: _chainHeader(
            chain: 'Ethereum',
            signer: 'MetaMask',
            mark: _chainMark('ethereum', const BrandMark('metamask', size: 18)),
            address: linked ? address : null,
            short: address == null ? '' : EvmSigner.short(address),
            trailing: mm == null
                ? _connectButton('wallet:metamask:connect', 'Connect', _mmWaiting, _connectMetaMask)
                : _connectButton('wallet:metamask:disconnect', 'Disconnect', false, _disconnectMetaMask),
          ),
        ),
        if (_mmReopen != null)
          Row(children: [
            TextButton(
              onPressed: () => GlyfBridge.openMetaMask(_mmReopen!),
              style: _leadingButton,
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

  Widget _solanaCard() {
    final link = WalletFlow.link.value;
    String usd(BigInt? units, int decimals, double? price) {
      if (units == null || price == null) return '';
      return '\$${_money(units.toDouble() / BigInt.from(10).pow(decimals).toDouble() * price)}';
    }

    final signer = _mwaHere ? 'Your wallet' : 'Phantom';
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
          identifier: 'wallet:solana',
          child: _chainHeader(
            chain: 'Solana',
            signer: signer,
            mark: _chainMark('solana', _mwaHere ? null : const PhantomMark(size: 18)),
            address: link?.address,
            short: link == null ? '' : Sol.short(link.address),
            trailing: link == null
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

  Widget _nearCard() {
    final a = HotWallet.account.value;
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
          identifier: 'wallet:near',
          child: _chainHeader(
            chain: 'NEAR',
            signer: HotWallet.name,
            mark: _chainMark('near', null),
            address: a?.accountId,
            short: a == null ? '' : _shortNear(a.accountId),
            trailing: a == null
                ? _connectButton('wallet:hot:connect', 'Connect', _hotWaiting, _connectHot)
                : _connectButton('wallet:hot:disconnect', 'Disconnect', false, _disconnectHot),
          ),
        ),
        if (_hotReopen != null)
          Row(children: [
            TextButton(
              onPressed: () => GlyfBridge.openURL(_hotReopen!),
              style: _leadingButton,
              child: const Text('Open HOT Wallet', style: TextStyle(color: Glass.ink, fontSize: 15, fontWeight: FontWeight.w700)),
            ),
            const Spacer(),
            TextButton(
              onPressed: HotWallet.stopWaiting,
              child: const Text('Stop', style: TextStyle(color: Glass.inkSoft, fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ]),
        if (a != null) ...[
          const SizedBox(height: 14),
          _balance('NEAR', _near == null ? '…' : HotWallet.format(_near!), ''),
        ],
        // The pot is paid into from any wallet, so it shows connected or not.
        const SizedBox(height: 6),
        _row('Group pot', _pot.isEmpty ? 'Add' : _pot, id: 'wallet:near:pot', chevron: true, onTap: _editPot),
      ]),
    );
  }

  /// A named account as it is; an implicit one (64 hex) shortened.
  static String _shortNear(String id) => id.length <= 24 ? id : '${id.substring(0, 6)}…${id.substring(id.length - 4)}';

  /// The chain's own logo, with the wallet that signs on its corner
  /// (MetaMask on Ethereum, Phantom on Solana).
  Widget _chainMark(String chain, Widget? wallet) => SizedBox(
        width: 40,
        height: 40,
        child: Stack(clipBehavior: Clip.none, children: [
          BrandMark(chain, size: 38),
          if (wallet != null)
            Positioned(
              right: -3,
              bottom: -3,
              child: Container(
                padding: const EdgeInsets.all(1.5),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(7)),
                child: wallet,
              ),
            ),
        ]),
      );

  /// A text button that starts where the card's words start (the chain's
  /// mark, the rows under it); its padding stays on the right.
  static final _leadingButton = TextButton.styleFrom(padding: const EdgeInsets.fromLTRB(0, 8, 12, 8));

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
          // Rows sit inside a card's own padding: their words line up with
          // the chain's mark above, the chevron with its button.
          padding: const EdgeInsets.fromLTRB(0, 13, 4, 13),
          child: Row(children: [
            Text(title, style: const TextStyle(color: Glass.ink, fontSize: 15.5, fontWeight: FontWeight.w600)),
            const SizedBox(width: 12),
            // A long value (a pot's whole DAO account) shrinks to the room
            // left, whole, rather than running past the card.
            Expanded(
              child: value == null
                  ? const SizedBox.shrink()
                  : Align(
                      alignment: Alignment.centerRight,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(value,
                            maxLines: 1,
                            style: const TextStyle(
                                color: Glass.inkSoft, fontSize: 14, fontFeatures: [FontFeature.disable('calt')])),
                      ),
                    ),
            ),
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

/// The line under a chain's name: who signs, the short address and the copy
/// icon. It takes the room the card leaves beside Disconnect and never draws
/// past it (a long signer name with an address overflowed the Solana card).
class WalletSignerLine extends StatelessWidget {
  const WalletSignerLine({super.key, required this.text, this.copyIcon});

  final String text;
  final IconData? copyIcon;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      // Shrinks to fit rather than fading its last characters: an address
      // that loses its end ("0x7099…7") can't be checked by eye.
      Flexible(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(text,
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(color: Glass.inkSoft, fontSize: 13.5, fontFeatures: [FontFeature.disable('calt')])),
        ),
      ),
      if (copyIcon != null) ...[
        const SizedBox(width: 5),
        Icon(copyIcon, size: 14, color: Glass.inkSoft),
      ],
    ]);
  }
}
