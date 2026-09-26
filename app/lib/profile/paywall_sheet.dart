import 'package:flutter/material.dart';

import '../core/bridge.dart';
import '../core/glyf_api.dart';
import '../core/telemetry.dart';
import '../core/theme.dart';

/// §6.16 — two plans over free. Free: 20 runs a day · Plus $1.99 a month or
/// $19.99 a year: 150 a day · Max $4.99 a month or $49.99 a year: 400 a day.
/// Suggestions and translations have their own daily counts; the server
/// enforces all of them (server/src/lib/limits.ts). App Store products and
/// server receipt validation replace the same toggle at ship.

/// Plus and Max can't be bought yet: App Store and Play subscriptions are
/// the next update. Until then the plans show greyed out as Coming soon,
/// and nothing here can change a plan.
const plansOnSale = false;

Future<bool> showPaywall(BuildContext context, {String? reason}) async {
  Telemetry.log('paywall_shown', {'reason': reason ?? 'profile', 'onSale': plansOnSale});
  final plan = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(Glass.radiusSheet))),
    builder: (ctx) => _PaywallSheet(reason: reason),
  );
  if (plan != null && plansOnSale) {
    // The server's word first: caps are enforced there, so a plan the phone
    // merely believes in would show 150 runs while the keyboard counts 20.
    String? refusal;
    try {
      final res = await GlyfApi.setPlan(plan);
      if (res['ok'] != true) refusal = (res['error'] as String?) ?? 'Could not change the plan';
    } on GlyfApiException catch (e) {
      refusal = e.message;
    } catch (_) {
      refusal = "Couldn't reach Glyf. Try again.";
    }
    if (refusal != null) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(refusal)));
      }
      Telemetry.log('plan_refused', {'plan': plan, 'reason': reason ?? 'profile'});
      return false;
    }
    await GlyfBridge.updateSharedSettings((s) {
      s['plan'] = plan;
      s['proUnlocked'] = plan != 'free';
      return s;
    });
    Telemetry.log('plan_selected', {'plan': plan, 'reason': reason ?? 'profile'});
    return true;
  }
  return false;
}

class _PaywallSheet extends StatefulWidget {
  const _PaywallSheet({this.reason});
  final String? reason;

  @override
  State<_PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends State<_PaywallSheet> {
  String _selected = 'plus';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
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
          const SizedBox(height: 18),
          // One height for both cards, so the plans read as a pair.
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: _planCard(
                id: 'plus',
                name: 'Plus',
                price: '\$1.99',
                yearly: 'or \$19.99 a year\n2 months free',
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
                price: '\$4.99',
                yearly: 'or \$49.99 a year\n2 months free',
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
          const SizedBox(height: 16),
          Semantics(
            identifier: 'paywall:unlock',
            button: true,
            child: PillButton(
                label: plansOnSale
                    ? (_selected == 'max' ? 'Get Max' : 'Get Plus')
                    : 'Coming soon',
                onPressed: plansOnSale ? () => Navigator.of(context).pop(_selected) : null),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: Text(plansOnSale ? 'Not now' : 'Close',
                style: const TextStyle(color: Glass.inkSoft, fontSize: 14)),
          ),
        ]),
      ),
    );
  }

  Widget _planCard({
    required String id,
    required String name,
    required String price,
    String? yearly,
    String? badge,
    required List<String> features,
  }) {
    final selected = plansOnSale && _selected == id;
    final card = GestureDetector(
      onTap: plansOnSale ? () => setState(() => _selected = id) : null,
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
            Text(price,
                style: const TextStyle(
                    color: Glass.ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w800)),
            const Text(' /mo',
                style: TextStyle(color: Glass.inkSoft, fontSize: 12)),
          ]),
          if (yearly != null)
            Text(yearly,
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
