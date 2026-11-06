import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/evm/trade_activity.dart';
import 'package:glyf/evm/trade_flow.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a trade step goes to the Live Activity with its query and nothing it does not have', () {
    const q = {'kind': 'stop-loss', 'sell': 'SOL', 'buy': 'USDC', 'amount': '2', 'price': '172', 'chain': 'solana'};
    final waiting = TradeActivity.payload('t1', q,
        const TradeOutcome(TradeState.working, 'Sign the stop-loss in Phantom', reopen: 'https://phantom.app/x'));
    expect(waiting['id'], 't1');
    expect(waiting['query'], q);
    expect(waiting['state'], 'working');
    expect(waiting['reopen'], true);
    expect(waiting.containsKey('link'), false);
    expect(waiting.containsKey('orderId'), false);

    final placed = TradeActivity.payload('t1', q,
        const TradeOutcome(TradeState.done, 'Stop-loss set',
            detail: 'Sells 2 SOL at \$172', txUrl: 'https://app.definitive.fi/orders/abc', orderId: 'abc'));
    expect(placed['state'], 'done');
    expect(placed['link'], 'https://app.definitive.fi/orders/abc');
    expect(placed['orderId'], 'abc');
    expect(placed['detail'], 'Sells 2 SOL at \$172');
    expect(placed['reopen'], false);
  });

  test('showing a step never throws, even with no native side', () async {
    const q = {'kind': 'swap', 'sell': 'ETH', 'buy': 'USDC'};
    await TradeActivity.show(Object(), q, const TradeOutcome(TradeState.working, 'Asking Uniswap…'));
    await TradeActivity.cancelled('abc');
  });
}
