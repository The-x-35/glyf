import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/bridge.dart';
import '../evm/evm_chains.dart';
import '../evm/evm_signer.dart';
import '../evm/trade_flow.dart';
import '../wallet/flash_solana.dart';
import '../wallet/mwa.dart';
import '../wallet/phantom.dart';
import '../wallet/solana.dart';
import '../wallet/wallet_api.dart';
import '../wallet/wallet_flow.dart';
import 'near_api.dart';

/// A step of a NEAR Intents trade, with what the trade screen shows beside
/// its line: the live quote (You pay / You get, Guard's checks), the
/// address to pay by hand, the NEAR Intents explorer page.
class NearOutcome extends TradeOutcome {
  const NearOutcome(super.state, super.title,
      {super.detail, super.txUrl, super.reopen, super.hash, this.quote, this.recipient, this.explorer,
      this.manual = false, this.blocked = false});

  final NearQuote? quote;

  /// Who gets it, as the person would know them ("alice.near", "7xKX…gAsU").
  final String? recipient;

  /// The trade on explorer.near-intents.org.
  final String? explorer;

  /// The deposit is made from another wallet: its address, amount and memo
  /// are shown to copy, with a QR code.
  final bool manual;

  /// Guard stopped it before anything was signed; the screen offers "Send anyway".
  final bool blocked;
}

/// What a NEAR Intents trade needs from the person's own wallets: who they
/// are on each chain, and the deposit signed (MetaMask on EVM chains,
/// Phantom or a Mobile Wallet Adapter wallet on Solana). A test stands in
/// for the wallets by overriding these.
class NearWallet {
  const NearWallet();

  /// The connected MetaMask's address, or null.
  Future<String?> evmAddress() => EvmSigner.load();

  /// The connected Solana wallet's address, or null.
  Future<String?> solanaAddress() async {
    await WalletFlow.load();
    return WalletFlow.link.value?.address;
  }

  String get solanaName => WalletFlow.link.value?.viaMwa == true ? 'your wallet' : 'Phantom';

  Stream<SignEvent> signEvm(String title, List<SignStep> steps) => EvmSigner.run(title, steps);

  Future<String> solanaBlockhash() => SolanaRpc.blockhash();

  /// [tx] signed in the Solana wallet: over Mobile Wallet Adapter on this
  /// phone, or Phantom by its deeplink, answered on `glyf://phantom/trade/<id>`.
  Future<Uint8List> signSolana(Uint8List tx) async {
    final wallet = WalletFlow.link.value;
    if (wallet != null && wallet.viaMwa) {
      try {
        return await WalletFlow.mwa.sign(tx);
      } on MwaException catch (e) {
        throw SignFailed(e.cancelled ? 'Cancelled in the wallet' : 'The wallet couldn’t sign it',
            detail: e.cancelled ? 'Nothing was sent' : e.message, cancelled: e.cancelled);
      }
    }
    final id = PhantomRequests.newId();
    final Uri url;
    try {
      url = await WalletFlow.phantom.signUrl(tx, id, step: PhantomRequests.step);
    } on PhantomError catch (e) {
      throw SignFailed(e.message);
    }
    final Uri reply;
    try {
      reply = await PhantomRequests.ask(id, () async {
        final failed = await WalletFlow.openPhantom(url);
        // No Phantom on a simulator: with `--glyf-test-phantom` (never in a
        // release build) qa/fake-phantom.mjs answers the logged link.
        return failed != null && !kReleaseMode && (await GlyfBridge.launchArgs()).contains('--glyf-test-phantom')
            ? null
            : failed;
      });
    } on PhantomUnavailable catch (e) {
      throw SignFailed(e.message);
    } on TimeoutException {
      throw SignFailed('Phantom didn’t answer', detail: 'Nothing was sent. Try again');
    }
    try {
      return await WalletFlow.phantom.finishSign(reply);
    } on PhantomError catch (e) {
      if (e.cancelled) throw SignFailed('Cancelled in Phantom', detail: 'Nothing was sent', cancelled: true);
      throw SignFailed('Phantom couldn’t sign it', detail: e.message);
    }
  }

