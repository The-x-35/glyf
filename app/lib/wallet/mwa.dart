import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:solana_mobile_client/solana_mobile_client.dart';

import 'base58.dart';
import 'phantom.dart' show SecretStore;

/// Mobile Wallet Adapter: the wallet standard Android and the Seeker speak.
/// The wallet app (Seed Vault on a Seeker, Phantom elsewhere) connects back
/// to a local association server and signs there, in one round trip, with
/// no deeplink reply to wait for. Glyf never touches a key.
///
/// The one rule that matters (learned the hard way): `startActivityForResult`
/// only completes when the wallet RETURNS, and `scenario.start()` is what
/// boots the server the wallet connects TO. Launch first, never awaited,
/// then start. Awaiting the launch strands the wallet and the OS kills us.
class MwaException implements Exception {
  const MwaException(this.message, {this.cancelled = false});
  final String message;
  final bool cancelled;
  @override
  String toString() => message;
}

class MwaAccount {
  const MwaAccount({required this.address, required this.authToken});
  final String address;
  final String authToken;
}

class Mwa {
  Mwa(this._secrets);

  final SecretStore _secrets;
  static const _name = 'mwa-auth';

  static final _identity = Uri.parse('https://www.tryglyf.com');
  static final _icon = Uri.parse('icon.png');
  static const _appName = 'Glyf';
  static const _cluster = 'mainnet-beta';

  MwaAccount? _account;
  MwaAccount? get account => _account;

  /// Whether any MWA wallet is installed. False everywhere but Android.
  static Future<bool> isAvailable() async {
    if (!Platform.isAndroid) return false;
    try {
      return await LocalAssociationScenario.isAvailable();
    } catch (_) {
      return false;
    }
  }

  Future<MwaAccount?> load() async {
    if (!Platform.isAndroid) return null;
    try {
      final raw = await _secrets.load(_name);
      if (raw == null) return null;
      final json = jsonDecode(raw) as Map;
      final address = json['address'];
      final token = json['authToken'];
      if (address is! String || token is! String) return null;
      return _account = MwaAccount(address: address, authToken: token);
    } catch (_) {
      return null;
    }
  }

  /// One wallet popup; the address, or null when the person backs out.
  Future<MwaAccount?> connect() async {
    final result = await _scenario((client) => client.authorize(
          identityUri: _identity,
          iconUri: _icon,
          identityName: _appName,
          cluster: _cluster,
        ));
    if (result == null) return null; // cancelled in the wallet
    return _remember(result);
  }

  /// Signs one transaction. The wallet pops only for the signature; a stale
  /// session re-authorizes first (one extra popup, not a failure).
  Future<Uint8List> sign(Uint8List transaction) async {
    final signed = await _scenario((client) async {
      var token = _account?.authToken;
      if (token != null) {
        try {
          final renewed = await client.reauthorize(
            identityUri: _identity,
            iconUri: _icon,
            identityName: _appName,
            authToken: token,
          );
          if (renewed != null) await _remember(renewed);
          if (renewed == null) token = null;
        } catch (_) {
          token = null;
        }
      }
      if (token == null) {
        final fresh = await client.authorize(
          identityUri: _identity,
          iconUri: _icon,
          identityName: _appName,
          cluster: _cluster,
        );
        if (fresh == null) return null;
        await _remember(fresh);
      }
      final result = await client.signTransactions(transactions: [transaction]);
      return result.signedPayloads.isEmpty ? null : result.signedPayloads.first;
    });
    if (signed == null) throw const MwaException('Cancelled in the wallet', cancelled: true);
    return signed;
  }

  Future<void> disconnect() async {
    final token = _account?.authToken;
    _account = null;
    await _secrets.clear(_name);
    if (token == null) return;
    try {
      // Best effort: the phone forgets the session either way.
      await _scenario((client) => client.deauthorize(authToken: token));
    } catch (_) {}
  }

  Future<MwaAccount> _remember(AuthorizationResult result) async {
    final account = MwaAccount(
      address: Base58.encode(result.publicKey),
      authToken: result.authToken,
    );
    _account = account;
    await _secrets.save(_name, jsonEncode({'address': account.address, 'authToken': account.authToken}));
    return account;
  }

  /// create → launch (NOT awaited) → start → [body] → close.
  Future<T?> _scenario<T>(Future<T?> Function(MobileWalletAdapterClient client) body) async {
    if (!Platform.isAndroid) throw const MwaException('Only on Android');
    final scenario = await LocalAssociationScenario.create();
    unawaited(scenario.startActivityForResult(null));
    try {
      final client = await scenario.start();
      return await body(client);
    } finally {
      await scenario.close();
    }
  }
}
