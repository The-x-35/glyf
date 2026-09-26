import 'package:flutter/material.dart';

import '../core/billing.dart';
import '../core/bridge.dart';
import '../core/glyf_api.dart';
import '../core/telemetry.dart';
import '../core/theme.dart';

/// §6.16 — two plans over free. Free: 20 runs a day · Plus $1.99 a month or
/// $19.99 a year: 150 a day · Max $4.99 a month or $49.99 a year: 400 a day.
/// Suggestions and translations have their own daily counts; the server
/// enforces all of them (server/src/lib/limits.ts).
///
/// On the iPhone the plans are bought through the App Store
/// (core/billing.dart) and the server checks Apple's signature before a
/// plan changes. Android shows them as Coming soon until Google Play billing.
final bool plansOnSale = Billing.available;

/// Apple's standard licence, which Glyf's subscriptions are sold under.
const _termsURL = 'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';

/// True when a plan was bought: the account has it now.
Future<bool> showPaywall(BuildContext context, {String? reason}) async {
  Telemetry.log('paywall_shown', {'reason': reason ?? 'profile', 'onSale': plansOnSale});
  final bought = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(Glass.radiusSheet))),
    builder: (ctx) => _PaywallSheet(reason: reason),
  );
  return bought == true;
}

class _PaywallSheet extends StatefulWidget {
  const _PaywallSheet({this.reason});
  final String? reason;

  @override
  State<_PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends State<_PaywallSheet> {
  String _selected = 'plus';
  bool _yearly = false;
  Map<String, StoreProduct> _store = const {};
  bool _busy = false;
  String? _note;

  @override
  void initState() {
    super.initState();
    if (plansOnSale) {
      Billing.products().then((found) {
        if (mounted) setState(() => _store = found);
      });
    }
  }

  /// The App Store's own price, in the person's currency; the US price
  /// until the store has answered.
  String _price(String plan, {required bool yearly}) =>
      _store[Billing.productFor(plan, yearly: yearly)]?.price ??
      switch ((plan, yearly)) {
        ('plus', false) => '\$1.99',
        ('plus', true) => '\$19.99',
        ('max', false) => '\$4.99',
        _ => '\$49.99',
      };

  Future<void> _buy() async {
    final id = Billing.productFor(_selected, yearly: _yearly);
    setState(() {
      _busy = true;
      _note = null;
    });
    Telemetry.log('purchase_started', {'product': id, 'reason': widget.reason ?? 'profile'});
    final outcome = await Billing.buy(id);
    if (!mounted) return;
    if (outcome.plan != null && outcome.plan != 'free') {
      Telemetry.log('purchase_done', {'product': id, 'plan': outcome.plan});
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _note = (outcome.message ?? '').isEmpty ? null : outcome.message;
    });
  }

