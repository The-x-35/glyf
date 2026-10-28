import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;

import 'base58.dart';

/// One account an instruction touches.
class AccountMeta {
  const AccountMeta(this.address, {this.signer = false, this.writable = false});
  final String address;
  final bool signer;
  final bool writable;
}

class Instruction {
  const Instruction(this.program, this.accounts, this.data);
  final String program;
  final List<AccountMeta> accounts;
  final List<int> data;
}

/// The little of Solana that Glyf builds on the phone: addresses, the token
/// account an owner holds for a mint, and two transfers (SOL, and a token
/// with the recipient's account opened if it's missing). Phantom signs every
/// transaction; nothing here ever holds a key.
abstract final class Sol {
  static const systemProgram = '11111111111111111111111111111111';
  static const tokenProgram = 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA';
  static const token2022Program = 'TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb';
  static const ataProgram = 'ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL';
  static const wsol = 'So11111111111111111111111111111111111111112';
  static const usdc = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';
  static const solDecimals = 9;
  static const usdcDecimals = 6;

  /// The 32 bytes of an address, or null when it isn't one.
  static Uint8List? key(String address) {
    final bytes = Base58.decode(address.trim());
    return bytes != null && bytes.length == 32 ? bytes : null;
  }

  static bool isAddress(String text) => key(text) != null;

  /// "7dHb…7ARj".
  static String short(String address) =>
      address.length <= 10 ? address : '${address.substring(0, 4)}…${address.substring(address.length - 4)}';

  // MARK: Program addresses

  static final _p = (BigInt.one << 255) - BigInt.from(19);
  static final _d = (BigInt.from(-121665) * BigInt.from(121666).modInverse(_p)) % _p;

  /// Whether 32 bytes are a point on ed25519: what curve25519-dalek's
  /// `decompress()` answers, which is Solana's rule for program addresses.
  static bool isOnCurve(Uint8List bytes) {
    var y = BigInt.zero;
    for (var i = 31; i >= 0; i--) {
      y = (y << 8) | BigInt.from(i == 31 ? bytes[i] & 0x7f : bytes[i]);
    }
    y %= _p;
    final y2 = (y * y) % _p;
    final u = (y2 - BigInt.one) % _p;
    final v = (_d * y2 + BigInt.one) % _p;
    final x2 = (u * v.modPow(_p - BigInt.two, _p)) % _p;
    if (x2 == BigInt.zero) return true;
    return x2.modPow((_p - BigInt.one) >> 1, _p) == BigInt.one;
  }

  static Uint8List? findProgramAddress(List<List<int>> seeds, List<int> program) {
    for (var bump = 255; bump >= 0; bump--) {
      final input = BytesBuilder(copy: false);
      for (final seed in seeds) {
        input.add(seed);
      }
      input
        ..addByte(bump)
        ..add(program)
        ..add(utf8.encode('ProgramDerivedAddress'));
      final hash = Uint8List.fromList(sha256.convert(input.toBytes()).bytes);
      if (!isOnCurve(hash)) return hash;
    }
    return null;
  }

  /// The associated token account [owner] holds for [mint].
  static String tokenAccount(String owner, String mint) =>
      Base58.encode(findProgramAddress([key(owner)!, key(tokenProgram)!, key(mint)!], key(ataProgram)!)!);

  // MARK: Amounts

  /// A typed amount with "." as its decimal point, or null when it can't be
  /// read only one way. With a "." any commas are grouping ("1,000.5");
  /// without one, a single comma is the decimal point ("5,5" from a comma
  /// keypad) and more than one is refused.
  static String? plainAmount(String amount) {
    final text = amount.trim();
    final dot = text.indexOf('.');
    if (dot >= 0) {
      // Grouping never comes after the point: "1.000,5" is refused, not
      // read as 1.0005.
      if (text.contains(',', dot)) return null;
      return text.replaceAll(',', '');
    }
    if (','.allMatches(text).length > 1) return null;
    return text.replaceFirst(',', '.');
  }

  /// "12.5" (or "12,5") in whole tokens, as base units, exactly. Null when
  /// it isn't an amount, is zero, or has more decimals than the token.
  static BigInt? units(String amount, int decimals) {
    final text = plainAmount(amount);
    if (text == null) return null;
    final match = RegExp(r'^(\d*)(?:\.(\d*))?$').firstMatch(text);
    if (match == null || text.isEmpty || text == '.') return null;
    final whole = match.group(1) ?? '';
    final frac = match.group(2) ?? '';
    if (frac.length > decimals) return null;
    final value =
        BigInt.parse(whole.isEmpty ? '0' : whole) * BigInt.from(10).pow(decimals) +
        BigInt.parse((frac + '0' * decimals).substring(0, decimals).padRight(1, '0'));
    return value > BigInt.zero ? value : null;
  }

