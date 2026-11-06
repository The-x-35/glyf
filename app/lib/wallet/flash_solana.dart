import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pinenacl/ed25519.dart' as ed;

import 'base58.dart';
import 'solana.dart';

/// Phantom's answers to the requests a waiting Flash order made: each one
/// opened Phantom with its own id, and its reply comes back on
/// `glyf://phantom/trade/<id>`. The trade screen waits on [ask]; the app's
/// link handler (main.dart) hands every reply to [handle] first, so a pay
/// or connect reply (glyf://phantom/sign/…, /connect) still goes where it
/// always did.
abstract final class PhantomRequests {
  static const step = 'trade';
  static final Map<String, Completer<Uri>> _waiting = {};

  static String newId() {
    final r = Random.secure();
    return List.generate(12, (_) => r.nextInt(36).toRadixString(36)).join();
  }

  /// Waits for the reply to the request [id]. [open] opens Phantom on it
  /// (an error to show, or null); it runs after the waiter is in place, so
  /// even an instant reply finds it. Throws a [TimeoutException] after
  /// [timeout], and the error [open] gave if Phantom never opened.
  static Future<Uri> ask(String id, Future<String?> Function() open,
      {Duration timeout = const Duration(minutes: 10)}) async {
    final waiter = Completer<Uri>();
    _waiting[id] = waiter;
    try {
      final failed = await open();
      if (failed != null) throw PhantomUnavailable(failed);
      return await waiter.future.timeout(timeout);
    } finally {
      _waiting.remove(id);
    }
  }

  /// True when [uri] answered a request a trade is waiting on (it is taken
  /// care of); false for anything else, which goes on to the pay screen.
  static bool handle(Uri uri) {
    if (uri.host != 'phantom' || uri.pathSegments.length < 2 || uri.pathSegments.first != step) return false;
    final waiter = _waiting.remove(uri.pathSegments[1]);
    if (waiter == null || waiter.isCompleted) return false;
    waiter.complete(uri);
    return true;
  }

  /// For tests: whether a request is still waiting.
  static bool isWaiting(String id) => _waiting.containsKey(id);
}

/// Phantom couldn't be opened (not installed): the App Store was, instead.
class PhantomUnavailable implements Exception {
  const PhantomUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}

/// What Flash's order message (svm.orderMessage) commits to:
/// `DFS|m=<spent mint>|t=<total in base units>|h=<order hash>`.
class FlashOrderMessage {
  const FlashOrderMessage(this.mint, this.total, this.hash);
  final String mint;
  final BigInt total;
  final String hash;

  static FlashOrderMessage? parse(String message) {
    final m = RegExp(r'^DFS\|m=([1-9A-HJ-NP-Za-km-z]{32,44})\|t=(\d{1,30})\|h=([1-9A-HJ-NP-Za-km-z]{1,44})$')
        .firstMatch(message);
    if (m == null) return null;
    return FlashOrderMessage(m.group(1)!, BigInt.parse(m.group(2)!), m.group(3)!);
  }
}

/// The phone's half of a Flash order on Solana
/// (flash.definitive.fi/docs/solana-overview.md): the setup instructions
/// Flash quotes put into ONE transaction for Phantom to sign, and every
/// signature Phantom sends back checked against the wallet's own key before
/// anything is submitted.
abstract final class FlashSvm {
  static const computeBudgetProgram = 'ComputeBudget111111111111111111111111111111';

  /// One of Flash's SvmInstruction objects: {programId, accounts:
  /// [{pubkey, isSigner, isWritable}], data (base58)}.
  static Instruction instruction(Object? json) {
    if (json is! Map) throw const FormatException('Flash sent an instruction Glyf can’t read');
    final program = json['programId'], accounts = json['accounts'], data = json['data'];
    if (program is! String || !Sol.isAddress(program) || accounts is! List || data is! String) {
      throw const FormatException('Flash sent an instruction Glyf can’t read');
    }
    final bytes = data.isEmpty ? Uint8List(0) : Base58.decode(data);
    if (bytes == null) throw const FormatException('Flash sent an instruction Glyf can’t read');
    return Instruction(program, [
      for (final a in accounts)
        if (a is Map && a['pubkey'] is String && Sol.isAddress(a['pubkey'] as String))
          AccountMeta(a['pubkey'] as String, signer: a['isSigner'] == true, writable: a['isWritable'] == true)
        else
          throw const FormatException('Flash sent an instruction Glyf can’t read'),
    ], bytes);
  }

