import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/wallet/wallet_api.dart';

/// Glyf's 0.5% on a buy (docs/SWAP-FEE.md): Jupiter's referral fee, sent
/// only when a referral account is set.
void main() {
  const sol = 'So11111111111111111111111111111111111111112';
  const bonk = 'DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263';
  const referral = '18LeLp3B8yGctKtWKAXXqdB6Lf1GxmEa2fRL5xxa1ta';

  test('ships off: no referral account, so /order is asked as before', () {
    expect(SwapFee.referralAccount, isEmpty);
    expect(SwapFee.params(), isEmpty);
    final uri = Jupiter.orderUri(inputMint: sol, outputMint: bonk, amount: BigInt.from(100000000));
    expect(uri.queryParameters, {'inputMint': sol, 'outputMint': bonk, 'amount': '100000000'});
  });

  test('a referral account adds referralAccount and a 50 bps referralFee', () {
    final uri = Jupiter.orderUri(
      inputMint: sol,
      outputMint: bonk,
      amount: BigInt.from(100000000),
      taker: '7dHbWXmci3dT8UFYWYZweBLXgycu7Y3iL6trKn1Y7ARj',
      referral: referral,
    );
    expect(uri.path, '/swap/v2/order');
    expect(uri.queryParameters['referralAccount'], referral);
    expect(uri.queryParameters['referralFee'], '50');
    expect(uri.queryParameters['taker'], '7dHbWXmci3dT8UFYWYZweBLXgycu7Y3iL6trKn1Y7ARj');
  });

  test('the fee sits inside Jupiter\'s 50 to 255 bps', () {
    expect(SwapFee.bps, inInclusiveRange(50, 255));
  });

  test('the fee shows only when Jupiter applied the referral', () {
    // Recorded from /swap/v2/order, 2026-10-14.
    expect(SwapFee.applied({'feeBps': 10, 'feeMint': sol}), isNull);
    expect(SwapFee.applied({'feeBps': 50, 'feeMint': sol, 'referralAccount': referral}), 50);
    expect(SwapFee.applied({'referralAccount': referral}), 50);
  });

  test('labels', () {
    expect(SwapFee.label(50), 'Fee 0.5%');
    expect(SwapFee.label(100), 'Fee 1%');
    expect(SwapFee.label(255), 'Fee 2.55%');
  });
}
