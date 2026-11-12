import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/bridge.dart';
import '../core/theme.dart';
import '../near/hot_wallet.dart';
import '../near/near_flow.dart';
import '../near/near_views.dart';
import 'trade_flow.dart';

/// The flash between the keyboard and the chain: the keyboard read the
/// trade and showed its quote, so this asks for it at once in the person's
/// own wallet app (MetaMask on Ethereum chains, Phantom on Solana) and says
/// how it went. Back in the chat, the keyboard says it too. Glyf holds no
/// key: every transaction and signature is made in that wallet. A NEAR
/// Intents trade also shows its live quote, Guard's checks, and for a chain
/// Glyf can't sign on, the deposit to pay from any wallet.
class TradeScreen extends StatefulWidget {
  const TradeScreen({super.key, required this.query, this.run});

  /// TradeIntent.query: kind=swap&sell=ETH&buy=USDC&amount=0.05&chain=base…
  final Map<String, String> query;

  /// The journey, for a test to drive; TradeFlow.run otherwise.
  final Stream<TradeOutcome> Function(Map<String, String>)? run;

  @override
  State<TradeScreen> createState() => _TradeScreenState();
}

class _TradeScreenState extends State<TradeScreen> {
  TradeOutcome _outcome = const TradeOutcome(TradeState.working, 'One moment…');
  StreamSubscription<TradeOutcome>? _sub;
  final _refund = TextEditingController();

  /// A wallet being connected from the screen's button ("hot"…).
  String? _connecting;

  @override
  void initState() {
    super.initState();
    _start(widget.query);
  }

  void _start(Map<String, String> query) {
    _sub?.cancel();
    _sub = (widget.run ?? TradeFlow.run)(query).listen(
      _show,
      onError: (Object e) => _show(TradeOutcome(TradeState.failed, 'Something went wrong', detail: '$e')),
      onDone: () {
        if (_outcome.state == TradeState.working) {
          _show(const TradeOutcome(TradeState.failed, 'Something went wrong'));
        }
      },
    );
  }

  void _show(TradeOutcome outcome) {
    if (!mounted) return;
    if (outcome.state == TradeState.done) HapticFeedback.mediumImpact();
    setState(() => _outcome = outcome);
  }

  @override
  void dispose() {
    // The trade carries on without the screen and tells the keyboard.
    _sub?.cancel();
    _refund.dispose();
    super.dispose();
  }

  /// Paid from a wallet Glyf doesn't know: the same trade again, with the
  /// person's own address on that chain for a refund.
  void _withRefund() {
    final to = _refund.text.trim();
    if (to.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _outcome = const TradeOutcome(TradeState.working, 'One moment…'));
    _start({...widget.query, 'refundTo': to});
  }

  /// The trade's wallet isn't connected: connect it here, then the same
  /// trade again. MetaMask, Phantom and HOT Wallet stay side by side.
  Future<void> _connect(String wallet) async {
    if (_connecting != null) return;
    final name = NearFlow.walletNames[wallet] ?? wallet;
    setState(() {
      _connecting = wallet;
      _outcome = TradeOutcome(TradeState.working, 'Connect $name', detail: 'Approve in $name, then come back here');
    });
    final error = await NearFlow.connect(wallet, opened: (link) {
      if (mounted && _connecting == wallet) {
        setState(() => _outcome = TradeOutcome(TradeState.working, 'Connect $name',
            detail: 'Approve in $name, then come back here', reopen: link));
      }
    });
    if (!mounted) return;
    setState(() => _connecting = null);
    if (error != null) {
      setState(() => _outcome = NearOutcome(TradeState.failed, '$name isn’t connected', detail: error, connect: wallet));
      return;
    }
    setState(() => _outcome = const TradeOutcome(TradeState.working, 'One moment…'));
    _start(widget.query);
  }

  /// Guard stopped it: the same trade again, past the check.
  void _sendAnyway() {
    setState(() => _outcome = const TradeOutcome(TradeState.working, 'One moment…'));
    _start({...widget.query, 'anyway': '1'});
  }

  static String _linkLabel(String url) {
    if (url.contains('near-intents.org')) return 'View on NEAR Intents';
    if (url.contains('nearblocks')) return 'View on NearBlocks';
    if (url.contains('mempool.space')) return 'View on mempool.space';
    if (url.contains('definitive.fi')) return 'View on Definitive';
    if (url.contains('basescan')) return 'View on Basescan';
    if (url.contains('etherscan')) return 'View on Etherscan';
    if (url.contains('arbiscan')) return 'View on Arbiscan';
    if (url.contains('solscan')) return 'View on Solscan';
    return 'View transaction';
  }

