import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/wallet/solana.dart';
import 'package:glyf/wallet/wallet_api.dart';

/// A private USDC transfer exactly as payments.magicblock.app built it on
/// mainnet (1 USDC, 28 Oct 2026; unsigned, legacy).
const _magicBlockTx = 'AQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABAAcWfowIh2C/3h3dzzLBfyCbgkLuUqrxMfrNiNDqLG0LBvIka7wN3cjnGJ/2vb6tGQzYwk9WSman6pEjxY14QLf7qjL1oj5XcVtBmTtxw3BoGQUa+yT2b46gP7bfxhek4wxlQqVuWUF5oWTqXnyV+NRJuES9wiHkrb1n+OfaVIxh3cxQMMKMljl3zrDS5RT8zbN43LH5Fw3xK1zWaMBHr3aplF+orlLvfgOiNb5SIzHAAM5xGBykfz7vBUsphKWljX9ze4oU/h0S1xYKuOcQ+yTb35rKuNgnvz/FVL4POSq1XR2l17BPeGD5lIbgbZl+ZCSapSIUwz6KWKwqoBauFYRM1b+nsvQK8zK+rzBKpQ1aiofVLx8Ml5iM6RjMwpL1CUSFy0SSUz36eeHH3tOQj/tkezUD0o7+OmVN/cba/MIILBzT6oz1rKyozQUgdRIXXEPO9Upd2Z7eIKFrVSU3OPOX3OY1L3qrLoNJAnJN67E3+nHLJgIpp4Yv5mAt1tpam/mo7I66eo10YOvjfDRoGpq6yuH56OIc6Atr8QdLRebPQ4D0OcJFZ9K5g2LFG/GFufQDn+46qd+LX78OwuMdB8W5gv9F4PeiBUFRq3e1CJn4MOWvz9liUaY9mV+2M8znyoW2AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABGIt60I003Q7VjPDXbunpgiCkNSeBmibSKKe6HqtjUOoyXJY9OJInxuz0QKRSODYMLWhOZ2v8QhASOe9jb6fhZtbcA4fJXOsDMBiIBNErPl7g1BuuM5RmYzGJ+GJOApz7G+nrzvtutOj1l82qryXQxsbvkwtL24OR8pgIDRS9dYQaAyOpzyqzhHfDBuMDlL60R6ixsAMKAfeDvBuWHx19HBt324ddloZPZy+FGzut5rBy0he1fWzeROoz1hX7/AKnsRLnoIz2UhgEtkhBnzh9lzghZ/wBwS9sfBb8hqpzRkgQRBgAKABMPFQEBFAUIAAATDwEAFAgACBQLDAESDyEEBT1HGoWecy5oC8lY+EEHK48/vBlzm+aXxMaBEm+MH3QUEwACBQQOABQHAwYSEQ8TFRAKCQ3EARmwJTIgQEIPAAAAAAABNbLP3r6AycS+AVMF1P2pkzSFHrIkwoc7QEJYIJxdwTYbxEtMo9lv5UAwTeRM8BaMtbsCTNtmjn/dxF3MEwAIrFL8HMHHJKUowZunxnzE88oBBT1HGoWecy5oC8lY+EEHK48/vBlzm+aXxMaBEm+MH3REpi0OWko/jWf3HvOsdd7PBilcvhJC+3EzTpikkJY2RCOPD7oMKUfU6bCjaPDG0r+YDvYvZF4IMcoO2fhQ2vqsMwvhlnY=';

void main() {
  const from = '9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM';
  const feeWallet = '5Q544fKrFoe6tsEbD7S8EmxGTJYAKtTVhAW5Q5pge4j1';

  test('reads MagicBlock’s transaction back', () {
    final d = Sol.decodeLegacy(base64.decode(_magicBlockTx))!;
    expect(d.feePayer, from);
    expect(d.instructions, hasLength(4));
    expect(d.instructions.last.program, 'SPLxh1LVZzEkX99H6rqYizhytLWPZVV296zyYDPagv2');
  });

  test('puts Glyf’s fee in front, still one signer and under the size limit', () {
    final original = base64.decode(_magicBlockTx);
    final fee = Sol.feeInstructions(
      from: from, feeWallet: feeWallet, mint: Sol.usdc, amount: BigInt.from(1000), decimals: 6);
    final out = Sol.prepend(original, fee)!;
    expect(out.length, lessThanOrEqualTo(Sol.maxTransactionBytes));
    expect(out[0], 1, reason: 'only the sender signs');
    final d = Sol.decodeLegacy(out)!;
    expect(d.feePayer, from);
    expect(d.blockhash, Sol.decodeLegacy(original)!.blockhash);
    expect(d.instructions, hasLength(6));
    expect(d.instructions[1].program, Sol.tokenProgram);
    expect(d.instructions[1].data.first, 12, reason: 'TransferChecked');
    expect(d.instructions[1].accounts[2].address, Sol.tokenAccount(feeWallet, Sol.usdc));
    // MagicBlock's own four, untouched and in order.
    final before = Sol.decodeLegacy(original)!.instructions;
    for (var i = 0; i < 4; i++) {
      expect(d.instructions[i + 2].program, before[i].program);
      expect(d.instructions[i + 2].data, before[i].data);
      expect([for (final a in d.instructions[i + 2].accounts) (a.address, a.signer, a.writable)],
          [for (final a in before[i].accounts) (a.address, a.signer, a.writable)]);
    }
  });

  test('a signed transaction is never rewritten', () {
    final signed = base64.decode(_magicBlockTx)..[5] = 7;
    expect(Sol.prepend(signed, const []), isNull);
  });

  test('0.1% rounds down', () {
    expect(PrivateFee.amountFor(BigInt.from(5000000), 10), BigInt.from(5000));
    expect(PrivateFee.amountFor(BigInt.from(999), 10), BigInt.zero);
    expect(PrivateFee.percent(10), '0.1');
  });
}
