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

  testWidgets('without an address there is no copy icon', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: WalletSignerLine(text: 'MetaMask'))));
    expect(find.text('MetaMask'), findsOneWidget);
    expect(find.byIcon(Icons.copy_rounded), findsNothing);
  });
}