  Future<String> sendSolana(Uint8List signed) => SolanaRpc.send(signed);

  /// True when it landed, false when Solana refused it, null when unknown yet.
  Future<bool?> confirmSolana(String signature) => SolanaRpc.confirm(signature);
}

/// Swaps and sends across chains through NEAR Intents (docs/NEAR-SPEC.md):
/// Glyf's server asks 1Click for a live quote with a deposit address; the
/// person's own wallet pays that address (MetaMask on an EVM chain, Phantom
/// on Solana, any wallet by hand elsewhere); NEAR Intents' solvers deliver
/// on the other chain, and this follows it until it lands or is refunded.
/// Refunds go back to the person's own address on the chain they paid from.
/// Glyf holds no key: it builds the deposit from the quote's address and
/// amount itself, and checks what the wallet signed.
abstract final class NearFlow {
  @visibleForTesting
  static NearApi api = const NearApi();
  @visibleForTesting
  static NearWallet wallet = const NearWallet();

  /// How often GET /near/status is asked, and when to stop asking.
  @visibleForTesting
  static Duration pollEvery = const Duration(seconds: 3);
  @visibleForTesting
  static Duration giveUpAfter = const Duration(minutes: 10);

  /// How many earlier recipients are kept for Guard (shared settings `nearRecent`).
  static const keepRecent = 20;

  static const venue = 'NEAR Intents';

  /// Chains other than the EVM ones and Solana, as people say them.
  static const _labels = {
    'solana': 'Solana',
    'near': 'NEAR',
    'bitcoin': 'Bitcoin',
    'zcash': 'Zcash',
    'ton': 'TON',
    'tron': 'Tron',
    'xrp': 'XRP',
    'dogecoin': 'Dogecoin',
    'litecoin': 'Litecoin',
    'sui': 'Sui',
    'aptos': 'Aptos',
    'stellar': 'Stellar',
    'cardano': 'Cardano',
    'bsc': 'BNB Chain',
    'avalanche': 'Avalanche',
    'gnosis': 'Gnosis',
  };

  /// EVM chains MetaMask can pay from here; their deposit is signed there.
  static bool _isEvm(String chain) => EvmChain.named(chain) != null || const {'bsc', 'avalanche', 'gnosis'}.contains(chain);

  static String chainLabel(String chain) => EvmChain.named(chain)?.label ?? _labels[chain] ?? chain;

  static String short(String a) => a.length <= 16 || a.endsWith('.near') ? a : '${a.substring(0, 6)}…${a.substring(a.length - 4)}';

