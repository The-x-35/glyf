import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/bridge.dart';
import '../core/theme.dart';
import 'wallet_flow.dart';

/// Where Phantom's reply lands: the payment is sent on from here, and the
/// person sees how it went. Also the answer to Connect.
class PayStatusScreen extends StatefulWidget {
  const PayStatusScreen({super.key, required this.reply});

  final Uri reply;

  @override
  State<PayStatusScreen> createState() => _PayStatusScreenState();
}

class _PayStatusScreenState extends State<PayStatusScreen> {
  PayOutcome _outcome = const PayOutcome(state: PayState.working, title: 'One moment…');

  @override
  void initState() {
    super.initState();
    WalletFlow.handleReply(widget.reply).listen((outcome) {
      if (!mounted) return;
      if (outcome.state == PayState.done) HapticFeedback.mediumImpact();
      setState(() => _outcome = outcome);
    });
  }

  @override
  Widget build(BuildContext context) {
    final o = _outcome;
    final working = o.state == PayState.working;
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
                  identifier: 'pay:title',
                  child: Text(
                    o.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Glass.ink, fontSize: 26, fontWeight: FontWeight.w800),
                  ),
                ),
                if (o.detail != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    o.detail!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Glass.inkSoft,
                      fontSize: 16,
                      height: 1.35,
                      fontFeatures: [FontFeature.disable('calt')],
                    ),
                  ),
                ],
                if (o.signature != null) ...[
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => GlyfBridge.openURL('https://solscan.io/tx/${o.signature}'),
                    child: const Text(
                      'View on Solscan',
                      style: TextStyle(
                        color: Glass.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
                const Spacer(flex: 3),
                if (!working) PillButton(label: 'Done', onPressed: () => Navigator.of(context).maybePop()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _badge(PayState state) {
    switch (state) {
      case PayState.working:
        return const SizedBox(
          width: 84,
          height: 84,
          child: Padding(
            padding: EdgeInsets.all(22),
            child: CircularProgressIndicator(strokeWidth: 3, color: Glass.ink),
          ),
        );
      case PayState.done:
        return _circle(Glass.ink, Icons.check_rounded, Colors.white);
      case PayState.failed:
        return _circle(const Color(0xFFFCE8E6), Icons.priority_high_rounded, Glass.danger);
      case PayState.cancelled:
        return _circle(Colors.white, Icons.close_rounded, Glass.inkSoft);
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