  /// Everything the quote wants on chain before the order, in the order
  /// Flash's docs give: token accounts, the native-SOL wrap, the delegation
  /// for what's spent, then (an attached take-profit / stop-loss) the
  /// delegation for what comes back.
  static List<Instruction> setupInstructions(Map quote) {
    final svm = quote['svm'] is Map ? quote['svm'] as Map : const {};
    final wrap = quote['wrap'] is Map ? quote['wrap'] as Map : const {};
    final pair = quote['attachedBracket'] is Map ? quote['attachedBracket'] as Map : const {};
    final pairSvm = pair['svm'] is Map ? pair['svm'] as Map : const {};
    return [
      for (final ix in (svm['ataSetupIxs'] as List? ?? const [])) instruction(ix),
      for (final ix in (wrap['svmInstructions'] as List? ?? const [])) instruction(ix),
      if (svm['delegateIx'] != null) instruction(svm['delegateIx']),
      if (pairSvm['delegateIx'] != null) instruction(pairSvm['delegateIx']),
    ];
  }

  /// Instructions that only [funder] may sign for: anything wanting another
  /// signer can't be in a transaction Phantom alone signs.
  static String? strangerSigner(List<Instruction> instructions, String funder) {
    for (final ix in instructions) {
      for (final a in ix.accounts) {
        if (a.signer && a.address != funder) return a.address;
      }
    }
    return null;
  }

  /// The one setup transaction, unsigned, [funder] paying. Null when the
  /// quote needs none; throws when it wouldn't fit in one transaction.
  static Uint8List? setupTransaction({required Map quote, required String funder, required String blockhash}) {
    final ixs = setupInstructions(quote);
    if (ixs.isEmpty) return null;
    final stranger = strangerSigner(ixs, funder);
    if (stranger != null) throw FormatException('Flash asked for a signature from ${Sol.short(stranger)}');
    final tx = Sol.compileLegacy(feePayer: funder, blockhash: blockhash, instructions: ixs);
    if (tx.length > Sol.maxTransactionBytes) {
      throw const FormatException('The setup is too big for one transaction');
    }
    return tx;
  }

  /// A recent blockhash out of the quote's own setup transaction
  /// (setupTxs[0], base64), for when the phone can't ask Solana for one.
  static String? blockhashOf(Map quote) {
    final txs = quote['setupTxs'];
    if (txs is! List || txs.isEmpty || txs.first is! String) return null;
    try {
      return Sol.decodeLegacy(base64.decode(txs.first as String))?.blockhash;
    } catch (_) {
      return null;
    }
  }

  /// The message part of a serialized transaction, and its signatures.
  static ({List<Uint8List> signatures, Uint8List message})? split(Uint8List tx) {
    if (tx.isEmpty) return null;
    var i = 0, n = 0, shift = 0;
    while (true) {
      if (i >= tx.length) return null;
      final b = tx[i++];
      n |= (b & 0x7f) << shift;
      shift += 7;
      if (b < 0x80) break;
    }
    if (n < 1 || tx.length < i + 64 * n + 3) return null;
    return (
      signatures: [for (var k = 0; k < n; k++) tx.sublist(i + 64 * k, i + 64 * k + 64)],
      message: tx.sublist(i + 64 * n),
    );
  }

  /// A signed transaction's id (its first signature), in base58.
  static String? txSignature(Uint8List signed) {
    final parts = split(signed);
    return parts == null ? null : Base58.encode(parts.signatures.first);
  }