  static Stream<TradeOutcome> run(Map<String, String> q) async* {
    final kind = q['kind'] ?? 'swap';
    if (!const {'swap', 'send', 'bridge'}.contains(kind)) {
      yield const TradeOutcome(TradeState.failed, 'NEAR Intents swaps and sends only',
          detail: 'Orders that wait on a price go through Flash');
      return;
    }
    final send = kind == 'send' || q['exact'] == 'out';
    final sellChain = (q['chain'] ?? 'base').toLowerCase();
    final sell = (q['sell'] ?? (send ? 'USDC' : '')).toUpperCase();
    final buy = (q['buy'] ?? (send ? sell : '')).toUpperCase();
    final buyChain = (q['buyChain'] ?? sellChain).toLowerCase();
    final amount = q['amount'];
    if (sell.isEmpty || buy.isEmpty) {
      yield const TradeOutcome(TradeState.failed, 'Swap what for what?', detail: 'Say both coins, like “swap 20 usdc on base to sol”');
      return;
    }
    if (amount == null || (double.tryParse(amount) ?? 0) <= 0) {
      yield TradeOutcome(TradeState.failed, 'How much?',
          detail: send ? 'Say an amount, like “send 5 usdc to alice.near”' : 'Say an amount, like “swap 20 usdc on base to sol”');
      return;
    }
    final settings = await GlyfBridge.sharedSettings();

    // Who the person is on each side: refunds go back to their own address
    // on the chain they pay from; a swap lands in their own wallet unless
    // they typed someone else's.
    final evm = _isEvm(sellChain) || _isEvm(buyChain) ? await wallet.evmAddress() : null;
    final sol = sellChain == 'solana' || buyChain == 'solana' ? await wallet.solanaAddress() : null;
    final nearAccount = (settings['nearAccount'] as String?)?.trim();
    String? own(String chain) => _isEvm(chain)
        ? evm
        : chain == 'solana'
            ? sol
            : chain == 'near' && nearAccount != null && nearAccount.isNotEmpty
                ? nearAccount
                : null;

    final refundTo = q['refundTo'] ?? own(sellChain);
    if (refundTo == null) {
      yield TradeOutcome(TradeState.failed, switch (sellChain) {
        'solana' => 'Phantom isn’t connected',
        _ when _isEvm(sellChain) => 'MetaMask isn’t connected',
        _ => 'Where should a refund go?',
      },
          detail: switch (sellChain) {
            'solana' => 'Connect Phantom in Profile › Wallet',
            _ when _isEvm(sellChain) => EvmSigner.missing,
            _ => 'Glyf needs your own ${chainLabel(sellChain)} address in case NEAR Intents can’t fill it',
          });
      return;
    }
    final typed = q['to']?.trim();
    final recipient = typed != null && typed.isNotEmpty ? typed : own(buyChain);
    if (recipient == null) {
      final where = chainLabel(buyChain);
      yield TradeOutcome(TradeState.failed, 'Who gets the $buy?',
          detail: buyChain == 'near'
              ? 'Add your NEAR account, like “to alice.near”'
              : _isEvm(buyChain)
                  ? 'Connect MetaMask in Profile › Wallet, or add an address with “to”'
                  : buyChain == 'solana'
                      ? 'Connect Phantom in Profile › Wallet, or add an address with “to”'
                      : 'Add a $where address, like “to ${buyChain == 'bitcoin' ? 'bc1q…' : '…'}”');
      return;
    }
    final mine = recipient == own(buyChain);
    final who = mine ? 'your wallet' : short(recipient);

    // 1. The live quote, with the deposit address and Guard's checks.
    yield const NearOutcome(TradeState.working, 'Asking NEAR Intents…');
    final recent = <String>{
      for (final a in [evm, sol, nearAccount, ...((settings['nearRecent'] as List?) ?? const []).whereType<String>()])
        if (a != null && a.isNotEmpty) a,
    }.toList();
    final quote = await api.quote({
      'sell': sell,
      'sellChain': sellChain,
      'buy': buy,
      'buyChain': buyChain,
      'amount': amount,
      'exact': send ? 'out' : 'in',
      'refundTo': refundTo,
      'recipient': recipient,
      'slippage': double.tryParse(q['slippage'] ?? '') ?? 1,
      'recent': recent,
      if (settings['dailyLimitUsd'] is num) 'dailyLimitUsd': settings['dailyLimitUsd'],
      if (settings['spentTodayUsd'] is num) 'spentTodayUsd': settings['spentTodayUsd'],
    });
    NearOutcome step(TradeState state, String title,
            {String? detail, String? txUrl, String? reopen, String? hash, bool manual = false, bool blocked = false}) =>
        NearOutcome(state, title,
            detail: detail,
            txUrl: txUrl,
            reopen: reopen,
            hash: hash,
            quote: quote,
            recipient: who,
            explorer: quote.explorer,
            manual: manual,
            blocked: blocked);

    // Guard first: a recipient that can't be paid (no such .near account, an
    // address from another chain) comes back as a preview with no deposit
    // address, and that is Guard's reason, never "no deposit address". Only
    // a live quote can go ahead anyway.
    if (quote.blocked && (q['anyway'] != '1' || quote.dry)) {
      final check = quote.checks.firstWhere((c) => c.level == 'block', orElse: () => const NearCheck('', 'block', ''));
      yield step(TradeState.failed, check.text.isEmpty ? 'Guard stopped this one' : check.text,
          detail: quote.dry ? 'Nothing was sent. Check the ${check.id == 'no-account' ? 'name' : 'address'}' : 'Nothing was sent',
          blocked: !quote.dry);
      return;
    }
    final problem = quoteProblem(quote,
        sell: sell, sellChain: sellChain, buy: buy, buyChain: buyChain, amount: amount, exactIn: !send);
    if (problem != null) {
      yield step(TradeState.failed, problem, detail: 'Nothing was sent');
      return;
    }
    final depositAddress = quote.depositAddress!;
    final memo = quote.depositMemo;
    final deposit = quote.deposit!;
    final paid = '${_fmt(quote.amountIn)} $sell';
    final label = 'Send $paid to $venue';

    // 2. The deposit, from the person's own wallet.
    String? depositTx;
    final evmChain = EvmChain.named(sellChain);
    final signable = switch (deposit.kind) {
      'erc20' || 'native' => evmChain != null && (deposit.chainId == null || deposit.chainId == evmChain.id),
      'sol' || 'spl' => sellChain == 'solana' && sol != null,
      _ => false,
    };
    if (!signable) {
      // Bitcoin, Zcash, NEAR…: paid from any wallet, then followed here.
      await _remember(recipient, mine: mine);
      yield step(TradeState.working, 'Send from any wallet',
          detail: '$paid on ${chainLabel(sellChain)} to the address below', manual: true);
    } else if (deposit.kind == 'erc20' || deposit.kind == 'native') {
      final call = depositCall(quote, evmChain!);
      if (call == null) {
        yield step(TradeState.failed, 'That deposit doesn’t add up', detail: 'Nothing was sent');
        return;
      }
      late List<Signed> signed;
      await for (final e in wallet.signEvm(label, [TxStep(evmChain, label, call, failTitle: 'The deposit reverted')])) {
        if (e.results != null) {
          signed = e.results!;
        } else {
          yield step(TradeState.working, e.label!, reopen: e.reopen);
        }
      }
      depositTx = signed.single.hash;
      await _remember(recipient, mine: mine);
      yield step(TradeState.working, 'Deposit sent',
          detail: '$paid on ${evmChain.label}', txUrl: depositTx == null ? null : evmChain.txUrl(depositTx), hash: depositTx);
    } else {
      final from = sol!;
      final tx = depositTransaction(quote, from: from, blockhash: await wallet.solanaBlockhash());
      if (tx == null) {
        yield step(TradeState.failed, 'That deposit doesn’t add up', detail: 'Nothing was sent');
        return;
      }
      yield step(TradeState.working, '$label: approve in ${wallet.solanaName}');
      final signed = await wallet.signSolana(tx);
      if (!FlashSvm.isSignedSetup(signed, tx, from)) {
        throw SignFailed('That isn’t what Glyf asked ${wallet.solanaName} to sign', detail: 'Nothing was sent');
      }
      yield step(TradeState.working, 'Sending to Solana…');
      depositTx = await wallet.sendSolana(signed);
      bool? landed;
      try {
        landed = await wallet.confirmSolana(depositTx);
      } catch (_) {
        // No node to ask: NEAR Intents says when it sees the deposit.
      }
      if (landed == false) {
        throw SignFailed('The deposit didn’t go through', detail: 'Solana turned it down. Nothing was sent', hash: depositTx);
      }
      await _remember(recipient, mine: mine);
      yield step(TradeState.working, 'Deposit sent',
          detail: '$paid on Solana', txUrl: WalletFlow.solscanUrl(depositTx), hash: depositTx);
    }

    // 3. Told to 1Click, then followed until it lands.
    if (depositTx != null) {
      try {
        await api.submit(depositAddress: depositAddress, txHash: depositTx, memo: memo);
      } catch (_) {
        // Only a speed-up: 1Click finds the deposit on its own.
      }
    }
    final got = '$buy on ${chainLabel(buyChain)}';
    final end = DateTime.now().add(giveUpAfter);
    String? shown;
    while (true) {
      NearStatus? status;
      try {
        status = await api.status(depositAddress: depositAddress, memo: memo);
      } catch (_) {
        // A dropped answer: ask again.
      }
      final explorer = status?.explorer ?? quote.explorer;
      final out = _fmt(status?.amountOut ?? quote.amountOut);
      final originUrl = depositTx == null
          ? null
          : evmChain != null
              ? evmChain.txUrl(depositTx)
              : WalletFlow.solscanUrl(depositTx);
      switch (status?.status) {
        case 'SUCCESS':
          yield NearOutcome(TradeState.done, send ? 'Sent' : 'Swapped',
              detail: send ? '$out $buy to $who on ${chainLabel(buyChain)}' : '$paid on ${chainLabel(sellChain)} → $out $got',
              txUrl: status!.destinationTx?.url ?? explorer,
              hash: status.destinationTx?.hash ?? depositTx,
              quote: quote,
              recipient: who,
              explorer: explorer);
          return;
        case 'REFUNDED':
          yield NearOutcome(TradeState.failed, 'Refunded',
              detail: '$venue couldn’t fill it, so $paid went back to ${short(refundTo)}',
              txUrl: explorer, quote: quote, recipient: who, explorer: explorer);
          return;
        case 'FAILED':
          yield NearOutcome(TradeState.failed, 'That didn’t go through',
              detail: '$venue is refunding $paid to ${short(refundTo)}',
              txUrl: explorer, quote: quote, recipient: who, explorer: explorer);
          return;
      }
      if (DateTime.now().isAfter(end)) {
        yield NearOutcome(TradeState.submitted, depositTx == null ? 'No deposit yet' : 'Still on its way',
            detail: depositTx == null
                ? 'Send $paid to the address and $venue picks it up'
                : '$venue hasn’t finished yet. Follow it on its explorer',
            txUrl: explorer ?? originUrl,
            quote: quote,
            recipient: who,
            explorer: explorer,
            manual: depositTx == null);
        return;
      }
      final line = switch (status?.status) {
        'PROCESSING' || 'KNOWN_DEPOSIT_TX' => 'Swapping on $venue',
        'INCOMPLETE_DEPOSIT' => 'Deposit seen, but short',
        _ => null,
      };
      if (line != null && line != shown) {
        shown = line;
        final secs = quote.timeSeconds;
        yield step(TradeState.working, line,
            detail: line == 'Deposit seen, but short'
                ? 'Send the rest of $paid to the same address, or $venue refunds it'
                : 'Deposit seen · $out $got${secs == null ? '' : ' in about $secs s'}',
            txUrl: originUrl,
            hash: depositTx,
            manual: depositTx == null && line == 'Deposit seen, but short');
      }
      await Future<void>.delayed(pollEvery);
    }
  }

