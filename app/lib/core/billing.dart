import 'dart:io';

import 'bridge.dart';
import 'glyf_api.dart';

/// A plan as the App Store sells it: its own name and price, in the
/// person's currency.
class StoreProduct {
  const StoreProduct({required this.id, required this.price, required this.name, required this.period});
  final String id;
  final String price;
  final String name;

  /// "month" or "year".
  final String period;
}

/// What a purchase or a restore came to: the plan now on the account, or
/// what to tell the person ('' when they simply closed Apple's sheet).
typedef BillingOutcome = ({String? plan, String? message});

/// Plus and Max through the App Store.
///
/// The phone never decides a plan: each purchase goes to the server as the
/// transaction Apple signed, the server checks Apple's signature, and the
/// plan it answers with is the one the app and the keyboard use.
abstract final class Billing {
  static const plusMonthly = 'com.arpit.glyf.plus.monthly';
  static const plusYearly = 'com.arpit.glyf.plus.yearly';
  static const maxMonthly = 'com.arpit.glyf.max.monthly';
  static const maxYearly = 'com.arpit.glyf.max.yearly';
  static const ids = [plusMonthly, plusYearly, maxMonthly, maxYearly];

  /// The iPhone sells plans; Android waits for Google Play billing.
  static bool get available => Platform.isIOS;

  static String productFor(String plan, {required bool yearly}) => plan == 'max'
      ? (yearly ? maxYearly : maxMonthly)
      : (yearly ? plusYearly : plusMonthly);

  static Future<Map<String, StoreProduct>> products() async {
    if (!available) return const {};
    final list = await GlyfBridge.billingProducts(ids);
    return {
      for (final p in list)
        p['id'] as String: StoreProduct(
            id: p['id'] as String,
            price: p['price'] as String? ?? '',
            name: p['name'] as String? ?? '',
            period: p['period'] as String? ?? 'month'),
    };
  }

  static Future<BillingOutcome> buy(String productId) async {
    final res = await GlyfBridge.billingPurchase(productId);
    if (res['cancelled'] == true) return (plan: null, message: '');
    if (res['pending'] == true) {
      return (plan: null, message: 'Waiting for approval. The plan starts once it is approved.');
    }
    final jws = res['jws'];
    if (jws is! String) {
      return (plan: null, message: res['error'] as String? ?? "The App Store didn't finish that purchase.");
    }
    return _send([jws]);
  }

  static Future<BillingOutcome> restore() async {
    final res = await GlyfBridge.billingRestore();
    final held = [for (final t in res['transactions'] as List? ?? const []) t as String];
    if (held.isEmpty) {
      return (plan: null, message: res['error'] as String? ?? 'No Glyf plan on this Apple ID.');
    }
    return _send(held);
  }

  /// An offer code from App Store Connect: a gift month or year, or a
  /// discount. Closing Apple's sheet without a code says nothing.
  static Future<BillingOutcome> redeem() async {
    final res = await GlyfBridge.billingRedeem();
    final held = [for (final t in res['transactions'] as List? ?? const []) t as String];
    if (held.isEmpty) return (plan: null, message: res['error'] as String? ?? '');
    return _send(held);
  }

  /// At launch and on coming back: whatever the phone holds goes to the
  /// server, so a renewal the server hasn't heard of still counts.
  static Future<void> sync() async {
    if (!available) return;
    final held = await GlyfBridge.billingEntitlements();
    if (held.isNotEmpty) await _send(held);
  }

  /// Renewals and purchases finished outside the app go to the server too.
  static void listen() {
    if (available) GlyfBridge.onBillingUpdate((jws) => _send([jws]));
  }

  static Future<BillingOutcome> _send(List<String> transactions) async {
    try {
      final res = await GlyfApi.appleBilling(transactions);
      final plan = res['plan'] as String? ?? 'free';
      await GlyfBridge.updateSharedSettings((s) {
        s['plan'] = plan;
        s['proUnlocked'] = plan != 'free';
        return s;
      });
      return (plan: plan, message: null);
    } on GlyfApiException catch (e) {
      return (plan: null, message: e.message);
    } catch (_) {
      return (plan: null, message: "Couldn't reach Glyf. The purchase is safe: tap Restore in a moment.");
    }
  }
}
