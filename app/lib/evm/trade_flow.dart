import 'dart:async';
import 'dart:convert';

import '../core/bridge.dart';
import '../core/glyf_api.dart';
import 'evm_chains.dart';
import 'evm_rpc.dart';
import 'evm_wallet.dart';
import 'pay_request.dart';

/// How a trade stands: still going, done, sent but unconfirmed, refused.
enum TradeState { working, done, submitted, failed }

class TradeOutcome {
  const TradeOutcome(this.state, this.title, {this.detail, this.txUrl, this.insert});

  final TradeState state;
  final String title;
  final String? detail;

  /// The explorer page for the transaction (or Flash's order), when there is one.
  final String? txUrl;

  /// Text the keyboard types into the chat on its return (a pay link).
  final String? insert;
}

/// What the keyboard read (TradeIntent.query) carried out with the Glyf
/// wallet: Uniswap for swaps, Definitive's Flash for every order that waits
/// on a price or spreads over time, plain transfers for sends, GlyfPayRequest
/// on Whitechain for requests. Every number is asked for again here: the
/// keyboard's quote was only for show.
abstract final class TradeFlow {
  static Stream<TradeOutcome> run(Map<String, String> q) async* {
    try {
      final address = await EvmWallet.load();
      if (address == null) {
        yield const TradeOutcome(TradeState.failed, 'No Glyf wallet yet',
            detail: 'Make one in Profile › Wallet, then try again');
        return;
      }
      final kind = q['kind'] ?? 'swap';
      final chain = EvmChain.named(q['chain']) ?? EvmChain.base;
      final Stream<TradeOutcome> steps = switch (kind) {
        'swap' => _swap(q, chain, address),
        'send' => _send(q, chain, address),
        'request' => _request(q, address),
        _ => _flash(q, kind, chain, address),
      };
      await for (final o in steps) {
        yield o.state == TradeState.working ? o : await _told(o);
      }
    } on GlyfApiException catch (e) {
      yield await _told(TradeOutcome(TradeState.failed, 'That didn’t go through', detail: _plain(e.message)));
    } on EvmRpcException catch (e) {
      yield await _told(TradeOutcome(TradeState.failed, 'The network said no', detail: _plain(e.message)));
    } catch (e) {
      yield await _told(TradeOutcome(TradeState.failed, 'Something went wrong', detail: _plain('$e')));
    }
  }

  /// Nodes and APIs speak in codes; the screen says what they mean.
  static String _plain(String message) {
    final m = message.toLowerCase();
    if (m.contains('insufficient funds') || m.contains('insufficient balance') || m.contains('exceeds balance')) {
      return 'Not enough in the Glyf wallet for this and its fee';
    }
    if (m.contains('nonce')) return 'Another transaction is still going through. Try again in a moment';
    if (m.contains('timeout') || m.contains('timed out')) return 'The network took too long to answer';
    return message.length > 160 ? '${message.substring(0, 157)}…' : message;
  }

  // MARK: Uniswap