  /// Why [quote] isn't the trade asked for, or null when it is: the coins
  /// and chains asked for, a deposit to make, and for a swap the amount.
  @visibleForTesting
  static String? quoteProblem(NearQuote quote,
      {required String sell,
      required String sellChain,
      required String buy,
      required String buyChain,
      required String amount,
      required bool exactIn}) {
    if (quote.dry || quote.depositAddress == null || quote.deposit == null) return '$venue gave no deposit address';
    if (quote.sell.symbol.toUpperCase() != sell || quote.buy.symbol.toUpperCase() != buy ||
        quote.sell.chain.toLowerCase() != sellChain || quote.buy.chain.toLowerCase() != buyChain) {
      return 'That quote isn’t for this trade';
    }
    final d = quote.deposit!;
    if (d.depositAddress != null && d.depositAddress != quote.depositAddress) return 'That quote isn’t for this trade';
    if (exactIn && quote.amountInBase != null && quote.sell.decimals > 0) {
      final asked = Sol.units(amount, quote.sell.decimals);
      if (BigInt.tryParse(quote.amountInBase!) != asked) return 'That quote isn’t for $amount $sell';
    }
    return null;
  }

  /// The amount to deposit, in the sell coin's smallest units.
  static BigInt? _base(NearQuote quote, String? own) => BigInt.tryParse(own ?? quote.amountInBase ?? '');

