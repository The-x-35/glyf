import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/wallet/base58.dart';
import 'package:glyf/wallet/solana.dart';

/// Expected bytes come from Solana's own @solana/web3.js 1.x and
/// @solana/spl-token 0.4 for the same inputs (keys from seeds of 7s and 9s).
void main() {
  const from = 'GmaDrppBC7P5ARKV8g3djiwP89vz1jLK23V2GBjuAEGB';
  const to = 'J2xccRtuG43drESLYznHhLhQkLTdfepcKYbiQ9BsJVaf';
  const blockhash = 'EkSnNWid2cvwEVnVx9aBqawnmiCNiDgp3gUdkDPTKN1N';

  test('base58 round-trips addresses and keeps leading zeros', () {
    final bytes = Base58.decode(from)!;
    expect(bytes.length, 32);
    expect(Base58.encode(bytes), from);
    expect(Base58.encode([0, 0, 1]), '112');
    expect(Base58.decode('0OIl'), isNull, reason: 'not in the alphabet');
    expect(Sol.isAddress('hello'), isFalse);
    expect(Sol.isAddress(Sol.usdc), isTrue);
  });

  test('token accounts match spl-token', () {
    const expected = {
      from: '7woc3ajaGMMXczFYjxon4aQoHH3j126fMUR9c58eHRsK',
      to: '7RP22uEk2BNSbZaQDPAXEqFzcqgoo7qiDiM3VwpgwXc1',
      '9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM': 'FGETo8T8wMcN2wCjav8VK6eh3dLk63evNDPxzLSJra8B',
      '7dHbWXmci3dT8UFYWYZweBLXgycu7Y3iL6trKn1Y7ARj': '47EavE6pitj9Dzge7PTRDUHmLm8weZmLfnAvZKbqA9SB',
    };
    expected.forEach((owner, ata) => expect(Sol.tokenAccount(owner, Sol.usdc), ata, reason: owner));
  });

  test('a SOL transfer serializes exactly like web3.js', () {
    final tx = Sol.transferSol(from: from, to: to, lamports: BigInt.from(12300000), blockhash: blockhash);
    expect(base64.encode(tx),
        'AQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABAAED6kpsY+KcUgq+9VB7Ey7F+ZVHdq6+vnuSQh7qaRRG0iz9FyQ4WqDHW2T7eM1gL6HZkf3r92sTxY7XAurINen2GAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAzEkOkozS44c7s0P8ldozF5ymD02/RsLDbpEpnVXU5rkBAgIAAQwCAAAA4K67AAAAAAA=');
  });

  test('a USDC transfer carries the same instructions as spl-token\'s', () {
    final tx = Sol.transferToken(
        from: from, to: to, mint: Sol.usdc, amount: BigInt.from(5250000), decimals: 6, blockhash: blockhash);
    // web3.js sorts accounts of the same kind by address; these keep the
    // order they first appear in. Decoded by web3.js (Transaction.from), the
    // two carry identical instructions, accounts, flags and data (checked
    // 2026-09-27): CreateIdempotent for the recipient's account, then
    // TransferChecked of 5.25 USDC.
    expect(base64.encode(tx),
        'AQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABAAUI6kpsY+KcUgq+9VB7Ey7F+ZVHdq6+vnuSQh7qaRRG0ixfZPTjA2uksxbaU+n6MTMwx33fGlSEu7ljqCiM1OBB5mcwLkkYlNdJLqa+T5FOpPRfoULmRYZ8kWSidtXddvB2/RckOFqgx1tk+3jNYC+h2ZH96/drE8WO1wLqyDXp9hjG+nrzvtutOj1l82qryXQxsbvkwtL24OR8pgIDRS9dYQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABt324ddloZPZy+FGzut5rBy0he1fWzeROoz1hX7/AKmMlyWPTiSJ8bs9ECkUjg2DC1oTmdr/EIQEjnvY2+n4WcxJDpKM0uOHO7ND/JXaMxecpg9Nv0bCw26RKZ1V1Oa5AgcGAAEDBAUGAQEGBAIEAQAKDNAbUAAAAAAABg==');
  });

  test('amounts are exact', () {
    expect(Sol.units('12.5', 6), BigInt.from(12500000));
    expect(Sol.units('0.000000001', 9), BigInt.one);
    expect(Sol.units('1,000', 6), BigInt.from(1000000000));
    expect(Sol.units('0', 6), isNull);
    expect(Sol.units('1.2345678', 6), isNull, reason: 'more places than USDC has');
    expect(Sol.units('abc', 6), isNull);
    expect(Sol.format(BigInt.from(12500000), 6), '12.5');
    expect(Sol.format(BigInt.from(1234567891), 9), '1.2345');
    expect(Sol.short('7dHbWXmci3dT8UFYWYZweBLXgycu7Y3iL6trKn1Y7ARj'), '7dHb…7ARj');
  });
}