  @override
  Widget build(BuildContext context) {
    final o = _outcome;
    final working = o.state == TradeState.working;
    final near = o is NearOutcome && o.quote != null ? o : null;
    return PopScope(
      canPop: !working,
      child: Scaffold(
        backgroundColor: Glass.bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            child: near != null
                ? Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.only(top: 28, bottom: 16),
                          child: Column(
                            children: [
                              ..._head(o),
                              const SizedBox(height: 22),
                              if (near.manual) ...[
                                Semantics(
                                  identifier: 'trade:near:deposit',
                                  child: NearDepositCard(quote: near.quote!),
                                ),
                                const SizedBox(height: 14),
                              ],
                              NearQuoteCard(quote: near.quote!, recipient: near.recipient),
                            ],
                          ),
                        ),
                      ),
                      ..._buttons(o, working, blocked: near.blocked),
                    ],
                  )
                : Column(
                    children: [const Spacer(flex: 2), ..._head(o), const Spacer(flex: 3), ..._buttons(o, working)],
                  ),
          ),
        ),
      ),
    );
  }

  /// The badge, the line, its detail and its links.
  List<Widget> _head(TradeOutcome o) {
    final explorer = o is NearOutcome ? o.explorer : null;
    return [
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        transitionBuilder: (child, a) => ScaleTransition(
          scale: Tween(begin: 0.7, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)),
          child: FadeTransition(opacity: a, child: child),
        ),
        child: KeyedSubtree(key: ValueKey(o.state), child: _badge(o.state)),
      ),
      const SizedBox(height: 22),
      Semantics(
        identifier: 'trade:title',
        child: Text(
          o.title,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Glass.ink, fontSize: 26, fontWeight: FontWeight.w800),
        ),
      ),
      if (o.detail != null) ...[
        const SizedBox(height: 8),
        Semantics(
          identifier: 'trade:detail',
          child: Text(
            o.detail!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Glass.inkSoft,
              fontSize: 16,
              height: 1.35,
              fontFeatures: [FontFeature.disable('calt')],
            ),
          ),
        ),
      ],
      if (o.txUrl != null) ...[const SizedBox(height: 10), _link(o.txUrl!)],
      // Done or refunded: the trade on NEAR Intents' own explorer too.
      if (explorer != null && explorer != o.txUrl && o.state != TradeState.working) _link(explorer),
    ];
  }

  Widget _link(String url) => TextButton(
    onPressed: () => GlyfBridge.openURL(url),
    child: Text(
      _linkLabel(url),
      style: const TextStyle(
        color: Glass.ink,
        fontSize: 15,
        fontWeight: FontWeight.w700,
        decoration: TextDecoration.underline,
      ),
    ),
  );

  List<Widget> _buttons(TradeOutcome o, bool working, {bool blocked = false}) => [
    if (o is NearOutcome && o.askRefund != null) ...[
      Semantics(
        identifier: 'trade:near:refund',
        child: TextField(
          controller: _refund,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _withRefund(),
          style: const TextStyle(color: Glass.ink, fontSize: 16),
          decoration: InputDecoration(
            hintText: 'Your ${o.askRefund} address',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          ),
        ),
      ),
      const SizedBox(height: 12),
      PillButton(label: 'Continue', onPressed: _withRefund),
      TextButton(
        onPressed: () => Navigator.of(context).maybePop(),
        child: const Text('Close', style: TextStyle(color: Glass.inkSoft, fontSize: 15, fontWeight: FontWeight.w600)),
      ),
    ] else if (blocked) ...[
      PillButton(label: 'Don’t send', onPressed: () => Navigator.of(context).maybePop()),
      const SizedBox(height: 6),
      Semantics(
        identifier: 'trade:near:anyway',
        button: true,
        child: TextButton(
          onPressed: _sendAnyway,
          child: const Text(
            'Send anyway',
            style: TextStyle(color: Glass.danger, fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    ] else if (o is NearOutcome && o.connect != null && !working) ...[
      Semantics(
        identifier: 'trade:connect:${o.connect}',
        button: true,
        child: PillButton(
            label: 'Connect ${NearFlow.walletNames[o.connect] ?? 'wallet'}', onPressed: () => _connect(o.connect!)),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).maybePop(),
        child: const Text('Close', style: TextStyle(color: Glass.inkSoft, fontSize: 15, fontWeight: FontWeight.w600)),
      ),
    ] else if (working && o.reopen != null) ...[
      Semantics(
        identifier: 'trade:reopen',
        button: true,
        child: o.reopen!.startsWith(HotRelay.appLink)
            ? PillButton(label: 'Open HOT Wallet', onPressed: () => GlyfBridge.openURL(o.reopen!))
            : PillButton(label: 'Open MetaMask', onPressed: () => GlyfBridge.openMetaMask(o.reopen!)),
      ),
      const SizedBox(height: 6),
      if (_connecting == 'hot') ...[
        PillButton(label: 'Stop', primary: false, onPressed: HotWallet.stopWaiting),
        const SizedBox(height: 6),
      ],
    ] else if (working && _connecting == 'hot') ...[
      PillButton(label: 'Stop', primary: false, onPressed: HotWallet.stopWaiting),
      const SizedBox(height: 6),
    ],
    if (working)
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text(
          'Close',
          style: TextStyle(color: Glass.inkSoft, fontSize: 15, fontWeight: FontWeight.w600),
        ),
      )
    else if (!blocked && !(o is NearOutcome && (o.askRefund != null || o.connect != null)))
      PillButton(label: 'Done', onPressed: () => Navigator.of(context).maybePop()),
  ];

  Widget _badge(TradeState state) {
    switch (state) {
      case TradeState.working:
        return const SizedBox(
          width: 84,
          height: 84,
          child: Padding(
            padding: EdgeInsets.all(22),
            child: CircularProgressIndicator(strokeWidth: 3, color: Glass.ink),
          ),
        );
      case TradeState.done:
        return _circle(Glass.ink, Icons.check_rounded, Colors.white);
      case TradeState.submitted:
        return _circle(Colors.white, Icons.schedule_rounded, Glass.ink);
      case TradeState.failed:
        return _circle(const Color(0xFFFCE8E6), Icons.priority_high_rounded, Glass.danger);
    }
  }

  Widget _circle(Color fill, IconData icon, Color ink) => Container(
    width: 84,
    height: 84,
    decoration: BoxDecoration(
      color: fill,
      shape: BoxShape.circle,
      border: fill == Colors.white ? Border.all(color: Glass.hairline) : null,
    ),
    child: Icon(icon, size: 44, color: ink),
  );
}
