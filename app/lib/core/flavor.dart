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

  /// 0G Private AI (ETHGlobal Mumbai): on in this version by default, with a
  /// switch in Keyboard and in Build your own. Builds already out (TestFlight)
  /// have none of this and send nothing, so they keep the usual AI; the server
  /// uses 0G only when it has ZEROG_API_KEY. Before this code goes into a
  /// release for everyone, decide this default (docs/DECISIONS.md D109).
  /// `--dart-define=GLYF_ZEROG=false` builds without it.
  static const zeroG = bool.fromEnvironment('GLYF_ZEROG', defaultValue: true);
}