  /// Base units as whole tokens, with at most [maxDecimals] places and no
  /// trailing zeros.
  static String format(BigInt units, int decimals, {int maxDecimals = 4}) {
    final scale = BigInt.from(10).pow(decimals);
    final whole = units ~/ scale;
    var frac = (units % scale).toString().padLeft(decimals, '0');
    if (frac.length > maxDecimals) frac = frac.substring(0, maxDecimals);
    frac = frac.replaceFirst(RegExp(r'0+$'), '');
    return frac.isEmpty ? '$whole' : '$whole.$frac';
  }

  // MARK: Transactions

  /// SOL from [from] to [to]: one System transfer, [from] pays and signs.
  static Uint8List transferSol({
    required String from,
    required String to,
    required BigInt lamports,
    required String blockhash,
  }) => compileLegacy(
    feePayer: from,
    blockhash: blockhash,
    instructions: [
      Instruction(
        systemProgram,
        [AccountMeta(from, signer: true, writable: true), AccountMeta(to, writable: true)],
        [2, 0, 0, 0, ..._u64(lamports)],
      ),
    ],
  );

  /// A token (USDC) from [from] to [to]: opens [to]'s token account when it
  /// doesn't have one (CreateIdempotent does nothing when it exists), then
  /// TransferChecked, so the amount and the decimals are both checked.
  static Uint8List transferToken({
    required String from,
    required String to,
    required String mint,
    required BigInt amount,
    required int decimals,
    required String blockhash,
  }) {
    final source = tokenAccount(from, mint);
    final destination = tokenAccount(to, mint);
    return compileLegacy(
      feePayer: from,
      blockhash: blockhash,
      instructions: [
        Instruction(
          ataProgram,
          [
            AccountMeta(from, signer: true, writable: true),
            AccountMeta(destination, writable: true),
            AccountMeta(to),
            AccountMeta(mint),
            const AccountMeta(systemProgram),
            const AccountMeta(tokenProgram),
          ],
          const [1],
        ),
        Instruction(
          tokenProgram,
          [
            AccountMeta(source, writable: true),
            AccountMeta(mint),
            AccountMeta(destination, writable: true),
            AccountMeta(from, signer: true),
          ],
          [12, ..._u64(amount), decimals],
        ),
      ],
    );
  }

  /// A legacy transaction with empty signature slots, the way web3.js
  /// serializes one before signing: the fee payer first, then signers,
  /// writable accounts, the rest, each group in the order it first appears,
  /// program ids after the accounts.
  static Uint8List compileLegacy({
    required String feePayer,
    required String blockhash,
    required List<Instruction> instructions,
  }) {
    final order = <String>[];
    final signer = <String, bool>{};
    final writable = <String, bool>{};
    void touch(String address, {bool isSigner = false, bool isWritable = false}) {
      if (!signer.containsKey(address)) {
        order.add(address);
        signer[address] = false;
        writable[address] = false;
      }
      signer[address] = signer[address]! || isSigner;
      writable[address] = writable[address]! || isWritable;
    }

    touch(feePayer, isSigner: true, isWritable: true);
    for (final ix in instructions) {
      for (final meta in ix.accounts) {
        touch(meta.address, isSigner: meta.signer, isWritable: meta.writable);
      }
    }
    for (final ix in instructions) {
      touch(ix.program);
    }
    int rank(String a) => (signer[a]! ? 0 : 2) + (writable[a]! ? 0 : 1);
    final keys = [...order]
      ..sort((a, b) {
        if (a == feePayer) return -1;
        if (b == feePayer) return 1;
        final byRank = rank(a).compareTo(rank(b));
        return byRank != 0 ? byRank : order.indexOf(a).compareTo(order.indexOf(b));
      });
    final signers = keys.where((k) => signer[k]!).length;
    final readonlySigned = keys.where((k) => signer[k]! && !writable[k]!).length;
    final readonlyUnsigned = keys.where((k) => !signer[k]! && !writable[k]!).length;

    final message = BytesBuilder(copy: false)
      ..add([signers, readonlySigned, readonlyUnsigned])
      ..add(_compactU16(keys.length));
    for (final k in keys) {
      message.add(key(k)!);
    }
    message
      ..add(key(blockhash)!)
      ..add(_compactU16(instructions.length));
    for (final ix in instructions) {
      message
        ..addByte(keys.indexOf(ix.program))
        ..add(_compactU16(ix.accounts.length))
        ..add([for (final m in ix.accounts) keys.indexOf(m.address)])
        ..add(_compactU16(ix.data.length))
        ..add(ix.data);
    }
    return Uint8List.fromList([..._compactU16(signers), ...List.filled(64 * signers, 0), ...message.toBytes()]);
  }

