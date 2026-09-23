import 'package:flutter/material.dart';

import '../core/bridge.dart';
import '../core/glyf_api.dart';
import '../core/telemetry.dart';
import '../core/theme.dart';

/// §6.16 — two plans over free (priced against Wispr Flow $12–15/mo and
/// Grammarly ~$12/mo: we undercut with Plus and out-feature with Max).
/// Free: 40 runs/day · Plus $4.99: 400 runs/day + priority · Max $19.99:
/// unlimited + the smartest models. This build unlocks locally; App Store
/// products + server receipt validation replace the same toggle at ship.
Future<bool> showPaywall(BuildContext context, {String? reason}) async {
  Telemetry.log('paywall_shown', {'reason': reason ?? 'profile'});
  final plan = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(Glass.radiusSheet))),
    builder: (ctx) => _PaywallSheet(reason: reason),
  );
  if (plan != null) {
    // The server's word first: caps are enforced there, so a plan the phone
    // merely believes in would show 400 runs while the keyboard counts 40.
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
                : 'Upgrade Glyf',
            style: const TextStyle(
                color: Glass.ink, fontSize: 21, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(
              child: _planCard(
                id: 'plus',
                name: 'Plus',
                price: '\$4.99',
                features: const [
                  '400 runs a day',
                  'Priority speed',
                  'Every tool & connector',
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _planCard(
                id: 'max',
                name: 'Max',
                price: '\$19.99',
                badge: 'Best',
                features: const [
                  'Unlimited Glyf runs',
                  'The smartest models',
                  'Unlimited custom Glyfs',
                  'Early features',
                ],
              ),
            ),
          ]),
          const SizedBox(height: 16),
          Semantics(
            identifier: 'paywall:unlock',
            button: true,
            child: PillButton(
                label: _selected == 'max' ? 'Get Max' : 'Get Plus',
                onPressed: () => Navigator.of(context).pop(_selected)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Not now',
                style: TextStyle(color: Glass.inkSoft, fontSize: 14)),
          ),
        ]),
      ),
    );
  }

  Widget _planCard({
    required String id,
    required String name,
    required String price,
    String? badge,
    required List<String> features,
  }) {
    final selected = _selected == id;
    return GestureDetector(
      onTap: () => setState(() => _selected = id),
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
  }
}