  static Stream<TradeOutcome> _swap(Map<String, String> q, EvmChain chain, String address) async* {
    yield const TradeOutcome(TradeState.working, 'Asking Uniswap…');
    final body = <String, Object?>{
      'chain': chain.name,
      'sell': q['sell'],
      'buy': q['buy'],
      'recipient': address,
      'swapper': address,
      'slippageBps': 50,
    };
    if (q['buyAmount'] != null) {
      body['amount'] = q['buyAmount'];
      body['side'] = 'buy';
    } else if (q['amount'] != null) {
      body['amount'] = q['amount'];
      body['side'] = 'sell';
    } else {
      // "sell my eth": everything, less the gas to send it when it's ETH.
      body['amount'] = await _allOf(chain, address, q['sell']!);
      body['side'] = 'sell';
    }
    final swap = await GlyfApi.evmPost('/uniswap/swap', body);
    final sellSym = q['sell']!;
    final buySym = q['buy']!;
    final approval = swap['approval'];
    if (approval is Map) {
      yield TradeOutcome(TradeState.working, 'Letting Uniswap use your $sellSym…');
      final hash = await EvmWallet.send(chain, EvmCall.fromJson(Map<String, dynamic>.from(approval)));
      final r = await EvmRpc.receipt(chain, hash);
      if (r == null || !EvmRpc.succeeded(r)) {
        yield TradeOutcome(TradeState.failed, 'The approval didn’t go through', txUrl: chain.txUrl(hash));
        return;
      }
    }
    final txs = (swap['txs'] as List? ?? const []).cast<Map>();
    if (txs.isEmpty) throw GlyfApiException('Uniswap had no route for this');
    yield TradeOutcome(TradeState.working, 'Swapping $sellSym for $buySym…');
    String? last;
    for (final tx in txs) {
      last = await EvmWallet.send(chain, EvmCall.fromJson(Map<String, dynamic>.from(tx)));
      final r = await EvmRpc.receipt(chain, last);
      if (r == null) {
        yield TradeOutcome(TradeState.submitted, 'Swap sent', detail: 'Still confirming on ${chain.label}',
            txUrl: chain.txUrl(last));
        return;
      }
      if (!EvmRpc.succeeded(r)) {
        yield TradeOutcome(TradeState.failed, 'The swap reverted',
            detail: 'The price moved past the limit. Nothing was spent but the fee', txUrl: chain.txUrl(last));
        return;
      }
    }
    final inAmount = _fmt(swap['amountIn']);
    final outAmount = _fmt(swap['amountOut']);
    yield TradeOutcome(TradeState.done, 'Swapped',
        detail: '$inAmount $sellSym → $outAmount $buySym on ${chain.label}', txUrl: chain.txUrl(last!));
  }

  // MARK: Flash

  static const _flashOrderTypes = {
    'limit': 'limit',
    'stop': 'stop',
    'stop-loss': 'stop-loss',
    'take-profit': 'take-profit',
    'bracket': 'bracket',
    'trailing-stop': 'trailing-stop',
    'twap': 'twap',
    'bridge': 'market',
  };

  /// The body Flash's /quote takes, from the keyboard's words. Prices are
  /// the target asset's dollars (notional); sells count the target, buys
  /// the contra (Flash's own convention).
  static Future<Map<String, Object?>> flashBody(
      Map<String, String> q, String kind, EvmChain chain, String address) async {
    final sell = q['sell']!;
    final buy = q['buy']!;
    final stable = {'USDC', 'USDT', 'DAI'};
    // An order is about the asset that isn't the dollar side.
    final buying = stable.contains(sell) && !stable.contains(buy);
    final target = buying ? buy : sell;
    final contra = buying ? sell : buy;
    final toChain = EvmChain.named(q['toChain']);
    final body = <String, Object?>{
      'targetChain': kind == 'bridge' ? (toChain ?? chain).name : chain.name,
      'contraChain': chain.name,
      'target': target,
      'contra': kind == 'bridge' ? sell : contra,
      'side': kind == 'bridge' ? 'buy' : (buying ? 'buy' : 'sell'),
      'orderType': _flashOrderTypes[kind] ?? 'market',
      'funderAddress': address,
    };
    // How much: dollars of the contra for buys, the target held for sells.
    String? qty = q['amount'];
    if (kind == 'bridge') {
      body['recipientAddress'] = address;
    } else if (!buying && qty == null) {
      qty = await _allOf(chain, address, target, keepGas: false);
    } else if (buying && q['buyAmount'] != null && q['price'] != null) {
      // "buy 0.1 eth at 2800": 0.1 × 2800 of the contra.
      qty = _trim(double.parse(q['buyAmount']!) * double.parse(q['price']!));
    } else if (buying && q['buyAmount'] != null) {
      // "buy 0.1 eth, tp 4500, sl 3000": a market buy, so today's price.
      qty = _trim(double.parse(q['buyAmount']!) * await _priceOf(chain, target));
    }
    body['qty'] = qty;
    final price = q['price'];
    switch (kind) {
      case 'limit':
        body['limitNotionalPrice'] = price;
      case 'stop':
        body['triggers'] = [
          {'notionalPrice': price, 'triggerType': 'upper'},
        ];
      case 'stop-loss':
        body['triggers'] = [
          {'notionalPrice': price, 'triggerType': 'lower'},
        ];
      case 'take-profit':
        body['triggers'] = [
          {'notionalPrice': price, 'triggerType': 'upper'},
        ];
      case 'bracket':
        if (buying) {
          // A market buy with its take-profit and stop attached.
          body['orderType'] = 'market';
          body['attachedBracket'] = {
            'takeProfit': {'notionalPrice': price},
            'stopLoss': {'notionalPrice': q['stopPrice']},
          };
        } else {
          body['triggers'] = [
            {'notionalPrice': price, 'triggerType': 'upper'},
            {'notionalPrice': q['stopPrice'], 'triggerType': 'lower'},
          ];
        }
      case 'trailing-stop':
        body['trailingStop'] = {'trailPercent': _trim(double.parse(q['trail'] ?? '5') / 100)};
      case 'twap':
        body['durationSeconds'] = int.tryParse(q['duration'] ?? '') ?? 86400;
    }
    return body;
  }