  Future<void> _restore() async {
    setState(() {
      _busy = true;
      _note = null;
    });
    final outcome = await Billing.restore();
    if (!mounted) return;
    if (outcome.plan != null && outcome.plan != 'free') {
      Telemetry.log('purchase_restored', {'plan': outcome.plan});
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _note = outcome.message ?? 'No Glyf plan on this Apple ID.';
    });
  }

  Future<void> _redeem() async {
    setState(() {
      _busy = true;
      _note = null;
    });
    final outcome = await Billing.redeem();
    if (!mounted) return;
    if (outcome.plan != null && outcome.plan != 'free') {
      Telemetry.log('offer_code_redeemed', {'plan': outcome.plan});
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _note = (outcome.message ?? '').isEmpty ? null : outcome.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            widget.reason == 'cap'
                ? 'You’re out of runs today'
                : plansOnSale ? 'Upgrade Glyf' : 'Glyf Pro',
            style: const TextStyle(
                color: Glass.ink, fontSize: 21, fontWeight: FontWeight.w800),
          ),
          if (widget.reason == 'cap') ...[
            const SizedBox(height: 4),
            const Text('They come back tomorrow.',
                style: TextStyle(color: Glass.inkSoft, fontSize: 14)),
          ],
          const SizedBox(height: 16),
          if (plansOnSale) ...[
            _periodSwitch(),
            const SizedBox(height: 12),
          ],
          // One height for both cards, so the plans read as a pair.
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: _planCard(
                id: 'plus',
                name: 'Plus',
                features: const [
                  '150 runs a day',
                  '3x the suggestions',
                  '4x the translations',
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _planCard(
                id: 'max',
                name: 'Max',
                badge: plansOnSale ? 'Best' : null,
                features: const [
                  '400 runs a day',
                  '6x the suggestions',
                  '10x the translations',
                  'Early features',
                ],
              ),
            ),
          ])),
          if (_note != null) ...[
            const SizedBox(height: 10),
            Text(_note!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Glass.inkSoft, fontSize: 13)),
          ],
          const SizedBox(height: 14),
          Semantics(
            identifier: 'paywall:unlock',
            button: true,
            child: _busy
                ? const SizedBox(
                    height: 48,
                    child: Center(
                        child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: Glass.ink))))
                : PillButton(
                    label: plansOnSale
                        ? (_selected == 'max' ? 'Get Max' : 'Get Plus')
                        : 'Coming soon',
                    onPressed: plansOnSale ? _buy : null),
          ),
          // The sheet closes with a swipe down or a tap above it, so it needs
          // no Not now. Restore stays: App Review asks every subscription
          // screen for one. Redeem code takes App Store Connect's offer
          // codes (gift months and years, discounts).
          if (plansOnSale)
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Semantics(
                identifier: 'paywall:restore',
                button: true,
                child: TextButton(
                  onPressed: _busy ? null : _restore,
                  child: const Text('Restore purchases',
                      style: TextStyle(color: Glass.inkSoft, fontSize: 14)),
                ),
              ),
              Semantics(
                identifier: 'paywall:redeem',
                button: true,
                child: TextButton(
                  onPressed: _busy ? null : _redeem,
                  child: const Text('Redeem code',
                      style: TextStyle(color: Glass.inkSoft, fontSize: 14)),
                ),
              ),
            ])
          else
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Close',
                  style: TextStyle(color: Glass.inkSoft, fontSize: 14)),
            ),
          if (plansOnSale) _terms(),
        ]),
      ),
    );
  }

  /// Monthly or yearly; yearly is two months free.
  Widget _periodSwitch() {
    Widget option(String label, bool yearly) {
      final on = _yearly == yearly;
      return Expanded(
        child: Semantics(
          identifier: yearly ? 'paywall:yearly' : 'paywall:monthly',
          button: true,
          selected: on,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _busy ? null : () => setState(() => _yearly = yearly),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: on ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                boxShadow: on
                    ? const [BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 1))]
                    : null,
              ),
              alignment: Alignment.center,
              child: Text(label,
                  style: TextStyle(
                      color: on ? Glass.ink : Glass.inkSoft,
                      fontSize: 13.5,
                      fontWeight: on ? FontWeight.w700 : FontWeight.w600)),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F2F5),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(children: [
        option('Monthly', false),
        option('Yearly · 2 months free', true),
      ]),
    );
  }

  /// What App Review asks every subscription screen to say.
  Widget _terms() {
    Widget link(String label, String url) => GestureDetector(
          onTap: () => GlyfBridge.openURL(url),
          child: Text(label,
              style: const TextStyle(
                  color: Glass.inkSoft,
                  fontSize: 11.5,
                  decoration: TextDecoration.underline,
                  decorationColor: Glass.inkSoft)),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Column(children: [
        const Text(
            'Renews automatically until you cancel, at least a day before it ends, '
            'in Settings › your name › Subscriptions.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Glass.inkSoft, fontSize: 11.5, height: 1.35)),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          link('Terms of Use', _termsURL),
          const Text('  ·  ', style: TextStyle(color: Glass.inkSoft, fontSize: 11.5)),
          link('Privacy Policy', privacyPolicyURL),
        ]),
      ]),
    );
  }

  Widget _planCard({
    required String id,
    required String name,
    String? badge,
    required List<String> features,
  }) {
    final selected = plansOnSale && _selected == id;
    final card = GestureDetector(
      onTap: plansOnSale && !_busy ? () => setState(() => _selected = id) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: selected ? Glass.ink : Glass.hairline,
              width: selected ? 1.8 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(name,
                style: const TextStyle(
                    color: Glass.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w800)),
            const Spacer(),
            if (badge != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Glass.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(badge,
                    style: const TextStyle(
                        color: Glass.accent,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800)),
              ),
          ]),
          const SizedBox(height: 2),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Flexible(
              child: Text(_price(id, yearly: _yearly),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Glass.ink,
                      fontSize: 22,
                      fontWeight: FontWeight.w800)),
            ),
            Text(_yearly ? ' /yr' : ' /mo',
                style: const TextStyle(color: Glass.inkSoft, fontSize: 12)),
          ]),
          Text(
              _yearly ? '2 months free' : 'or ${_price(id, yearly: true)} a year',
              style: const TextStyle(
                  color: Glass.accent, fontSize: 11.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          for (final f in features)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.check, size: 13, color: Glass.ink),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(f,
                          style: const TextStyle(
                              color: Glass.ink, fontSize: 12.5, height: 1.3)),
                    ),
                  ]),
            ),
          if (!plansOnSale) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F2F5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('Coming soon',
                  style: TextStyle(color: Glass.inkSoft, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ],
        ]),
      ),
    );
    if (plansOnSale) return card;
    // Not for sale yet: shown so people see what is coming, greyed so
    // nobody mistakes it for something to buy.
    return Semantics(
      identifier: 'paywall:$id',
      label: '$name, coming soon',
      child: Opacity(opacity: 0.5, child: card),
    );
  }
}
