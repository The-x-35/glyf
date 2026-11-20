import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/wallet/wallet_screen.dart';

void main() {
  testWidgets('the signer line stays inside a narrow card beside Disconnect', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            child: Row(children: [
              const SizedBox(width: 40),
              const Expanded(
                child: WalletSignerLine(text: 'Phantom · DYbqJ8x2…kP9oQ69', copyIcon: Icons.copy_rounded),
              ),
              TextButton(onPressed: () {}, child: const Text('Disconnect')),
            ]),
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
  });

  testWidgets('a line too wide for the room shrinks whole, its last characters never faded', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 150,
            child: Row(children: [
              const Expanded(
                child: WalletSignerLine(text: 'MetaMask · 0x7099…79C8', copyIcon: Icons.copy_rounded),
              ),
            ]),
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    final text = tester.widget<Text>(find.text('MetaMask · 0x7099…79C8'));
    expect(text.overflow, isNot(TextOverflow.fade));
    // Drawn smaller than it would be laid out: scaled down to fit, so all of
    // it shows beside the copy icon inside the 150 pt.
    final drawn = tester.getSize(find.text('MetaMask · 0x7099…79C8'));
    final box = tester.getRect(find.byType(FittedBox));
    expect(box.right, lessThanOrEqualTo(150 + tester.getTopLeft(find.byType(Row).first).dx));
    expect(drawn.width, greaterThan(box.width));
    expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
  });

  testWidgets('without an address there is no copy icon', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: WalletSignerLine(text: 'MetaMask'))));
    expect(find.text('MetaMask'), findsOneWidget);
    expect(find.byIcon(Icons.copy_rounded), findsNothing);
  });
}
