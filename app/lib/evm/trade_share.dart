import 'dart:convert';

import '../core/bridge.dart';
import '../core/glyf_api.dart';
import 'evm_chains.dart';
import 'trade_flow.dart';

/// A trade that went through, shared into the chat as a link (server
/// routes/tradeshare.ts): the friend who taps it opens the same trade in
/// Glyf, quoted again, and signs it with their own wallet.
abstract final class TradeShare {
  /// Sends and requests name a person, so only trades are shared or copied.
  static bool shareable(Map<String, String> q) => !{'send', 'request'}.contains(q['kind'] ?? 'swap');

  /// The trade in one line: "Bought $50 of ETH on Base" once it's done
  /// ([past]), "Buy $50 of ETH on Base" for a friend about to copy it.
  static String describe(Map<String, String> q, {required bool past}) {
    String v(String done, String todo) => past ? done : todo;
    final kind = q['kind'] ?? 'swap';
    final sell = q['sell'] ?? '';
    final buy = q['buy'] ?? '';
    final amount = q['amount'];
    final chain = EvmChain.named(q['chain'])?.label ?? '';
    const stable = {'USDC', 'USDT', 'DAI'};
    final buying = stable.contains(sell) && !stable.contains(buy);
    final asset = buying ? buy : sell;
    final price = q['price'] == null ? '' : ' at \$${q['price']}';
    final String what = switch (kind) {
      'swap' when q['usd'] == '1' && amount != null => '${v('Bought', 'Buy')} \$$amount of $buy',
      'swap' when q['buyAmount'] != null => '${v('Bought', 'Buy')} ${q['buyAmount']} $buy with $sell',
      'swap' when amount != null => '${v('Swapped', 'Swap')} $amount $sell for $buy',
      'swap' => '${v('Swapped', 'Swap')} all ${v('my', 'your')} $sell for $buy',
      'limit' => '${v('Placed', 'Place')} a limit ${buying ? 'buy' : 'sell'} for $asset$price',
      'stop' => 'Set a stop buy for $asset$price',
      'stop-loss' => 'Set a stop-loss on $asset$price',
      'take-profit' => 'Set a take profit on $asset$price',
      'bracket' => 'Set a bracket on $asset: take profit \$${q['price']}, stop \$${q['stopPrice']}',
      'trailing-stop' => 'Set a ${q['trail'] ?? '5'}% trailing stop on $asset',
      'twap' => '${v('Started', 'Start')} a TWAP${amount == null ? '' : ' of \$$amount'} into $asset',
      'bridge' => '${v('Moved', 'Move')} ${amount ?? v('all my', 'all your')} $sell from $chain to '
          '${EvmChain.named(q['toChain'])?.label ?? ''}',
      _ => '${v('Traded', 'Trade')} $sell for $buy',
    };
    return kind == 'bridge' || chain.isEmpty ? what : '$what on $chain';
  }

  /// What POST /trade-shares takes: the keyboard's words for the trade
  /// (never a recipient), the line, and where it can be seen.
  static Map<String, Object?> body(Map<String, String> q, TradeOutcome o) {
    final chain = EvmChain.named(q['chain']);
    return {
      'query': {
        for (final e in q.entries)
          if (!{'to', 'address', 'copied', 'memo'}.contains(e.key)) e.key: e.value,
      },
      'summary': describe(q, past: true),
      if (chain != null) 'chainId': chain.id,
      if (o.hash != null && RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch(o.hash!)) 'txHash': o.hash,
      if (o.orderId != null && RegExp(r'^[\w-]{1,80}$').hasMatch(o.orderId!)) 'orderId': o.orderId,
    };
  }

  /// Makes the link; the chat line comes back (“… with Glyf. Copy my trade: the link”).
  static Future<String> post(Map<String, String> q, TradeOutcome o) async {
    final res = await GlyfApi.evmPost('/trade-shares', body(q, o));
    final text = res['text'];
    if (text is! String || text.isEmpty) throw GlyfApiException('Glyf couldn’t make the link');
    return text;
  }

  /// Where the keyboard reads it (shared settings): back in the chat, the
  /// strip offers Share trade once, for 10 minutes.
  static Future<void> handToKeyboard(String text) => GlyfBridge.updateSharedSettings((s) {
        s['tradeShare'] = jsonEncode({'text': text, 'at': DateTime.now().millisecondsSinceEpoch / 1000.0});
        return s;
      });
}
