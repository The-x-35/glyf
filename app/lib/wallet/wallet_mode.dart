import 'package:flutter/foundation.dart';

import '../core/bridge.dart';

/// Which wallets sign, one switch for every chain (Profile › Keyboard ›
/// Sign with; shared settings `walletMode`). Arpit, 2026-11-06: "If the
/// user switched on the internal wallet, it should use the internal
/// wallet. If the user switched on the external wallet, it should go to
/// Phantom or MetaMask as needed based on the chain."
enum WalletMode {
  /// The Glyf wallet: Ethereum and Solana from its recovery phrase, signed here.
  internal('Glyf wallet'),

  /// Phantom for Solana, MetaMask for Ethereum and its L2s.
  external('Phantom & MetaMask');

  const WalletMode(this.label);
  final String label;

  /// Unset is the Glyf wallet.
  static WalletMode of(Object? name) => name == 'external' ? external : internal;
}

/// Who signs on a chain.
enum WalletSigner {
  glyf('Glyf wallet'),
  metamask('MetaMask'),
  phantom('Phantom');

  const WalletSigner(this.label);
  final String label;
}

/// Where a chain's trade goes: the signer, its address, or (when there is
/// none yet) one plain line saying how to get it.
class WalletRoute {
  const WalletRoute(this.signer, {this.address, this.missing});
  final WalletSigner signer;
  final String? address;
  final String? missing;

  bool get ready => address != null;
}

abstract final class WalletModes {
  static final mode = ValueNotifier<WalletMode>(WalletMode.internal);

  static Future<WalletMode> load() async {
    mode.value = fromSettings(await GlyfBridge.sharedSettings());
    return mode.value;
  }

  /// The saved switch; before there was one, a phone that had picked
  /// MetaMask to sign (evmSigner) keeps its outside wallets.
  static WalletMode fromSettings(Map<String, dynamic> s) =>
      s['walletMode'] != null ? WalletMode.of(s['walletMode']) : WalletMode.of(s['evmSigner'] == 'metamask' ? 'external' : null);

  /// Saves the switch where the keyboard reads it.
  static Future<void> set(WalletMode m) async {
    mode.value = m;
    await GlyfBridge.updateSharedSettings((s) {
      s['walletMode'] = m.name;
      return s;
    });
  }

  /// The routing rule, as a pure function: [solana] or an EVM chain, the
  /// switch, and what this phone has (the Glyf wallet's two addresses,
  /// connected MetaMask and Phantom).
  static WalletRoute route({
    required bool solana,
    required WalletMode mode,
    String? glyfEvm,
    String? glyfSolana,
    String? metamask,
    String? phantom,
  }) {
    if (mode == WalletMode.external) {
      return solana
          ? WalletRoute(WalletSigner.phantom,
              address: phantom, missing: phantom == null ? 'Connect Phantom in Profile › Wallet' : null)
          : WalletRoute(WalletSigner.metamask,
              address: metamask, missing: metamask == null ? 'Connect MetaMask in Profile › Wallet' : null);
    }
    if (!solana) {
      return WalletRoute(WalletSigner.glyf,
          address: glyfEvm, missing: glyfEvm == null ? 'Make your Glyf wallet in Profile › Wallet' : null);
    }
    return WalletRoute(WalletSigner.glyf,
        address: glyfSolana,
        missing: glyfSolana != null
            ? null
            : glyfEvm != null
                ? 'Make a recovery phrase in Profile › Wallet to use Solana'
                : 'Make your Glyf wallet in Profile › Wallet');
  }
}