  /// Solana's limit on one serialized transaction.
  static const maxTransactionBytes = 1232;

  /// A legacy transaction taken apart: its fee payer, blockhash and
  /// instructions (each account's signer and writable flags read back from
  /// the message header). Null when [tx] isn't an unsigned-or-signed legacy
  /// transaction this can read.
  static ({String feePayer, String blockhash, List<Instruction> instructions})? decodeLegacy(Uint8List tx) {
    try {
      var i = 0;
      int compact() {
        var value = 0, shift = 0;
        while (true) {
          final byte = tx[i++];
          value |= (byte & 0x7f) << shift;
          shift += 7;
          if (byte < 0x80) return value;
        }
      }

      final sigs = compact();
      i += 64 * sigs;
      if (tx[i] & 0x80 != 0) return null; // a v0 message
      final signers = tx[i], readonlySigned = tx[i + 1], readonlyUnsigned = tx[i + 2];
      i += 3;
      final count = compact();
      final keys = [for (var k = 0; k < count; k++) Base58.encode(tx.sublist(i + 32 * k, i + 32 * k + 32))];
      i += 32 * count;
      final blockhash = Base58.encode(tx.sublist(i, i + 32));
      i += 32;
      bool isSigner(int k) => k < signers;
      bool isWritable(int k) =>
          k < signers ? k < signers - readonlySigned : k < count - readonlyUnsigned;
      final instructions = <Instruction>[];
      final n = compact();
      for (var x = 0; x < n; x++) {
        final program = keys[tx[i++]];
        final accounts = [for (var a = 0, m = compact(); a < m; a++) tx[i++]];
        final len = compact();
        final data = tx.sublist(i, i + len);
        i += len;
        instructions.add(Instruction(program, [
          for (final k in accounts) AccountMeta(keys[k], signer: isSigner(k), writable: isWritable(k)),
        ], data));
      }
      if (i != tx.length) return null;
      return (feePayer: keys.first, blockhash: blockhash, instructions: instructions);
    } catch (_) {
      return null;
    }
  }

  /// [tx] with [first] run before its own instructions, re-serialized
  /// unsigned. Null when [tx] can't be read, already carries a signature, or
  /// the result would be over Solana's size limit; the caller then keeps
  /// [tx] as it was.
  static Uint8List? prepend(Uint8List tx, List<Instruction> first) {
    if (tx.isEmpty || tx[0] == 0 || tx.length < 65) return null;
    // Any slot already filled is a signature this would invalidate.
    final sigs = tx[0];
    for (var b = 1; b < 1 + 64 * sigs; b++) {
      if (tx[b] != 0) return null;
    }
    final decoded = decodeLegacy(tx);
    if (decoded == null) return null;
    final out = compileLegacy(
      feePayer: decoded.feePayer,
      blockhash: decoded.blockhash,
      instructions: [...first, ...decoded.instructions],
    );
    return out.length <= maxTransactionBytes ? out : null;
  }

  /// Glyf's fee on a token payment, paid by [from] to [feeWallet]: opens the
  /// fee wallet's token account if it has none (CreateIdempotent, nothing
  /// when it exists), then TransferChecked.
  static List<Instruction> feeInstructions({
    required String from,
    required String feeWallet,
    required String mint,
    required BigInt amount,
    required int decimals,
  }) {
    final source = tokenAccount(from, mint);
    final destination = tokenAccount(feeWallet, mint);
    return [
      Instruction(
        ataProgram,
        [
          AccountMeta(from, signer: true, writable: true),
          AccountMeta(destination, writable: true),
          AccountMeta(feeWallet),
          AccountMeta(mint),
          const AccountMeta(systemProgram),
          const AccountMeta(tokenProgram),
        ],
        const [1],
      ),
      Instruction(
        tokenProgram,
        [
          AccountMeta(source, writable: true),
          AccountMeta(mint),
          AccountMeta(destination, writable: true),
          AccountMeta(from, signer: true),
        ],
        [12, ..._u64(amount), decimals],
      ),
    ];
  }

  static List<int> _u64(BigInt value) {
    final out = List<int>.filled(8, 0);
    var v = value;
    for (var i = 0; i < 8; i++) {
      out[i] = (v & BigInt.from(0xff)).toInt();
      v >>= 8;
    }
    return out;
  }

  static List<int> _compactU16(int value) {
    final out = <int>[];
    var v = value;
    while (true) {
      final byte = v & 0x7f;
      v >>= 7;
      if (v == 0) {
        out.add(byte);
        return out;
      }
      out.add(byte | 0x80);
    }
  }
}
