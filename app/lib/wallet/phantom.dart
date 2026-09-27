import 'dart:convert';

import 'package:pinenacl/x25519.dart';

import 'base58.dart';

/// Where the wallet link's secrets live: the Keychain on the iPhone, a
/// Keystore-sealed file on Android (see WalletSecrets in the bridge).
abstract class SecretStore {
  Future<String?> load(String name);
  Future<void> save(String name, String value);
  Future<void> clear(String name);
}

/// What stays on the phone after Connect. None of it can move money: the
/// wallet's address (public), Phantom's session for this app, and the
/// x25519 keys our messages to Phantom are sealed with.
class PhantomLink {
  const PhantomLink({required this.address, required this.session, required this.dappSecret, required this.phantomKey});

  final String address;
  final String session;
  final String dappSecret;
  final String phantomKey;

  Map<String, String> toJson() => {
    'address': address,
    'session': session,
    'dappSecret': dappSecret,
    'phantomKey': phantomKey,
  };

  static PhantomLink? fromJson(Object? json) {
    if (json is! Map) return null;
    final a = json['address'], s = json['session'], d = json['dappSecret'], p = json['phantomKey'];
    if (a is! String || s is! String || d is! String || p is! String) return null;
    return PhantomLink(address: a, session: s, dappSecret: d, phantomKey: p);
  }
}

/// Phantom said no, or couldn't do it. 4001 is the person tapping Cancel.
class PhantomError implements Exception {
  const PhantomError(this.code, this.message);
  final String code;
  final String message;

  bool get cancelled => code == '4001';

  @override
  String toString() => 'PhantomError($code, $message)';
}

/// The Phantom app, through its deeplinks
/// (https://docs.phantom.com/phantom-deeplinks): Connect for the address and
/// a session, then signTransaction for each payment. Phantom only signs;
/// Glyf sends the signed transaction on (Phantom's own sign-and-send link is
/// deprecated). Every message both ways is a NaCl box (x25519 +
/// XSalsa20-Poly1305) under the key agreed at Connect, in base58.
///
/// Replies come back to `glyf://phantom/{step}`, with Phantom's answer in the
/// query: `nonce` and `data` on success, `errorCode` and `errorMessage`
/// otherwise.
class Phantom {
  Phantom(this.store, {this.appUrl = 'https://www.tryglyf.com', this.redirectBase = 'glyf://phantom'});

  final SecretStore store;
  final String appUrl;
  final String redirectBase;

  static const _base = 'https://phantom.app/ul/v1';
  static const _linkName = 'phantom-link';
  static const _pendingKeyName = 'phantom-pending-key';

