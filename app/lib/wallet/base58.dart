import 'dart:typed_data';

/// Base58 with Bitcoin's alphabet: how Solana writes addresses, signatures
/// and transactions, and how Phantom's deeplinks carry everything.
abstract final class Base58 {
  static const _alphabet = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
  static final _index = {for (var i = 0; i < _alphabet.length; i++) _alphabet.codeUnitAt(i): i};

  static String encode(List<int> bytes) {
    if (bytes.isEmpty) return '';
    var zeros = 0;
    while (zeros < bytes.length && bytes[zeros] == 0) {
      zeros++;
    }
    // Repeated division of the big-endian number by 58, in place.
    final digits = <int>[];
    final input = List<int>.from(bytes.sublist(zeros));
    var start = 0;
    while (start < input.length) {
      var remainder = 0;
      for (var i = start; i < input.length; i++) {
        final acc = remainder * 256 + input[i];
        input[i] = acc ~/ 58;
        remainder = acc % 58;
      }
      digits.add(remainder);
      while (start < input.length && input[start] == 0) {
        start++;
      }
    }
    final out = StringBuffer('1' * zeros);
    for (var i = digits.length - 1; i >= 0; i--) {
      out.writeCharCode(_alphabet.codeUnitAt(digits[i]));
    }
    return out.toString();
  }

  /// Null when [text] isn't base58.
  static Uint8List? decode(String text) {
    if (text.isEmpty) return Uint8List(0);
    var zeros = 0;
    while (zeros < text.length && text.codeUnitAt(zeros) == 0x31) {
      zeros++;
    }
    final bytes = <int>[];
    for (var i = zeros; i < text.length; i++) {
      final value = _index[text.codeUnitAt(i)];
      if (value == null) return null;
      var carry = value;
      for (var j = 0; j < bytes.length; j++) {
        carry += bytes[j] * 58;
        bytes[j] = carry & 0xff;
        carry >>= 8;
      }
      while (carry > 0) {
        bytes.add(carry & 0xff);
        carry >>= 8;
      }
    }
    return Uint8List.fromList([...List.filled(zeros, 0), ...bytes.reversed]);
  }
}
