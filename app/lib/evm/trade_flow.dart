import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/bridge.dart';
import '../core/glyf_api.dart';
import '../wallet/base58.dart';
import '../wallet/flash_solana.dart';
import '../wallet/phantom.dart';
import '../wallet/solana.dart';
import '../wallet/wallet_api.dart';
import '../wallet/wallet_flow.dart';
import 'evm_chains.dart';
import 'evm_rpc.dart';
import 'evm_signer.dart';

/// How a trade stands: still going, done, sent but unconfirmed, refused.
enum TradeState { working, done, submitted, failed }

class TradeOutcome {
  const TradeOutcome(this.state, this.title,
      {this.detail, this.txUrl, this.reopen, this.hash, this.orderId});

  final TradeState state;
  final String title;
  final String? detail;

  /// The explorer page for the transaction (or Flash's order), when there is one.
  final String? txUrl;

  /// Opens MetaMask again while it's waiting on it.
  final String? reopen;

  /// The swap's transaction, or Flash's order.
  final String? hash;
  final String? orderId;
}

/// What the keyboard read (TradeIntent.query) carried out in the person's
/// own wallet app: Uniswap for swaps and Definitive's Flash for every order
/// that waits on a price or spreads over time, signed in MetaMask on
/// Ethereum chains; Jupiter swaps and Flash orders on Solana, signed in
/// Phantom. Glyf builds each request and checks each answer; it holds no
/// key. Every number is asked for again here: the keyboard's quote was only
/// for show.
abstract final class TradeFlow {
  /// The kinds the keyboard hands over (TradeIntent.query `kind`).
  static const kinds = {'swap', 'limit', 'stop', 'stop-loss', 'take-profit', 'bracket', 'trailing-stop', 'twap', 'bridge'};

  static Stream<TradeOutcome> run(Map<String, String> q) async* {
    final kind = q['kind'] ?? 'swap';
    final onSolana = q['chain'] == 'solana';
    if (!kinds.contains(kind)) {
      // A send or a pay request from an older keyboard: not a trade here.
      yield await _told(const TradeOutcome(TradeState.failed, 'Glyf can’t do that one',
          detail: 'Swaps and orders only. Send from Profile › Wallet'));
      return;
    }
    try {
      if (onSolana && kind == 'swap') {
        // Uniswap has no Solana pools here; Jupiter swaps there (as Uniswap's
        // own app does), signed in Phantom.
        await for (final o in _jupiterSwap(q)) {
          yield o.state == TradeState.working ? o : await _told(o);
        }
        return;
      }
      if (onSolana) {
        // Solana's orders: Flash, signed in Phantom.
        await for (final o in _flashSolana(q, kind)) {
          yield o.state == TradeState.working ? o : await _told(o);
        }
        return;
      }
      final address = await EvmSigner.load();
      if (address == null) {
        yield await _told(const TradeOutcome(TradeState.failed, 'MetaMask isn’t connected', detail: EvmSigner.missing));
        return;
      }
      final chain = EvmChain.named(q['chain']) ?? EvmChain.base;
      final Stream<TradeOutcome> steps = switch (kind) {
        'swap' => _swap(q, chain, address),
        _ => _flash(q, kind, chain, address),
      };
      await for (final o in steps) {
        yield o.state == TradeState.working ? o : await _told(o);
      }
    } on SignFailed catch (e) {
      yield await _told(TradeOutcome(TradeState.failed, e.title,
          detail: e.detail == null ? null : _plain(e.detail!, solana: onSolana),
          txUrl: e.hash == null ? null : (onSolana ? WalletFlow.solscanUrl(e.hash!) : e.chain?.txUrl(e.hash!))));
    } on GlyfApiException catch (e) {
      yield await _told(
          TradeOutcome(TradeState.failed, 'That didn’t go through', detail: _plain(e.message, solana: onSolana)));
    } on EvmRpcException catch (e) {
      yield await _told(TradeOutcome(TradeState.failed, 'The network said no', detail: _plain(e.message)));
    } on WalletError catch (e) {
      yield await _told(TradeOutcome(TradeState.failed, 'Solana said no', detail: _plain(e.message, solana: true)));
    } catch (e) {
      yield await _told(TradeOutcome(TradeState.failed, 'Something went wrong', detail: _plain('$e', solana: onSolana)));
    }
  }

