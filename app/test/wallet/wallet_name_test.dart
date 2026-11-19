import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/wallet/wallet_flow.dart';

// On a Seeker (any phone with a Mobile Wallet Adapter wallet) the connect and
// pay screens name the phone's own wallet, not Phantom.
void main() {
  test('a phone with an MWA wallet names it, not Phantom', () {
    expect(WalletFlow.walletNameFor(mwaHere: true), 'your wallet');
  });

  test('without one, Phantom signs', () {
    expect(WalletFlow.walletNameFor(mwaHere: false), 'Phantom');
  });
}
