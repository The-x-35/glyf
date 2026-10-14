import 'package:flutter/material.dart';

import '../core/billing.dart';
import '../core/bridge.dart';
import '../core/glyf_api.dart';
import '../core/telemetry.dart';
import '../core/theme.dart';
import '../wallet/crypto_pay.dart';

/// Apple's standard licence, which Glyf's subscriptions are sold under.
const _termsURL = 'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';

/// §6.16 — two plans over free, in whole dollars. Free: 50 runs a week ·
/// Plus $2 a month or $20 a year: 150 a day · Max $5 a month or $50 a year:
/// 400 a day (yearly is two months free).
/// Suggestions and translations have their own daily counts; the server
/// enforces all of them (server/src/lib/limits.ts).
///
/// On the iPhone the plans are bought through the App Store
/// (core/billing.dart) and the server checks Apple's signature before a
/// plan changes. They are sold only once the store has answered with them;
/// until then, and on Android until Google Play billing, they show
/// read-only.
///
/// True when a plan was bought: the account has it now.
Future<bool> showPaywall(BuildContext context, {String? reason}) async {
  Telemetry.log('paywall_shown', {'reason': reason ?? 'profile', 'onSale': Billing.available});
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
  /// The App Store has answered (there is nothing to ask on Android).
  bool _asked = !Billing.available;
  bool _busy = false;
  String? _note;

  /// Only what the store returned is sold: before the plans exist in App
  /// Store Connect, every tap on a buy button failed.
  bool get _onSale => _store.isNotEmpty;

  /// Plans in USDC: only the Solana dApp Store build, and only while the
  /// server takes them (wallet/crypto_pay.dart).
  bool _crypto = false;

  /// A plan can be picked: the App Store sells it, or USDC does.
  bool get _selectable => _onSale || _crypto;

  @override
  void initState() {
    super.initState();
    if (CryptoPay.allowed) {
      CryptoPay.available().then((on) {
        if (mounted && on) setState(() => _crypto = true);
      });
    }
    if (!_asked) {
      Billing.products().then((found) {
        if (mounted) {
          setState(() {
            _store = found;
            _asked = true;
          });
        }
      }, onError: (Object _) {
        if (mounted) setState(() => _asked = true);
      });
    }
  }

  /// The App Store's own price, in the person's currency; the US price
  /// until the store has answered.
  String _price(String plan, {required bool yearly}) =>
      _store[Billing.productFor(plan, yearly: yearly)]?.price ??
      switch ((plan, yearly)) {
        ('plus', false) => '\$2',
        ('plus', true) => '\$20',
        ('max', false) => '\$5',
        _ => '\$50',
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

  /// The price in whole USDC, the same dollars as the App Store's US price.
  static String _usdc(String plan, {required bool yearly}) => switch ((plan, yearly)) {
        ('plus', false) => '2',
        ('plus', true) => '20',
        ('max', false) => '5',
        _ => '50',
      };

  Future<void> _payCrypto() async {
    final plan = _selected, yearly = _yearly;
    setState(() {
      _busy = true;
      _note = null;
    });
    Telemetry.log('crypto_pay_started', {'plan': plan, 'yearly': yearly, 'reason': widget.reason ?? 'profile'});
    try {
      final request = await CryptoPay.request(plan, yearly: yearly);
      final problem = await CryptoPay.pay(request);
      if (!mounted) return;
      if (problem != null) {
        setState(() {
          _busy = false;
          _note = problem.isEmpty ? null : problem;
        });
        return;
      }
      setState(() => _note = 'Waiting for Solana');
      final got = await CryptoPay.waitForPlan(request.reference);
      if (!mounted) return;
      if (got != null && got != 'free') {
        Telemetry.log('crypto_pay_done', {'plan': got});
        Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _busy = false;
        _note = 'Not on Solana yet. Your plan starts when it lands';
      });
    } on GlyfApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _note = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _note = "Couldn't reach Glyf. Try again";
      });
    }
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

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            widget.reason == 'cap' ? 'You’re out of runs today' : 'Upgrade Glyf',
            style: const TextStyle(
                color: Glass.ink, fontSize: 21, fontWeight: FontWeight.w800),
          ),
          if (widget.reason == 'cap') ...[
            const SizedBox(height: 4),
            const Text('They come back tomorrow.',
                style: TextStyle(color: Glass.inkSoft, fontSize: 14)),
          ],
          const SizedBox(height: 16),
          if (_selectable) ...[
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
                badge: _selectable ? 'Best' : null,
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
            button: _selectable,
            child: _busy || !_asked
                ? const SizedBox(
                    height: 48,
                    child: Center(
                        child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: Glass.ink))))
                : _onSale
                    ? PillButton(
                        label: _selected == 'max' ? 'Get Max' : 'Get Plus',
                        onPressed: _store.containsKey(Billing.productFor(_selected, yearly: _yearly)) ? _buy : null)
                    : _crypto
                        ? PillButton(
                            label: 'Pay ${_usdc(_selected, yearly: _yearly)} USDC',
                            onPressed: _payCrypto)
                        : const SizedBox(
                            height: 48,
                            child: Center(
                              child: Text('Plans open soon',
                                  style: TextStyle(color: Glass.inkSoft, fontSize: 15, fontWeight: FontWeight.w700)),
                            ),
                          ),
          ),
          // Both on sale: USDC as the second way to pay.
          if (_onSale && _crypto && !_busy)
            Semantics(
              identifier: 'paywall:usdc',
              button: true,
              child: TextButton(
                onPressed: _payCrypto,
                child: Text('Pay ${_usdc(_selected, yearly: _yearly)} USDC',
                    style: const TextStyle(color: Glass.ink, fontSize: 14, fontWeight: FontWeight.w700)),
              ),
            ),
          // The sheet closes with a swipe down or a tap above it, so it needs
          // no Not now. Restore stays on the iPhone, plans on sale or not: it
          // brings back a plan this Apple ID already paid for, and App Review
          // asks every subscription screen for one. Gift codes live in
          // Profile (Got a code?).
          if (Billing.available)
            Semantics(
              identifier: 'paywall:restore',
              button: true,
              child: TextButton(
                onPressed: _busy ? null : _restore,
                child: const Text('Restore purchases',
                    style: TextStyle(color: Glass.inkSoft, fontSize: 14)),
              ),
            )
          else
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Close',
                  style: TextStyle(color: Glass.inkSoft, fontSize: 14)),
            ),
          if (_onSale) _terms(),
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

  /// One line: that it can be cancelled, and the two links App Review asks
  /// every subscription screen for. Apple's own sheet spells out renewal.
  Widget _terms() {
    const style = TextStyle(color: Glass.inkSoft, fontSize: 12);
    Widget link(String label, String url) => GestureDetector(
          onTap: () => GlyfBridge.openURL(url),
          child: Text(label,
              style: style.copyWith(
                  decoration: TextDecoration.underline, decorationColor: Glass.inkSoft)),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('Cancel anytime', style: style),
        const Text('  ·  ', style: style),
        link('Terms', _termsURL),
        const Text('  ·  ', style: style),
        link('Privacy', privacyPolicyURL),
      ]),
    );
  }

  Widget _planCard({
    required String id,
    required String name,
    String? badge,
    required List<String> features,
  }) {
    final selected = _selectable && _selected == id;
    final card = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _selectable && !_busy ? () => setState(() => _selected = id) : null,
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
        ]),
      ),
    );
    // Plus and Max both pick by tap, and by name for VoiceOver.
    if (_selectable) return Semantics(identifier: 'paywall:$id', button: true, selected: selected, child: card);
    // Not for sale yet: shown so people see what is coming, greyed so
    // nobody mistakes it for something to buy.
    return Semantics(
      identifier: 'paywall:$id',
      label: '$name, opens soon',
      child: Opacity(opacity: 0.5, child: card),
    );
  }
}