  static String _walletName({bool solana = false}) => solana ? 'Phantom' : EvmSigner.kind.value.label;

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
  static String _plain(String message, {bool solana = false}) {
    final m = message.toLowerCase();
    if (m.contains('no record of a prior credit')) {
      final name = _walletName(solana: true);
      return '${name[0].toUpperCase()}${name.substring(1)} needs a little SOL for the network fee';
    }
    if (solana && (m.contains('does not exist') || m.contains('ata_setup') || m.contains('delegat'))) {
      return 'The setup hasn’t landed on Solana yet. Try again in a minute';
    }
    if (m.contains('insufficient funds') || m.contains('insufficient balance') || m.contains('exceeds balance') ||
        m.contains('outoffunds') || m.contains('transfer amount exceeds')) {
      return 'Not enough in ${_walletName(solana: solana)} for this and its fee';
    }
    if (m.contains('nonce')) return 'Another transaction is still going through. Try again in a moment';
    if (m.contains('timeout') || m.contains('timed out')) return 'The network took too long to answer';
    return message.length > 160 ? '${message.substring(0, 157)}…' : message;
  }

  // MARK: Uniswap

  static Stream<TradeOutcome> _swap(Map<String, String> q, EvmChain chain, String address) async* {
    yield const TradeOutcome(TradeState.working, 'Asking Uniswap…');
    // A token picked in the keyboard rides by its address, so a lookalike
    // symbol can't stand in; a swap can land on another chain (buyChain).
    final body = <String, Object?>{
      'chain': chain.name,
      'sell': q['sellAddress'] ?? q['sell'],
      'buy': q['buyAddress'] ?? q['buy'],
      if (q['buyChain'] != null && q['buyChain'] != chain.name) 'buyChain': q['buyChain'],
      'recipient': address,
      'swapper': address,
      'slippage': 0.5,
    };
    if (q['buyAmount'] != null) {
      // "buy 0.1 eth with usdc": what 0.1 ETH costs now, a hair over so
      // the swap lands at least the amount asked for.
      final cost = await GlyfApi.evmPost('/uniswap/quote',
          {'chain': chain.name, 'sell': q['buyAddress'] ?? q['buy'], 'buy': q['sellAddress'] ?? q['sell'], 'amount': q['buyAmount']});
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
          Map<String, String> q, String kind, EvmChain chain, String address) =>
      flashBodyOn(q, kind, chain.name, address,
          toChain: EvmChain.named(q['toChain'])?.name,
          allOf: (symbol) => _allOf(chain, address, symbol),
          priceOf: (symbol) => _priceOf(chain, symbol));

  /// [flashBody] on any of Flash's chains ("solana" too): [allOf] reads
  /// what's held of a coin, [priceOf] its dollar price.
  @visibleForTesting
  static Future<Map<String, Object?>> flashBodyOn(Map<String, String> q, String kind, String chainName, String address,
      {String? toChain,
      required Future<String> Function(String symbol) allOf,
      required Future<double> Function(String symbol) priceOf}) async {
    final sell = q['sell']!;
    final buy = q['buy']!;
    final stable = {'USDC', 'USDT', 'DAI'};
    // An order is about the asset that isn't the dollar side.
    final buying = stable.contains(sell) && !stable.contains(buy);
    final target = buying ? buy : sell;
    final contra = buying ? sell : buy;
    final body = <String, Object?>{
      'targetChain': kind == 'bridge' ? (toChain ?? chainName) : chainName,
      'contraChain': chainName,
      // A bridge's target is on the other chain: its symbol, not this chain's address.
      'target': kind == 'bridge' ? target : ((buying ? q['buyAddress'] : q['sellAddress']) ?? target),
      'contra': kind == 'bridge' ? (q['sellAddress'] ?? sell) : ((buying ? q['sellAddress'] : q['buyAddress']) ?? contra),
      'side': kind == 'bridge' ? 'buy' : (buying ? 'buy' : 'sell'),
      'orderType': _flashOrderTypes[kind] ?? 'market',
      'funderAddress': address,
    };
    // How much: dollars of the contra for buys, the target held for sells.
    String? qty = q['amount'];
    if (kind == 'bridge') {
      body['recipientAddress'] = address;
    } else if (!buying && qty == null) {
      qty = await allOf(target);
    } else if (buying && q['buyAmount'] != null && q['price'] != null && kind != 'bracket') {
      // "buy 0.1 eth at 2800": 0.1 × 2800 of the contra. (A bracket's price
      // is its take-profit, not what the buy pays.)
      qty = _trim(double.parse(q['buyAmount']!) * double.parse(q['price']!));
    } else if (buying && q['buyAmount'] != null) {
      // "buy 0.1 eth, tp 4500, sl 3000": a market buy, so today's price.
      qty = _trim(double.parse(q['buyAmount']!) * await priceOf(target));
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
      detail: _placedDetail(q, kind, chain.label, toLabel: EvmChain.named(q['toChain'])?.label),
      txUrl: 'https://app.definitive.fi/orders/$id',
      orderId: id,
    );
  }

  // MARK: Flash on Solana

  /// A Flash order on Solana, signed in Phantom over its deeplinks
  /// (flash.definitive.fi/docs/solana-overview.md): Flash quotes it for the
  /// Phantom wallet; anything it needs on chain first (token accounts, the
  /// SOL wrap, its delegation) goes into ONE transaction built here, signed
  /// in Phantom and broadcast by Flash; then Phantom signs Flash's order
  /// message (and the attached take-profit / stop-loss's), every signature
  /// is checked against the wallet's key, and the order goes in.
  static Stream<TradeOutcome> _flashSolana(Map<String, String> q, String kind) async* {
    if (kind == 'bridge') {
      yield const TradeOutcome(TradeState.failed, 'Moving from Solana comes next',
          detail: 'Flash moves coins from Base, Ethereum, Arbitrum, Optimism and Polygon for now');
      return;
    }
    await WalletFlow.load();
    final wallet = WalletFlow.link.value;
    if (wallet == null || wallet.viaMwa) {
      // Flash's Solana steps go by Phantom's deeplinks; a Mobile Wallet
      // Adapter wallet still swaps and pays, but doesn't place these yet.
      yield TradeOutcome(TradeState.failed, 'Phantom isn’t connected',
          detail: wallet == null ? 'Connect Phantom in Profile › Wallet' : 'Flash orders on Solana are signed in Phantom');
      return;
    }
    final funder = wallet.address;
    yield const TradeOutcome(TradeState.working, 'Asking Flash…');
    final quote = await GlyfApi.evmPost(
        '/flash/quote',
        await flashBodyOn(q, kind, 'solana', funder,
            allOf: (symbol) => _allOnSolana(funder, symbol), priceOf: _priceOnSolana));
    final svm = quote['svm'] is Map ? Map<String, dynamic>.from(quote['svm'] as Map) : null;
    final order = Map<String, dynamic>.from((quote['order'] as Map?) ?? const {});
    final message = svm?['orderMessage'] as String?;
    if (svm == null || message == null) {
      throw GlyfApiException((quote['error'] ?? quote['message'] ?? 'Flash sent nothing to sign').toString());
    }
    // What Phantom will be asked to sign says what the person asked for:
    // the coin spent, and exactly how much of it.
    final buying = order['side'] == 'buy';
    final spentMint = '${buying ? order['contraAsset'] : order['targetAsset']}';
    final gotMint = '${buying ? order['targetAsset'] : order['contraAsset']}';
    final decimals = (((quote['tokens'] as Map?)?[buying ? 'contra' : 'target'] as Map?)?['decimals'] as num?)?.toInt();
    final total = decimals == null ? null : Sol.units('${order['qty']}', decimals);
    final problem = FlashSvm.messageProblem(message, mint: spentMint, total: total);
    if (problem != null) throw SignFailed(problem, detail: 'Nothing was signed');
    final pair = order['attachedBracket'] is Map ? Map<String, dynamic>.from(order['attachedBracket'] as Map) : null;
    final pairMessage = ((quote['attachedBracket'] as Map?)?['svm'] as Map?)?['orderMessage'] as String?;
    if (pair != null) {
      final p = FlashSvm.messageProblem(pairMessage, mint: gotMint);
      if (p != null) throw SignFailed(p, detail: 'Nothing was signed');
    }
    final placed0 = _placedTitle(kind).replaceFirst(RegExp(r' (set|placed|started)$'), '');
    final title = placed0.startsWith('TWAP') ? placed0 : placed0[0].toLowerCase() + placed0.substring(1);

    // 1. On chain first, once per token: one transaction, one trip.
    String? setupSig;
    final setupIxs = FlashSvm.setupInstructions(quote);
    if (setupIxs.isNotEmpty) {
      final asked = FlashSvm.setupTransaction(quote: quote, funder: funder, blockhash: await _solanaBlockhash(quote))!;
      yield const TradeOutcome(TradeState.working, 'Approve the setup in Phantom',
          detail: 'Token accounts and Flash’s allowance, once per token');
      final reply = await _askPhantom((id) => WalletFlow.phantom.signUrl(asked, id, step: PhantomRequests.step));
      final signed = await _phantomAnswer(() => WalletFlow.phantom.finishSign(reply));
      if (!FlashSvm.isSignedSetup(signed, asked, funder)) {
        throw SignFailed('That isn’t what Glyf asked Phantom to sign', detail: 'Nothing was sent');
      }
      setupSig = FlashSvm.txSignature(signed);
      yield TradeOutcome(TradeState.working, 'Setting up on Solana…',
          txUrl: setupSig == null ? null : WalletFlow.solscanUrl(setupSig));
      // A simulator's stand-in wallet holds no SOL to pay for the setup:
      // `--glyf-test-flash-skip-setup` (never in a release build) checks the
      // signed setup and goes on without sending it, so the order's own
      // signing and Flash's answer to it can be seen.
      final skip = await _testFlag('--glyf-test-flash-skip-setup');
      final sent = skip
          ? const {'status': 'confirmed'}
          : await GlyfApi.evmPost('/flash/setup-transaction', {'signedSetupTx': base64.encode(signed)},
              timeout: const Duration(seconds: 60));
      if (sent['status'] != 'confirmed' && setupSig != null) {
        bool? landed;
        try {
          landed = await SolanaRpc.confirm(setupSig, wait: const Duration(seconds: 45));
        } catch (_) {
          // No node to ask: Flash refuses the order until the setup lands.
        }
        if (landed == false) {
          throw SignFailed('The setup didn’t go through',
              detail: 'Solana turned it down. Nothing else was signed', hash: setupSig);
        }
      }
    }

    // Definitive pays for the delegation when it offers to: Phantom signs
    // Flash's transaction, and it goes back with the order.
    final sponsored = svm['sponsoredDelegateTx'];
    if (sponsored is String && sponsored.isNotEmpty) {
      final asked = base64.decode(sponsored);
      yield const TradeOutcome(TradeState.working, 'Let Flash use your coins in Phantom',
          detail: 'Definitive pays this one’s fee');
      final reply = await _askPhantom((id) => WalletFlow.phantom.signUrl(asked, id, step: PhantomRequests.step));
      final signed = await _phantomAnswer(() => WalletFlow.phantom.finishSign(reply));
      if (!FlashSvm.isSignedSponsored(signed, asked, funder)) {
        throw SignFailed('That isn’t what Glyf asked Phantom to sign', detail: 'Nothing was placed');
      }
      order['svmSponsoredDelegateTx'] = base64.encode(signed);
    }

    // 2. The order itself: a message, no fee.
    yield TradeOutcome(TradeState.working, 'Sign the $title in Phantom', txUrl: _solscan(setupSig));
    order['userSignature'] = Base58.encode(await _signOnSolana(message, funder));
    if (pair != null) {
      yield TradeOutcome(TradeState.working, 'Sign the take profit and stop in Phantom', txUrl: _solscan(setupSig));
      pair['userSignature'] = Base58.encode(await _signOnSolana(pairMessage!, funder));
      order['attachedBracket'] = pair;
    }
    yield TradeOutcome(TradeState.working, 'Placing the order…', txUrl: _solscan(setupSig));
    final placed = await GlyfApi.evmPost('/flash/order', order);
    final id = (placed['orderId'] ?? placed['id'])?.toString();
    if (id == null) throw GlyfApiException((placed['error'] ?? 'Flash didn’t take the order').toString());
    yield TradeOutcome(
      kind == 'bracket' && q['buyAmount'] != null ? TradeState.submitted : TradeState.done,
      _placedTitle(kind),
      detail: '${_placedDetail(q, kind, 'Solana')} · Order ${id.length > 8 ? id.substring(0, 8) : id}',
      txUrl: 'https://app.definitive.fi/orders/$id',
      orderId: id,
      hash: setupSig,
    );
  }

  static String? _solscan(String? signature) => signature == null ? null : WalletFlow.solscanUrl(signature);

  /// Phantom signs [message] (Flash's UTF-8 order text); the signature is
  /// the funder's or the order stops here.
  static Future<Uint8List> _signOnSolana(String message, String funder) async {
    final reply = await _askPhantom((id) => WalletFlow.phantom.signMessageUrl(message, id, step: PhantomRequests.step));
    final signature = await _phantomAnswer(() => WalletFlow.phantom.finishSignMessage(reply));
    if (!FlashSvm.verifyMessage(message, signature, funder)) {
      throw SignFailed('That signature isn’t from ${Sol.short(funder)}', detail: 'Nothing was placed');
    }
    return signature;
  }

  /// Opens Phantom on the request [build] makes for an id, and waits for
  /// its answer on `glyf://phantom/trade/<id>`.
  static Future<Uri> _askPhantom(Future<Uri> Function(String id) build) async {
    final id = PhantomRequests.newId();
    final Uri url;
    try {
      url = await build(id);
    } on PhantomError catch (e) {
      throw SignFailed(e.message);
    }
    try {
      return await PhantomRequests.ask(id, () async {
        final failed = await WalletFlow.openPhantom(url);
        // No Phantom on a simulator: with `--glyf-test-phantom` (never in a
        // release build) qa/fake-phantom.mjs answers the logged link.
        return failed != null && await _testFlag('--glyf-test-phantom') ? null : failed;
      });
    } on PhantomUnavailable catch (e) {
      throw SignFailed(e.message);
    } on TimeoutException {
      throw SignFailed('Phantom didn’t answer', detail: 'Nothing was placed. Try again');
    }
  }

  static Future<bool> _testFlag(String flag) async =>
      !kReleaseMode && (await GlyfBridge.launchArgs()).contains(flag);

  static Future<T> _phantomAnswer<T>(Future<T> Function() read) async {
    try {
      return await read();
    } on PhantomError catch (e) {
      if (e.cancelled) throw SignFailed('Cancelled in Phantom', detail: 'Nothing was placed', cancelled: true);
      throw SignFailed('Phantom couldn’t sign it', detail: e.message);
    }
  }

  /// A recent blockhash to build the setup with: Solana's, or the one in
  /// Flash's own setup transaction when no node answers.
  static Future<String> _solanaBlockhash(Map quote) async {
    try {
      return await SolanaRpc.blockhash();
    } catch (_) {
      final fromQuote = FlashSvm.blockhashOf(quote);
      if (fromQuote != null) return fromQuote;
      rethrow;
    }
  }

  /// A swap on Solana: Jupiter's order for the taker, signed through the
  /// wallet's own buy (WalletFlow.buy: Phantom, or a Mobile Wallet Adapter
  /// wallet on Android).
  static Stream<TradeOutcome> _jupiterSwap(Map<String, String> q) async* {
    yield const TradeOutcome(TradeState.working, 'Asking Jupiter…');
    final sell = await _solanaToken(q['sell'] ?? 'SOL');
    final buy = await _solanaToken(q['buy'] ?? 'USDC');
    final String amount;
    if (q['buyAmount'] != null) {
      // "buy 1 sol with usdc": what it costs now, a hair over.
      final want = double.tryParse(q['buyAmount']!) ?? 0;
      amount = _trim(want * await _priceOnSolana(buy.symbol) / await _priceOnSolana(sell.symbol) * 1.006);
    } else if (q['amount'] != null) {
      amount = q['amount']!;
    } else {
      throw GlyfApiException('Say how much ${sell.symbol} to swap');
    }
    final start = await WalletFlow.buy(token: buy, payWith: sell, amount: amount);
    if (start.error != null) {
      yield TradeOutcome(TradeState.failed, 'Jupiter couldn’t swap that', detail: start.error);
      return;
    }
    final progress = start.progress;
    if (progress == null) {
      // Phantom has it; its answer comes back to the wallet.
      yield const TradeOutcome(TradeState.submitted, 'Approve the swap in Phantom',
          detail: 'Glyf shows the result when Phantom sends you back');
      return;
    }
    await for (final o in progress) {
      yield jupiterOutcome(o);
    }
  }

  /// A wallet step as the trade screen shows it.
  static TradeOutcome jupiterOutcome(PayOutcome o) {
    final url = o.signature == null ? null : WalletFlow.solscanUrl(o.signature!);
    return switch (o.state) {
      PayState.working => TradeOutcome(TradeState.working, o.title, detail: o.detail),
      PayState.done => TradeOutcome(TradeState.done, o.title, detail: o.detail, txUrl: url, hash: o.signature),
      PayState.submitted => TradeOutcome(TradeState.submitted, o.title, detail: o.detail, txUrl: url, hash: o.signature),
      PayState.failed || PayState.cancelled => TradeOutcome(TradeState.failed, o.title, detail: o.detail),
    };
  }

  static Future<TokenInfo> _solanaToken(String symbol) async {
    final s = symbol.toUpperCase();
    if (s == 'SOL') return TokenInfo.sol;
    if (s == 'USDC') return TokenInfo.usdc;
    final t = await Jupiter.token(symbol);
    if (t == null) throw GlyfApiException('Glyf doesn’t know $symbol on Solana');
    return t;
  }

  /// Everything Phantom's wallet holds of [symbol]; SOL keeps 0.01 back for
  /// the fees and the token accounts' rent.
  static Future<String> _allOnSolana(String owner, String symbol) async {
    final token = await _solanaToken(symbol);
    var units = token.mint == Sol.wsol ? await SolanaRpc.solBalance(owner) : await SolanaRpc.tokenBalance(owner, token.mint);
    if (token.mint == Sol.wsol) units -= BigInt.from(10000000);
    if (units <= BigInt.zero) throw GlyfApiException('No ${token.symbol} in Phantom');
    return Sol.format(units, token.decimals, maxDecimals: token.decimals);
  }

  static Future<double> _priceOnSolana(String symbol) async {
    if (const {'USDC', 'USDT'}.contains(symbol.toUpperCase())) return 1;
    final p = (await _solanaToken(symbol)).usdPrice ?? (await Jupiter.token(symbol))?.usdPrice;
    if (p == null || p <= 0) throw GlyfApiException('No price for $symbol on Solana');
    return p;
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

  static String _placedDetail(Map<String, String> q, String kind, String chainLabel, {String? toLabel}) {
    final p = q['price'] == null ? '' : '\$${q['price']}';
    final asset = {'USDC', 'USDT', 'DAI'}.contains(q['sell']) ? q['buy'] : q['sell'];
    return switch (kind) {
      'stop-loss' => 'Sells $asset if it falls to $p · $chainLabel',
      'take-profit' => 'Sells $asset if it rises to $p · $chainLabel',
      'limit' => 'Fills at $p or better · $chainLabel',
      'stop' => 'Buys $asset if it breaks $p · $chainLabel',
      'bracket' => 'Take profit $p · stop \$${q['stopPrice']} · $chainLabel',
      'trailing-stop' => 'Follows $asset ${q['trail']}% below its high · $chainLabel',
      'twap' => '\$${q['amount']} of $asset in slices · $chainLabel',
      'bridge' => '${q['amount']} ${q['sell']} to ${toLabel ?? ''}',
      _ => chainLabel,
    };
  }

  // MARK: helpers

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
  /// back in the chat.
  static Future<TradeOutcome> _told(TradeOutcome o) async {
    try {
      await GlyfBridge.updateSharedSettings((s) {
        s['walletOutcome'] = jsonEncode({
          'title': o.title,
          if (o.detail != null) 'detail': o.detail,
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