  static Stream<TradeOutcome> _flash(Map<String, String> q, String kind, EvmChain chain, String address) async* {
    if (chain.name == 'solana') {
      yield const TradeOutcome(TradeState.failed, 'Solana orders come next',
          detail: 'Flash orders sign with the Glyf wallet on Base, Ethereum, Arbitrum, Optimism and Polygon for now');
      return;
    }
    yield const TradeOutcome(TradeState.working, 'Asking Flash…');
    final quote = await GlyfApi.evmPost('/flash/quote', await flashBody(q, kind, chain, address));
    final evm = Map<String, dynamic>.from((quote['evm'] as Map?) ?? const {});
    // An allowance first, when Flash says the token needs one.
    final approve = evm['approveTx'] ?? evm['approvalTx'];
    if (approve is Map) {
      yield TradeOutcome(TradeState.working, 'Letting Flash use your ${q['sell']}…');
      final hash = await EvmWallet.send(chain, EvmCall.fromJson(Map<String, dynamic>.from(approve)));
      final r = await EvmRpc.receipt(chain, hash);
      if (r == null || !EvmRpc.succeeded(r)) {
        yield TradeOutcome(TradeState.failed, 'The approval didn’t go through', txUrl: chain.txUrl(hash));
        return;
      }
    }
    // Spending ETH: Flash trades WETH, so it's wrapped first.
    final wrap = quote['wrap'];
    if (wrap is Map && wrap['to'] != null) {
      yield const TradeOutcome(TradeState.working, 'Wrapping ETH…');
      final hash = await EvmWallet.send(chain, EvmCall.fromJson(Map<String, dynamic>.from(wrap)));
      await EvmRpc.receipt(chain, hash);
    }
    final typed = evm['orderTypedData'];
    if (typed == null) throw GlyfApiException((quote['error'] ?? quote['message'] ?? 'Flash sent nothing to sign').toString());
    yield const TradeOutcome(TradeState.working, 'Signing the order…');
    final order = <String, Object?>{
      'quoteId': quote['quoteId'],
      'userSignature': EvmWallet.signTypedData(typed),
      'evmOrderTypedData': typed,
      'bridgeQuoteId': ?quote['bridgeQuoteId'],
    };
    final permit = evm['permit2TypedData'] ?? evm['permitTypedData'];
    if (permit != null) {
      order['evmPermit2TypedData'] = permit;
      order['evmPermit2Signature'] = EvmWallet.signTypedData(permit);
    }
    final bracketTyped = evm['attachedBracketTypedData'] ?? evm['bracketOrderTypedData'];
    if (bracketTyped != null) {
      order['evmAttachedBracketTypedData'] = bracketTyped;
      order['attachedBracketSignature'] = EvmWallet.signTypedData(bracketTyped);
    }
    final placed = await GlyfApi.evmPost('/flash/order', order);
    final id = (placed['orderId'] ?? placed['id'])?.toString();
    if (id == null) throw GlyfApiException((placed['error'] ?? 'Flash didn’t take the order').toString());
    yield TradeOutcome(
      kind == 'bridge' || (kind == 'bracket' && q['buyAmount'] != null) ? TradeState.submitted : TradeState.done,
      _placedTitle(kind),
      detail: _placedDetail(q, kind, chain),
      txUrl: 'https://app.definitive.fi/orders/$id',
    );
  }

