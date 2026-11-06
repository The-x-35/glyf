import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/evm/trade_flow.dart';
import 'package:glyf/evm/trade_screen.dart';
import 'package:glyf/evm/trade_share.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const bridge = MethodChannel('so.glyf/bridge');
  late Map<String, dynamic> shared;

  setUp(() {
    shared = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(bridge, (call) async {
      final args = (call.arguments as Map?)?.cast<String, Object?>() ?? const {};
      switch (call.method) {
        case 'readSharedSettings':
          return jsonEncode(shared);
        case 'writeSharedSettings':
          shared = jsonDecode(args['json'] as String) as Map<String, dynamic>;
          return true;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(bridge, null);
  });

  test('a trade in one line, done or about to be copied', () {
    const buy = {'kind': 'swap', 'sell': 'USDC', 'buy': 'ETH', 'amount': '50', 'usd': '1', 'chain': 'base'};
    expect(TradeShare.describe(buy, past: true), 'Bought \$50 of ETH on Base');
    expect(TradeShare.describe(buy, past: false), 'Buy \$50 of ETH on Base');
    expect(TradeShare.describe({'kind': 'swap', 'sell': 'ETH', 'buy': 'USDC', 'amount': '0.05', 'chain': 'base'}, past: true),
        'Swapped 0.05 ETH for USDC on Base');
    expect(TradeShare.describe({'kind': 'stop-loss', 'sell': 'ETH', 'buy': 'USDC', 'price': '3000', 'chain': 'arbitrum'},
            past: true),
        'Set a stop-loss on ETH at \$3000 on Arbitrum');
    expect(TradeShare.describe({'kind': 'limit', 'sell': 'USDC', 'buy': 'ETH', 'amount': '100', 'price': '2800', 'chain': 'base'},
            past: false),
        'Place a limit buy for ETH at \$2800 on Base');
    expect(TradeShare.describe({'kind': 'bridge', 'sell': 'ETH', 'buy': 'ETH', 'amount': '0.1', 'chain': 'base', 'toChain': 'arbitrum'},
            past: true),
        'Moved 0.1 ETH from Base to Arbitrum');
  });

  test('a share carries the trade, never a recipient, and where to see it', () {
    final body = TradeShare.body(
      {'kind': 'swap', 'sell': 'USDC', 'buy': 'ETH', 'amount': '50', 'usd': '1', 'chain': 'base', 'copied': '1', 'to': 'sam.eth'},
      TradeOutcome(TradeState.done, 'Swapped', hash: '0x${'ab' * 32}'),
    );
    expect(body['query'], {'kind': 'swap', 'sell': 'USDC', 'buy': 'ETH', 'amount': '50', 'usd': '1', 'chain': 'base'});
    expect(body['summary'], 'Bought \$50 of ETH on Base');
    expect(body['chainId'], 8453);
    expect(body['txHash'], '0x${'ab' * 32}');
    expect(body.containsKey('orderId'), isFalse);
    expect(TradeShare.shareable({'kind': 'send'}), isFalse);
    expect(TradeShare.shareable({'kind': 'request'}), isFalse);
    expect(TradeShare.shareable({'kind': 'twap'}), isTrue);
  });

  test('the chat line is left for the keyboard with when it was made', () async {
    await TradeShare.handToKeyboard('Bought \$50 of ETH on Base with Glyf. Copy my trade: https://x/t/abc');
    final share = jsonDecode(shared['tradeShare'] as String) as Map<String, dynamic>;
    expect(share['text'], contains('Copy my trade'));
    expect((share['at'] as num) * 1000, closeTo(DateTime.now().millisecondsSinceEpoch, 5000));
  });

  testWidgets('a copied trade waits for a tap, then quotes and signs as usual, and can be shared', (tester) async {
    var runs = 0;
    Stream<TradeOutcome> run(Map<String, String> q) async* {
      runs++;
      yield TradeOutcome(TradeState.done, 'Swapped', detail: '50 USDC → 0.0125 ETH on Base', hash: '0x${'ab' * 32}');
    }

    await tester.pumpWidget(MaterialApp(
      home: TradeScreen(
        query: const {'kind': 'swap', 'sell': 'USDC', 'buy': 'ETH', 'amount': '50', 'usd': '1', 'chain': 'base', 'copied': '1'},
        run: run,
      ),
    ));
    await tester.pump();
    expect(find.text('Buy \$50 of ETH on Base'), findsOneWidget);
    expect(find.text('Copy this trade'), findsNWidgets(2)); // the title and the button
    expect(runs, 0);

    await tester.tap(find.widgetWithText(FilledButton, 'Copy this trade'));
    await tester.pumpAndSettle();
    expect(runs, 1);
    expect(find.text('Swapped'), findsOneWidget);
    expect(find.text('Share in chat'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('a copied send is refused', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: TradeScreen(
        query: const {'kind': 'send', 'sell': 'USDC', 'amount': '50', 'address': '0x0000000000000000000000000000000000000001', 'copied': '1'},
        run: (_) => throw StateError('never runs'),
      ),
    ));
    await tester.pump();
    expect(find.text('Only trades can be copied'), findsOneWidget);
    expect(find.text('Share in chat'), findsNothing);
  });
}
