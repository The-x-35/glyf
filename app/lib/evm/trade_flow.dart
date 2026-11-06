import 'dart:async';
import 'dart:convert';

import '../core/bridge.dart';
import '../core/glyf_api.dart';
import 'evm_chains.dart';
import 'evm_rpc.dart';
import 'evm_signer.dart';
import 'evm_wallet.dart';
import 'pay_request.dart';

/// How a trade stands: still going, done, sent but unconfirmed, refused.
enum TradeState { working, done, submitted, failed }

class TradeOutcome {
  const TradeOutcome(this.state, this.title,
      {this.detail, this.txUrl, this.insert, this.reopen, this.hash, this.orderId});

  final TradeState state;
  final String title;
  final String? detail;

  /// The explorer page for the transaction (or Flash's order), when there is one.
  final String? txUrl;

  /// Text the keyboard types into the chat on its return (a pay link).
  final String? insert;

  /// Opens MetaMask or Phantom again while it's waiting on them.
  final String? reopen;

  /// What a shared trade links to (TradeShare): the swap's transaction, or
  /// Flash's order.
  final String? hash;
  final String? orderId;
}

/// What the keyboard read (TradeIntent.query) carried out with the chosen
/// wallet (EvmSigner: the Glyf wallet, MetaMask or Phantom): Uniswap for
/// swaps, Definitive's Flash for every order that waits
/// on a price or spreads over time, plain transfers for sends, GlyfPayRequest
/// on Whitechain for requests. Every number is asked for again here: the
/// keyboard's quote was only for show.
abstract final class TradeFlow {
  static Stream<TradeOutcome> run(Map<String, String> q) async* {
    try {
      final address = await EvmSigner.load();
      if (address == null) {
        yield TradeOutcome(TradeState.failed,
            EvmSigner.kind.value == EvmSignerKind.glyf ? 'No Glyf wallet yet' : '${EvmSigner.kind.value.label} isn’t connected',
            detail: 'Set it up in Profile › Wallet › Ethereum, then try again');
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
    } on SignFailed catch (e) {
      yield await _told(TradeOutcome(TradeState.failed, e.title,
          detail: e.detail == null ? null : _plain(e.detail!),
          txUrl: e.hash == null ? null : e.chain?.txUrl(e.hash!)));
    } on GlyfApiException catch (e) {
      yield await _told(TradeOutcome(TradeState.failed, 'That didn’t go through', detail: _plain(e.message)));
    } on EvmRpcException catch (e) {
      yield await _told(TradeOutcome(TradeState.failed, 'The network said no', detail: _plain(e.message)));
    } catch (e) {
      yield await _told(TradeOutcome(TradeState.failed, 'Something went wrong', detail: _plain('$e')));
    }
  }

  static String _walletName() =>
      EvmSigner.kind.value == EvmSignerKind.glyf ? 'the Glyf wallet' : EvmSigner.kind.value.label;

  /// The signer's progress as the screen shows it; [got] receives what was signed.
  static Stream<TradeOutcome> _sign(String title, List<SignStep> steps, void Function(List<Signed>) got) async* {
    await for (final e in EvmSigner.run(title, steps)) {
      if (e.results != null) {
        got(e.results!);
      } else {
        yield TradeOutcome(TradeState.working, e.label!, reopen: e.reopen);
      }
    }
  }

  /// Nodes and APIs speak in codes; the screen says what they mean.
  static String _plain(String message) {
    final m = message.toLowerCase();
    if (m.contains('insufficient funds') || m.contains('insufficient balance') || m.contains('exceeds balance') ||
        m.contains('outoffunds') || m.contains('transfer amount exceeds')) {
      return 'Not enough in ${_walletName()} for this and its fee';
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
      'slippage': 0.5,
    };
    if (q['buyAmount'] != null) {
      // "buy 0.1 eth with usdc": what 0.1 ETH costs now, a hair over so
      // the swap lands at least the amount asked for.
      final cost = await GlyfApi.evmPost('/uniswap/quote',
          {'chain': chain.name, 'sell': q['buy'], 'buy': q['sell'], 'amount': q['buyAmount']});
      final need = double.tryParse('${cost['amountOut']}');
      if (need == null || need <= 0) throw GlyfApiException('Uniswap had no price for ${q['buy']}');
      body['amount'] = _trim(need * 1.006);
    } else if (q['amount'] != null) {
      body['amount'] = q['amount'];
    } else {
      // "sell my eth": everything, less the gas to send it when it's ETH.
      body['amount'] = await _allOf(chain, address, q['sell']!);
    }
    final swap = await GlyfApi.evmPost('/uniswap/swap', body);
    final sellSym = q['sell']!;
    final buySym = q['buy']!;
    final steps = <SignStep>[
      if (swap['approvalReset'] is Map)
        TxStep(chain, 'Reset the $sellSym allowance', EvmCall.fromJson(Map<String, dynamic>.from(swap['approvalReset'] as Map))),
      if (swap['approval'] is Map)
        TxStep(chain, 'Let Uniswap use your $sellSym', EvmCall.fromJson(Map<String, dynamic>.from(swap['approval'] as Map)),
            failTitle: 'The approval didn’t go through'),
      for (final tx in (swap['txs'] as List? ?? const []).cast<Map>())
        TxStep(chain, 'Swap $sellSym for $buySym', EvmCall.fromJson(Map<String, dynamic>.from(tx)),
            failTitle: 'The swap reverted', failDetail: 'The price moved past the limit. Nothing was spent but the fee'),
    ];
    if (steps.whereType<TxStep>().every((t) => !t.label.startsWith('Swap'))) {
      throw GlyfApiException('Uniswap had no route for this');
    }
    late List<Signed> signed;
    yield* _sign('Swap $sellSym for $buySym', steps, (r) => signed = r);
    final last = signed.last;
    if (last.pending) {
      yield TradeOutcome(TradeState.submitted, 'Swap sent', detail: 'Still confirming on ${chain.label}',
          txUrl: chain.txUrl(last.hash!), hash: last.hash);
      return;
    }
    final inAmount = _fmt(swap['amountIn']);
    final outAmount = _fmt(swap['amountOut']);
    yield TradeOutcome(TradeState.done, 'Swapped',
        detail: '$inAmount $sellSym → $outAmount $buySym on ${chain.label}', txUrl: chain.txUrl(last.hash!),
        hash: last.hash);
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
      qty = await _allOf(chain, address, target);
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
          detail: 'Flash orders sign on Base, Ethereum, Arbitrum, Optimism and Polygon for now');
      return;
    }
    yield const TradeOutcome(TradeState.working, 'Asking Flash…');
    final quote = await GlyfApi.evmPost('/flash/quote', await flashBody(q, kind, chain, address));
    final evm = Map<String, dynamic>.from((quote['evm'] as Map?) ?? const {});
    // Anything Flash wants on chain first: an allowance (to Permit2), and
    // for ETH a wrap to WETH, which is what the order then spends.
    final wrapTx = (quote['wrap'] as Map?)?['evmTx'];
    final setup = <Object?>[
      evm['approveTx'] ?? evm['approvalTx'],
      ...((evm['setupTxs'] as List?) ?? (quote['setupTxs'] as List?) ?? const []),
      // Only when the order spends ETH the wallet holds as ETH.
      if (q['sell'] == chain.native || (q['buy'] == chain.native && kind == 'bridge')) wrapTx,
    ].whereType<Map>().where((t) => t['to'] != null).toList();
    // The server hands back the order ready but for the signatures.
    final order = Map<String, dynamic>.from((quote['order'] as Map?) ?? const {});
    final typed = order['evmOrderTypedData'] ?? evm['orderTypedData'];
    if (typed == null) {
      throw GlyfApiException((quote['error'] ?? quote['message'] ?? 'Flash sent nothing to sign').toString());
    }
    order['evmOrderTypedData'] = typed;
    final pairTyped = ((quote['attachedBracket'] as Map?)?['evm'] as Map?)?['orderTypedData'];
    final pair = order['attachedBracket'] is Map ? Map<String, dynamic>.from(order['attachedBracket'] as Map) : null;
    final title = _placedTitle(kind).replaceFirst(RegExp(r' (set|placed|started)$'), '');
    final steps = <SignStep>[
      for (final tx in setup)
        identical(tx, wrapTx)
            ? TxStep(chain, 'Wrap ETH for the order', EvmCall.fromJson(Map<String, dynamic>.from(tx)),
                failTitle: 'The wrap didn’t go through')
            : TxStep(chain, 'Let Flash use your ${q['sell']}', EvmCall.fromJson(Map<String, dynamic>.from(tx)),
                failTitle: 'The approval didn’t go through'),
      TypedStep(chain, 'Sign the $title', typed),
      if (order['evmPermitTypedData'] != null) TypedStep(chain, 'Sign the allowance', order['evmPermitTypedData']!),
      if (pair != null && pairTyped != null) TypedStep(chain, 'Sign the take profit and stop', pairTyped),
      if (pair != null && pairTyped != null && pair['evmPermitTypedData'] != null)
        TypedStep(chain, 'Sign their allowance', pair['evmPermitTypedData']!),
    ];
    late List<Signed> signed;
    yield* _sign(title, steps, (r) => signed = r);
    // The signatures, in the order they were asked for after the setup.
    var i = setup.length;
    order['userSignature'] = signed[i++].signature;
    if (order['evmPermitTypedData'] != null) order['evmPermitSignature'] = signed[i++].signature;
    if (pair != null && pairTyped != null) {
      pair['userSignature'] = signed[i++].signature;
      if (pair['evmPermitTypedData'] != null) pair['evmPermitSignature'] = signed[i++].signature;
      order['attachedBracket'] = pair;
    }
    yield const TradeOutcome(TradeState.working, 'Placing the order…');
    final placed = await GlyfApi.evmPost('/flash/order', order);
    final id = (placed['orderId'] ?? placed['id'])?.toString();
    if (id == null) throw GlyfApiException((placed['error'] ?? 'Flash didn’t take the order').toString());
    yield TradeOutcome(
      kind == 'bridge' || (kind == 'bracket' && q['buyAmount'] != null) ? TradeState.submitted : TradeState.done,
      _placedTitle(kind),
      detail: _placedDetail(q, kind, chain),
      txUrl: 'https://app.definitive.fi/orders/$id',
      orderId: id,
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
    final who = q['to'] ?? to;
    late List<Signed> signed;
    yield* _sign('Send $amount $symbol to $who',
        [TxStep(chain, 'Send $amount $symbol to $who', call, failTitle: 'The send reverted')], (r) => signed = r);
    final sent = signed.single;
    if (sent.pending) {
      yield TradeOutcome(TradeState.submitted, 'Sent', detail: '$amount $symbol to $who, still confirming',
          txUrl: chain.txUrl(sent.hash!));
    } else {
      yield TradeOutcome(TradeState.done, 'Sent', detail: '$amount $symbol to $who on ${chain.label}',
          txUrl: chain.txUrl(sent.hash!));
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
    final progress = StreamController<TradeOutcome>();
    final making = PayRequests.create(
        amount: amount,
        memo: q['memo'] ?? '',
        onProgress: (label, reopen) => progress.add(TradeOutcome(TradeState.working, label, reopen: reopen)));
    unawaited(making.whenComplete(progress.close).then((_) {}, onError: (_) {}));
    yield* progress.stream;
    final made = await making;
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
        if (amount <= 0) throw GlyfApiException('No $symbol in ${_walletName()} on ${chain.label}');
        return _trim(amount);
      }
    }
    throw GlyfApiException('No $symbol in ${_walletName()} on ${chain.label}');
  }

  /// One [symbol] in dollars, from Uniswap (1 of it quoted to USDC).
  static Future<double> _priceOf(EvmChain chain, String symbol) async {
    final res = await GlyfApi.evmPost('/uniswap/quote', {'chain': chain.name, 'sell': symbol, 'buy': 'USDC', 'amount': '1'});
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
