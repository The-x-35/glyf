import 'package:flutter/services.dart' show appFlavor;

/// Which store this Android build is for (the Gradle product flavor:
/// `--flavor play` or `--flavor dappStore`, docs/SOLANA-DAPP-STORE.md).
/// The iPhone build has no flavor, so it reads as neither.
abstract final class Flavor {
  /// The Solana dApp Store build.
  static bool get dappStore => appFlavor == 'dappStore';

  /// The Google Play build.
  static bool get play => appFlavor == 'play';

  /// Tokenized stocks (xStocks, Ondo) may be bought here. Not in the dApp
  /// Store build: its Publisher Policy counts them as regulated financial
  /// services. The price still shows; only Buy goes.
  static bool get stockBuys => !dappStore;

  /// The hackathon build (ETHGlobal Mumbai): `--dart-define=GLYF_ZEROG=true`.
  /// Its AI runs on 0G's Private Computer by default, with a switch for it
  /// in Keyboard and in Build your own. Every other build has neither and
  /// keeps the usual AI: 0G is for testing only.
  static const zeroG = bool.fromEnvironment('GLYF_ZEROG');
}
