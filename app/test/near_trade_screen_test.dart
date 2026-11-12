import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/evm/trade_flow.dart';
import 'package:glyf/evm/trade_screen.dart';
import 'package:glyf/near/near_api.dart';
import 'package:glyf/near/near_flow.dart';
import 'package:qr_flutter/qr_flutter.dart';

NearQuote _quote({String sell = 'USDC', String sellChain = 'base', List<Map<String, String>> checks = const [], String? memo}) =>
    NearQuote.fromJson({
      'ok': true,
      'sell': {'symbol': sell, 'chain': sellChain, 'decimals': 6},
      'buy': {'symbol': 'SOL', 'chain': 'solana', 'decimals': 9},
      'amountIn': '20',
      'amountInUsd': '19.99',
      'amountOut': '0.2438',
      'amountOutUsd': '19.88',
      'timeSeconds': 32,
      'depositAddress': 'bc1qdeposit',
      'depositMemo': memo,
      'deposit': {'kind': 'manual', 'chain': sellChain},
      'explorer': 'https://explorer.near-intents.org/transactions/bc1qdeposit',
      'guard': {'level': checks.any((c) => c['level'] == 'block') ? 'block' : 'ok', 'checks': checks},
    });

/// The trade screen on a NEAR Intents trade, driven by the outcomes a test
/// hands it (NearFlow itself is covered in near_flow_test.dart).
void main() {
  Future<StreamController<TradeOutcome>> open(WidgetTester tester, {List<Map<String, String>>? asked}) async {
    final steps = StreamController<TradeOutcome>();
    await tester.pumpWidget(MaterialApp(
      home: TradeScreen(
        query: const {'kind': 'swap', 'venue': 'near'},
        run: (q) {
          asked?.add(q);
          // Asked again (Send anyway): a fresh run.
          return asked != null && asked.length > 1 ? const Stream<TradeOutcome>.empty() : steps.stream;
        },
      ),
    ));
    return steps;
  }

  testWidgets('the quote: You pay and You get with their chains, the time, via NEAR Intents', (tester) async {
    final steps = await open(tester);
    steps.add(NearOutcome(TradeState.working, 'Send 20 USDC to NEAR Intents: confirm in MetaMask',
        quote: _quote(), recipient: 'your wallet', reopen: 'metamask://'));
    await tester.pump();
    expect(find.text('You pay'), findsOneWidget);
    expect(find.text('20 USDC'), findsOneWidget);
    expect(find.text('Base'), findsOneWidget);
    expect(find.text('You get'), findsOneWidget);
    expect(find.text('≈ 0.2438 SOL'), findsOneWidget);
    expect(find.text('Solana'), findsOneWidget);
    expect(find.text('to your wallet'), findsOneWidget);
    expect(find.text('\$19.99'), findsOneWidget);
    expect(find.text('~32 s · via NEAR Intents'), findsOneWidget);
    expect(find.text('Open MetaMask'), findsOneWidget);
    unawaited(steps.close());
  });

  testWidgets('Guard’s warnings show on the quote; a block offers Send anyway, which asks again past it', (tester) async {
    final asked = <Map<String, String>>[];
    final steps = await open(tester, asked: asked);
    steps.add(NearOutcome(TradeState.failed, 'Looks like 0xAb12…9fE0 you paid before, but it isn’t',
        detail: 'Nothing was sent',
        blocked: true,
        quote: _quote(checks: [
          {'id': 'new-recipient', 'level': 'warn', 'text': 'You haven’t paid this address before'},
          {'id': 'lookalike', 'level': 'block', 'text': 'Looks like 0xAb12…9fE0 you paid before, but it isn’t'},
        ])));
    await tester.pump();
    expect(find.text('You haven’t paid this address before'), findsOneWidget);
    expect(find.text('Don’t send'), findsOneWidget);
    expect(find.text('Done'), findsNothing);
    await tester.tap(find.text('Send anyway'));
    await tester.pump();
    expect(asked, hasLength(2));
    expect(asked.last['anyway'], '1');
    expect(asked.last['venue'], 'near');
    unawaited(steps.close());
  });

  testWidgets('from a chain Glyf can’t sign on: a QR code and the amount, address and memo to copy', (tester) async {
    final steps = await open(tester);
    steps.add(NearOutcome(TradeState.working, 'Send from any wallet',
        detail: '20 BTC on Bitcoin to the address below',
        manual: true,
        quote: _quote(sell: 'BTC', sellChain: 'bitcoin', memo: '4821')));
    await tester.pump();
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('bc1qdeposit'), findsOneWidget);
    expect(find.text('20 BTC'), findsWidgets);
    expect(find.text('4821'), findsOneWidget);
    unawaited(steps.close());
  });

  testWidgets('done: the destination’s transaction and NEAR Intents’ explorer', (tester) async {
    final steps = await open(tester);
    steps.add(NearOutcome(TradeState.done, 'Swapped',
        detail: '20 USDC on Base → 0.2438 SOL on Solana',
        txUrl: 'https://solscan.io/tx/5Sig',
        explorer: 'https://explorer.near-intents.org/transactions/bc1qdeposit',
        quote: _quote()));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Swapped'), findsOneWidget);
    expect(find.text('View on Solscan'), findsOneWidget);
    expect(find.text('View on NEAR Intents'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    unawaited(steps.close());
  });
}