  /// Whether [signed] (Phantom's answer to [asked]) is the setup Glyf asked
  /// for, signed by [funder]: a valid signature from the funder over its
  /// message, the funder paying, and the same instructions in the same
  /// order. Phantom may add compute-budget instructions (its priority fee)
  /// and pick a newer blockhash; nothing else may change.
  static bool isSignedSetup(Uint8List signed, Uint8List asked, String funder) {
    final parts = split(signed);
    final key = Sol.key(funder);
    if (parts == null || key == null) return false;
    if (!verify(parts.message, parts.signatures.first, key)) return false;
    final got = Sol.decodeLegacy(signed), want = Sol.decodeLegacy(asked);
    if (got == null || want == null || got.feePayer != funder) return false;
    final kept = got.instructions.where((ix) => ix.program != computeBudgetProgram).toList();
    final wanted = want.instructions.where((ix) => ix.program != computeBudgetProgram).toList();
    if (kept.length != wanted.length) return false;
    for (var k = 0; k < kept.length; k++) {
      if (!_same(kept[k], wanted[k])) return false;
    }
    return true;
  }

  /// Whether [signed] is Flash's sponsored delegation [asked] with the
  /// funder's signature added: the same message, and a valid signature from
  /// [funder] in its slot.
  static bool isSignedSponsored(Uint8List signed, Uint8List asked, String funder) {
    final got = split(signed), want = split(asked);
    final key = Sol.key(funder);
    if (got == null || want == null || key == null) return false;
    if (!_bytesEqual(got.message, want.message)) return false;
    final slot = _signerSlot(got.message, key);
    return slot != null && slot < got.signatures.length && verify(got.message, got.signatures[slot], key);
  }

  /// The funder's position among a message's signers, legacy or v0.
  static int? _signerSlot(Uint8List message, Uint8List key) {
    var i = message.isNotEmpty && message[0] & 0x80 != 0 ? 1 : 0;
    if (message.length < i + 4) return null;
    final signers = message[i];
    i += 3;
    var count = 0, shift = 0;
    while (true) {
      final b = message[i++];
      count |= (b & 0x7f) << shift;
      shift += 7;
      if (b < 0x80) break;
    }
    for (var k = 0; k < signers && k < count; k++) {
      if (_bytesEqual(message.sublist(i + 32 * k, i + 32 * k + 32), key)) return k;
    }
    return null;
  }

  /// Ed25519: whether [signature] is [key]'s over [message].
  static bool verify(List<int> message, List<int> signature, List<int> key) {
    if (signature.length != 64 || key.length != 32) return false;
    try {
      return ed.VerifyKey(Uint8List.fromList(key))
          .verify(signature: ed.Signature(Uint8List.fromList(signature)), message: Uint8List.fromList(message));
    } catch (_) {
      return false;
    }
  }

  /// Whether Phantom's [signature] over Flash's UTF-8 [message] is the
  /// funder's: what Flash itself will check, checked before it's sent.
  static bool verifyMessage(String message, Uint8List signature, String funder) {
    final key = Sol.key(funder);
    return key != null && verify(utf8.encode(message), signature, key);
  }

  /// Why Flash's order message doesn't say what the person asked for, or
  /// null when it does: the spent [mint], and [total] of it in base units
  /// (null when the amount isn't known exactly).
  static String? messageProblem(String? message, {required String mint, BigInt? total}) {
    if (message == null || message.isEmpty) return 'Flash sent nothing to sign';
    final parsed = FlashOrderMessage.parse(message);
    if (parsed == null) return 'Flash sent an order Glyf can’t read';
    if (parsed.mint != mint) return 'Flash’s order spends a different token';
    if (total != null && parsed.total != total) return 'Flash’s order is for a different amount';
    return null;
  }

  static bool _same(Instruction a, Instruction b) {
    if (a.program != b.program || a.accounts.length != b.accounts.length) return false;
    if (!_bytesEqual(a.data, b.data)) return false;
    for (var k = 0; k < a.accounts.length; k++) {
      final x = a.accounts[k], y = b.accounts[k];
      if (x.address != y.address || x.signer != y.signer || x.writable != y.writable) return false;
    }
    return true;
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var k = 0; k < a.length; k++) {
      if (a[k] != b[k]) return false;
    }
    return true;
  }
}