  static String _placedTitle(String kind) => switch (kind) {
        'stop-loss' => 'Stop-loss set',
        'take-profit' => 'Take profit set',
        'limit' => 'Limit order placed',
        'stop' => 'Stop buy placed',
        'bracket' => 'Bracket set',
        'trailing-stop' => 'Trailing stop set',
        'twap' => 'TWAP started',
        'bridge' => 'Moving across',
        _ => 'Order placed',
      };

  static String _placedDetail(Map<String, String> q, String kind, EvmChain chain) {
    final p = q['price'] == null ? '' : '\$${q['price']}';
    final asset = {'USDC', 'USDT', 'DAI'}.contains(q['sell']) ? q['buy'] : q['sell'];
    return switch (kind) {
      'stop-loss' => 'Sells $asset if it falls to $p · ${chain.label}',
      'take-profit' => 'Sells $asset if it rises to $p · ${chain.label}',
      'limit' => 'Fills at $p or better · ${chain.label}',
      'stop' => 'Buys $asset if it breaks $p · ${chain.label}',
      'bracket' => 'Take profit $p · stop \$${q['stopPrice']} · ${chain.label}',
      'trailing-stop' => 'Follows $asset ${q['trail']}% below its high · ${chain.label}',
      'twap' => '\$${q['amount']} of $asset in slices · ${chain.label}',
      'bridge' => '${q['amount']} ${q['sell']} to ${EvmChain.named(q['toChain'])?.label ?? ''}',
      _ => chain.label,
    };
  }

  // MARK: Sends

  static Stream<TradeOutcome> _send(Map<String, String> q, EvmChain chain, String address) async* {
    final to = q['address'] ?? q['to'];
    if (to == null || !RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(to)) {
      yield TradeOutcome(TradeState.failed, 'No address for ${q['to'] ?? 'that name'}');
      return;
    }
    final symbol = q['sell'] ?? 'ETH';
    final amount = q['amount'];
    if (amount == null) {
      yield const TradeOutcome(TradeState.failed, 'How much?', detail: 'Say an amount, like “send 20 usdc to arpit.eth”');
      return;
    }
    yield TradeOutcome(TradeState.working, 'Sending $amount $symbol…');
    final EvmCall call;
    if (symbol == chain.native) {
      call = EvmCall(to: to, value: _units(amount, 18), gas: BigInt.from(21000));
    } else {
      final token = await _token(chain, symbol);
      call = EvmCall(to: token.address, data: erc20Transfer(to, _units(amount, token.decimals)));
    }
    final hash = await EvmWallet.send(chain, call);
    final r = await EvmRpc.receipt(chain, hash);
    final who = q['to'] ?? to;
    if (r == null) {
      yield TradeOutcome(TradeState.submitted, 'Sent', detail: '$amount $symbol to $who, still confirming',
          txUrl: chain.txUrl(hash));
    } else if (EvmRpc.succeeded(r)) {
      yield TradeOutcome(TradeState.done, 'Sent', detail: '$amount $symbol to $who on ${chain.label}',
          txUrl: chain.txUrl(hash));
    } else {
      yield TradeOutcome(TradeState.failed, 'The send reverted', txUrl: chain.txUrl(hash));
    }
  }

  // MARK: Whitechain

  static Stream<TradeOutcome> _request(Map<String, String> q, String address) async* {
    final amount = q['amount'];
    if (amount == null) {
      yield const TradeOutcome(TradeState.failed, 'How much?', detail: 'Say an amount, like “request 20 usdt”');
      return;
    }
    yield const TradeOutcome(TradeState.working, 'Making the request on Whitechain…');
    final made = await PayRequests.create(amount: amount, memo: q['memo'] ?? '');
    yield TradeOutcome(TradeState.done, 'Request ready',
        detail: '$amount USDT · the link is going in the chat',
        txUrl: EvmChain.whitechainSepolia.txUrl(made.txHash),
        insert: 'Pay me $amount USDT: ${made.link}');
  }

