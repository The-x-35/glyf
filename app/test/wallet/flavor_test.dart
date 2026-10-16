import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/core/flavor.dart';
import 'package:glyf/wallet/wallet_api.dart';

/// The store flavors (docs/SOLANA-DAPP-STORE.md): the dApp Store build
/// buys no tokenized stocks, so Jupiter's stock tags must be read.
void main() {
  test('Jupiter tags mark a tokenized stock', () {
    final aapl = TokenInfo.fromJson({
      'id': 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp',
      'symbol': 'AAPLx',
      'name': 'Apple xStock',
      'decimals': 8,
      'tags': ['verified', 'xstocks'],
    })!;
    expect(aapl.stock, isTrue);
    for (final tag in ['stocks', 'equities']) {
      expect(TokenInfo.fromJson({'id': 'm', 'symbol': 'X', 'decimals': 6, 'tags': [tag]})!.stock, isTrue);
    }
    final bonk = TokenInfo.fromJson({
      'id': 'DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263',
      'symbol': 'Bonk',
      'decimals': 5,
      'tags': ['verified', 'community'],
    })!;
    expect(bonk.stock, isFalse);
    expect(TokenInfo.fromJson({'id': 'm', 'symbol': 'X', 'decimals': 6})!.stock, isFalse);
  });

  test('a build with no flavor (tests, the iPhone) is neither store and buys stocks', () {
    expect(Flavor.dappStore, isFalse);
    expect(Flavor.play, isFalse);
    expect(Flavor.stockBuys, isTrue);
  });
}
