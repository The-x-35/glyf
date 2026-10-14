import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/profile/paywall_sheet.dart';
import 'package:glyf/wallet/base58.dart';
import 'package:glyf/wallet/crypto_pay.dart';
import 'package:glyf/wallet/solana.dart';

void main() {
  const from = 'GmSCZ3VJ5fn6oxPN1KAgEmiK4sPmdFXCDACeKMtxCpcB';
  const treasury = '7dHbWXmci3dT8UFYWYZweBLXgycu7Y3iL6trKn1Y7ARj';
  const reference = '4uQeVj5tqViQh7yWWGStvkEG1Zmhx6uasJtWCJziofM';
  const blockhash = 'EETubP5AKHgjPAhzPAFcb8BAY1hMH639CWCFTqi3hq1k';

  test('the USDC transfer carries the reference as a read-only account', () {
    const request = CryptoRequest(
        reference: reference, recipient: treasury, mint: Sol.usdc, amount: '5', url: 'solana:x');
    final tx = CryptoPay.transfer(from: from, request: request, blockhash: blockhash);
    // One empty signature slot: only the payer signs.
    expect(tx[0], 1);
    final msg = tx.sublist(65);
    final signers = msg[0], readonlySigned = msg[1], readonlyUnsigned = msg[2], count = msg[3];
    expect(signers, 1);
    expect(readonlySigned, 0);
    final keys = [for (var i = 0; i < count; i++) Base58.encode(msg.sublist(4 + 32 * i, 36 + 32 * i))];
    expect(keys.first, from);
    final refAt = keys.indexOf(reference);
    expect(refAt, greaterThan(count - readonlyUnsigned - 1), reason: 'among the read-only, unsigned accounts');
    // The same accounts as a plain USDC send, plus the reference.
    final plain = Sol.transferToken(
        from: from, to: treasury, mint: Sol.usdc, amount: BigInt.from(5000000), decimals: 6, blockhash: blockhash);
    expect(count, plain.sublist(65)[3] + 1);
    // TransferChecked (the last instruction) ends with the reference and
    // moves exactly 5 USDC.
    final tail = msg.sublist(msg.length - 18);
    expect(keys[tail[0]], Sol.tokenProgram);
    expect(tail[1], 5, reason: 'source, mint, destination, owner, reference');
    expect(keys[tail[4]], Sol.tokenAccount(treasury, Sol.usdc));
    expect(keys[tail[5]], from);
    expect(tail[6], refAt);
    expect(tail.sublist(7), [10, 12, 0x40, 0x4b, 0x4c, 0, 0, 0, 0, 0, 6]);
  });

  test('a request reads from the server’s answer', () {
    final r = CryptoRequest.fromJson({
      'reference': reference, 'recipient': treasury, 'mint': Sol.usdc, 'amount': '20', 'url': 'solana:$treasury?amount=20',
    });
    expect(r?.amount, '20');
    expect(CryptoRequest.fromJson({'reference': reference}), isNull);
  });

  testWidgets('store builds never offer USDC', (tester) async {
    expect(CryptoPay.allowed, isFalse);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(onPressed: () => showPaywall(context), child: const Text('open')),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('USDC'), findsNothing);
    expect(find.text('Plans open soon'), findsOneWidget);
  });
}