  /// The deposit on an EVM chain, built here from the quote's address and
  /// amount: the token's ERC-20 transfer to the deposit address, or the
  /// chain's coin sent to it. Null when the quote's pieces don't agree.
  @visibleForTesting
  static EvmCall? depositCall(NearQuote quote, EvmChain chain) {
    final d = quote.deposit!;
    final to = quote.depositAddress!;
    final amount = _base(quote, d.amountBase ?? (d.kind == 'native' ? d.value : null));
    if (amount == null || amount <= BigInt.zero || !RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(to)) return null;
    if (quote.amountInBase != null && BigInt.tryParse(quote.amountInBase!) != amount) return null;
    if (d.kind == 'native') return EvmCall(to: to, value: amount);
    final token = d.token ?? d.to ?? quote.sell.address;
    if (token == null || !RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(token)) return null;
    if (quote.sell.address != null && quote.sell.address!.toLowerCase() != token.toLowerCase()) return null;
    return EvmCall(to: token, data: TradeFlow.erc20Transfer(to, amount));
  }

  /// The deposit on Solana, built here: SOL to the deposit address, or the
  /// token's TransferChecked to its token account. Null when the quote's
  /// pieces don't agree.
  @visibleForTesting
  static Uint8List? depositTransaction(NearQuote quote, {required String from, required String blockhash}) {
    final d = quote.deposit!;
    final to = quote.depositAddress!;
    if (!Sol.isAddress(to) || (d.to != null && d.to != to)) return null;
    if (d.kind == 'sol') {
      final lamports = _base(quote, d.lamports ?? d.amountBase);
      if (lamports == null || lamports <= BigInt.zero) return null;
      if (quote.amountInBase != null && BigInt.tryParse(quote.amountInBase!) != lamports) return null;
      return Sol.transferSol(from: from, to: to, lamports: lamports, blockhash: blockhash);
    }
    final mint = d.mint ?? quote.sell.address;
    final amount = _base(quote, d.amountBase);
    if (mint == null || !Sol.isAddress(mint) || amount == null || amount <= BigInt.zero) return null;
    if (quote.sell.address != null && quote.sell.address != mint) return null;
    if (quote.amountInBase != null && BigInt.tryParse(quote.amountInBase!) != amount) return null;
    return Sol.transferToken(
        from: from, to: to, mint: mint, amount: amount, decimals: d.decimals ?? quote.sell.decimals, blockhash: blockhash);
  }

  /// Someone paid through NEAR Intents, kept for Guard's lookalike check
  /// next time (newest first, the last [keepRecent]). The person's own
  /// wallets go with every quote anyway.
  static Future<void> _remember(String recipient, {required bool mine}) async {
    if (mine) return;
    try {
      await GlyfBridge.updateSharedSettings((s) {
        final was = ((s['nearRecent'] as List?) ?? const []).whereType<String>().where((a) => a != recipient);
        s['nearRecent'] = [recipient, ...was].take(keepRecent).toList();
        return s;
      });
    } catch (_) {
      // A recipient not kept is only one Guard check fewer next time.
    }
  }

  static String _fmt(String v) {
    final d = double.tryParse(v);
    if (d == null) return v;
    var s = d.toStringAsFixed(d >= 1000 ? 2 : d >= 1 ? 4 : 6);
    while (s.contains('.') && (s.endsWith('0') || s.endsWith('.'))) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }
}