  Future<PhantomLink?> link() async {
    final raw = await store.load(_linkName);
    if (raw == null) return null;
    try {
      return PhantomLink.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  /// Opens Phantom's Connect. A new key per Connect, as Phantom asks; it
  /// waits in the store until the reply comes back, even if iOS closes the
  /// app while Phantom is up.
  Future<Uri> connectUrl() async {
    final secret = PrivateKey.generate();
    await store.save(_pendingKeyName, Base58.encode(secret.asTypedList));
    return Uri.parse('$_base/connect').replace(
      queryParameters: {
        'app_url': appUrl,
        'dapp_encryption_public_key': Base58.encode(secret.publicKey.asTypedList),
        'redirect_link': '$redirectBase/connect',
        'cluster': 'mainnet-beta',
      },
    );
  }

  /// Phantom's reply to Connect: the address and session, kept.
  Future<PhantomLink> finishConnect(Uri reply) async {
    _throwIfRefused(reply);
    final secret = await store.load(_pendingKeyName);
    final phantomKey = reply.queryParameters['phantom_encryption_public_key'];
    if (secret == null || phantomKey == null) {
      throw const PhantomError('-32000', 'Connect again from Glyf');
    }
    final json = _open(reply, secret: secret, phantomKey: phantomKey);
    final address = json['public_key'], session = json['session'];
    if (address is! String || session is! String) {
      throw const PhantomError('-32603', 'Phantom sent an answer Glyf can’t read');
    }
    final link = PhantomLink(address: address, session: session, dappSecret: secret, phantomKey: phantomKey);
    await store.save(_linkName, jsonEncode(link.toJson()));
    await store.clear(_pendingKeyName);
    return link;
  }

  /// Opens Phantom to sign [transaction] (unsigned bytes). The reply comes
  /// back to glyf://phantom/sign/[id].
  Future<Uri> signUrl(Uint8List transaction, String id) async {
    final link = await this.link();
    if (link == null) throw const PhantomError('4100', 'Connect Phantom first');
    return _request('signTransaction', link, {
      'transaction': Base58.encode(transaction),
      'session': link.session,
    }, redirect: '$redirectBase/sign/$id');
  }

  /// The signed transaction in Phantom's reply, exactly as Phantom signed
  /// it (it may add a priority fee, so these are the bytes to send).
  Future<Uint8List> finishSign(Uri reply) async {
    _throwIfRefused(reply);
    final link = await this.link();
    if (link == null) throw const PhantomError('4100', 'Connect Phantom first');
    final json = _open(reply, secret: link.dappSecret, phantomKey: link.phantomKey);
    final tx = json['transaction'];
    final bytes = tx is String ? Base58.decode(tx) : null;
    if (bytes == null) throw const PhantomError('-32603', 'Phantom sent an answer Glyf can’t read');
    return bytes;
  }

  /// Ends the session in Phantom too. Forget the link on the phone either way.
  Future<Uri?> disconnectUrl() async {
    final link = await this.link();
    if (link == null) return null;
    return _request('disconnect', link, {'session': link.session}, redirect: '$redirectBase/disconnect');
  }

  Future<void> forget() async {
    await store.clear(_linkName);
    await store.clear(_pendingKeyName);
  }

  // MARK: Sealing

  Uri _request(String method, PhantomLink link, Map<String, Object?> payload, {required String redirect}) {
    final box = Box(
      myPrivateKey: PrivateKey(Base58.decode(link.dappSecret)!),
      theirPublicKey: PublicKey(Base58.decode(link.phantomKey)!),
    );
    final sealed = box.encrypt(Uint8List.fromList(utf8.encode(jsonEncode(payload))));
    final dappPublic = PrivateKey(Base58.decode(link.dappSecret)!).publicKey;
    return Uri.parse('$_base/$method').replace(
      queryParameters: {
        'dapp_encryption_public_key': Base58.encode(dappPublic.asTypedList),
        'nonce': Base58.encode(sealed.nonce.asTypedList),
        'redirect_link': redirect,
        'payload': Base58.encode(sealed.cipherText.asTypedList),
      },
    );
  }

  Map<String, dynamic> _open(Uri reply, {required String secret, required String phantomKey}) {
    final nonce = Base58.decode(reply.queryParameters['nonce'] ?? '');
    final data = Base58.decode(reply.queryParameters['data'] ?? '');
    final secretKey = Base58.decode(secret), theirKey = Base58.decode(phantomKey);
    if (nonce == null || nonce.length != 24 || data == null || secretKey == null || theirKey == null) {
      throw const PhantomError('-32603', 'Phantom sent an answer Glyf can’t read');
    }
    try {
      final box = Box(myPrivateKey: PrivateKey(secretKey), theirPublicKey: PublicKey(theirKey));
      final plain = box.decrypt(ByteList(data), nonce: nonce);
      return jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    } catch (_) {
      throw const PhantomError('-32603', 'Phantom sent an answer Glyf can’t read');
    }
  }

  static void _throwIfRefused(Uri reply) {
    final code = reply.queryParameters['errorCode'];
    if (code != null) {
      throw PhantomError(code, reply.queryParameters['errorMessage'] ?? 'Phantom couldn’t do that');
    }
  }
}
