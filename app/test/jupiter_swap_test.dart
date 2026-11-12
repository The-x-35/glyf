import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/evm/trade_flow.dart';
import 'package:glyf/wallet/wallet_flow.dart';

/// A Solana swap runs through Jupiter (the wallet's buy); its steps read as
/// the trade screen's.
void main() {
  test('Jupiter steps map onto trade outcomes, with Solscan links', () {
    final done = TradeFlow.jupiterOutcome(const PayOutcome(state: PayState.done, title: 'Swapped', signature: 'abc'));
    expect(done.state, TradeState.done);
    expect(done.txUrl, 'https://solscan.io/tx/abc');
    expect(done.hash, 'abc');
    expect(TradeFlow.jupiterOutcome(const PayOutcome(state: PayState.working, title: 'Sending…')).state, TradeState.working);
    expect(TradeFlow.jupiterOutcome(const PayOutcome(state: PayState.submitted, title: 'Sent')).state, TradeState.submitted);
    final no = TradeFlow.jupiterOutcome(const PayOutcome(state: PayState.cancelled, title: 'Not sent'));
    expect(no.state, TradeState.failed);
    expect(no.txUrl, isNull);
  });
}
