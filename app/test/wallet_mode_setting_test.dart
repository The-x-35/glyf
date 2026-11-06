import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/evm/evm_signer.dart';
import 'package:glyf/profile/keyboard_screen.dart';
import 'package:glyf/wallet/wallet_mode.dart';

/// Keyboard › Sign with: the one switch between the Glyf wallet and the
/// outside wallets, shown with the wallet, saved where the keyboard reads it.
void main() {
  const bridge = MethodChannel('so.glyf/bridge');
  late Map<String, dynamic> stored;

  setUp(() {
    stored = {'keyTheme': 'site', 'themeBg': '', 'appearance': 'light'};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(bridge, (call) async {
      switch (call.method) {
        case 'readSharedSettings':
          return jsonEncode(stored);
        case 'writeSharedSettings':
          stored = jsonDecode((call.arguments as Map)['json'] as String) as Map<String, dynamic>;
          return true;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(bridge, null);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1206, 26000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: KeyboardScreen()));
    await settle(tester);
  }

  testWidgets('no Sign with until the wallet is on', (tester) async {
    await open(tester);
    expect(find.byKey(const ValueKey('choice:walletMode')), findsNothing);
  });

  testWidgets('Sign with shows the Glyf wallet, and picking outside wallets routes both chains there', (tester) async {
    stored['walletEnabled'] = true;
    await open(tester);
    final row = find.byKey(const ValueKey('choice:walletMode'));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    expect(find.descendant(of: row, matching: find.text('Glyf wallet')), findsOneWidget);
    await tester.tap(row);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Phantom & MetaMask').last);
    await tester.pumpAndSettle();
    await settle(tester);
    expect(stored['walletMode'], 'external');
    expect(WalletModes.mode.value, WalletMode.external);
    expect(EvmSigner.kind.value, EvmSignerKind.metamask);
    expect(stored['evmSigner'], 'metamask');
    expect(find.descendant(of: row, matching: find.text('Phantom & MetaMask')), findsOneWidget);
  });
}
