import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/bridge.dart';
import '../core/theme.dart';
import 'evm_signer.dart';
import 'trade_flow.dart';

/// The flash between the keyboard and the chain: the keyboard read the
/// trade and showed its quote, so this signs it at once (the Glyf wallet
/// here, or MetaMask or Phantom in their own app) and says how it went. Back in the chat, the keyboard says it too.
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

  @override
  void initState() {
    super.initState();
    _sub = (widget.run ?? TradeFlow.run)(widget.query).listen(
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
    super.dispose();
  }

  String get _linkLabel {
    final url = _outcome.txUrl ?? '';
    if (url.contains('definitive.fi')) return 'View on Definitive';
    if (url.contains('basescan')) return 'View on Basescan';
    if (url.contains('etherscan')) return 'View on Etherscan';
    if (url.contains('arbiscan')) return 'View on Arbiscan';
    if (url.contains('whitechain')) return 'View on Whitechain';
    return 'View transaction';
  }

  @override
  Widget build(BuildContext context) {
    final o = _outcome;
    final working = o.state == TradeState.working;
    return PopScope(
      canPop: !working,
      child: Scaffold(
        backgroundColor: Glass.bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            child: Column(
              children: [
                const Spacer(flex: 2),
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
                if (o.txUrl != null) ...[
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => GlyfBridge.openURL(o.txUrl!),
                    child: Text(
                      _linkLabel,
                      style: const TextStyle(
                        color: Glass.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
                const Spacer(flex: 3),
                if (working && o.reopen != null) ...[
                  Semantics(
                    identifier: 'trade:reopen',
                    button: true,
                    child: PillButton(
                        label: 'Open ${EvmSigner.kind.value.label}', onPressed: () => GlyfBridge.openURL(o.reopen!)),
                  ),
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
                else
                  PillButton(label: 'Done', onPressed: () => Navigator.of(context).maybePop()),
              ],
            ),
          ),
        ),
      ),
    );
  }

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