  // MARK: helpers

  static Future<({String address, int decimals})> _token(EvmChain chain, String symbol) async {
    final res = await GlyfApi.evmGet('/evm/tokens?chain=${chain.name}');
    for (final t in (res['tokens'] as List? ?? const []).cast<Map>()) {
      if ((t['symbol'] as String?)?.toUpperCase() == symbol.toUpperCase()) {
        return (address: t['address'] as String, decimals: (t['decimals'] as num).toInt());
      }
    }
    throw GlyfApiException('Glyf doesn’t know $symbol on ${chain.label}');
  }

  /// Everything held of [symbol], as a decimal string; ETH keeps enough back
  /// to pay for the transaction that spends it.
  static Future<String> _allOf(EvmChain chain, String address, String symbol, {bool keepGas = true}) async {
    final res = await GlyfApi.evmGet('/evm/balances?chain=${chain.name}&address=$address');
    for (final b in (res['balances'] as List? ?? const []).cast<Map>()) {
      final s = (b['symbol'] as String? ?? '').toUpperCase();
      if (s == symbol.toUpperCase() || (symbol == 'ETH' && s == 'NATIVE')) {
        var amount = double.tryParse('${b['amount'] ?? b['balance'] ?? 0}') ?? 0;
        if (symbol == chain.native && keepGas) amount -= chain.id == 1 ? 0.003 : 0.0002;
        if (amount <= 0) throw GlyfApiException('No $symbol in the Glyf wallet on ${chain.label}');
        return _trim(amount);
      }
    }
    throw GlyfApiException('No $symbol in the Glyf wallet on ${chain.label}');
  }

  /// One [symbol] in dollars, from Uniswap (1 of it quoted to USDC).
  static Future<double> _priceOf(EvmChain chain, String symbol) async {
    final res = await GlyfApi.evmPost('/uniswap/quote',
        {'chain': chain.name, 'sell': symbol, 'buy': 'USDC', 'amount': '1', 'side': 'sell'});
    final p = double.tryParse('${res['amountOut']}');
    if (p == null || p <= 0) throw GlyfApiException('No price for $symbol on ${chain.label}');
    return p;
  }

  /// ERC-20 transfer(to, amount).
  static String erc20Transfer(String to, BigInt amount) =>
      '0xa9059cbb${_word(to.substring(2))}${_word(amount.toRadixString(16))}';

  static String _word(String hex) => hex.toLowerCase().padLeft(64, '0');

  /// "20.5" of a token with [decimals] as its smallest units.
  static BigInt _units(String amount, int decimals) {
    final parts = amount.split('.');
    final whole = BigInt.parse(parts[0].isEmpty ? '0' : parts[0]);
    final frac = parts.length > 1 ? parts[1] : '';
    final padded = (frac.length > decimals ? frac.substring(0, decimals) : frac.padRight(decimals, '0'));
    return whole * BigInt.from(10).pow(decimals) + (padded.isEmpty ? BigInt.zero : BigInt.parse(padded));
  }

  static String _trim(double v) {
    var s = v.toStringAsFixed(8);
    while (s.contains('.') && (s.endsWith('0') || s.endsWith('.'))) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  static String _fmt(Object? v) {
    final d = double.tryParse('$v');
    if (d == null) return '$v';
    return _trim(double.parse(d.toStringAsFixed(d >= 1000 ? 2 : d >= 1 ? 4 : 6)));
  }

  /// How it went, where the keyboard reads it (shared settings): said once
  /// back in the chat, with a pay link typed in for a request.
  static Future<TradeOutcome> _told(TradeOutcome o) async {
    try {
      await GlyfBridge.updateSharedSettings((s) {
        s['walletOutcome'] = jsonEncode({
          'title': o.title,
          if (o.detail != null) 'detail': o.detail,
          if (o.insert != null) 'insert': o.insert,
          'at': DateTime.now().millisecondsSinceEpoch / 1000.0,
        });
        return s;
      });
    } catch (_) {
      // A toast the keyboard misses is no reason to fail the trade.
    }
    return o;
  }
}
