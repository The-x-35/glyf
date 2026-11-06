import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/profile/keyboard_screen.dart';
import 'package:glyf/wallet/wallet_mode.dart';

/// The one switch between the Glyf wallet and the outside wallets: on the
/// Wallet page (not in Keyboard settings), saved where the keyboard reads it.
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

  testWidgets('Keyboard settings have no Sign with: the switch lives on the Wallet page', (tester) async {
    stored['walletEnabled'] = true;
    await open(tester);
    expect(find.byKey(const ValueKey('choice:walletMode')), findsNothing);
  });

  test('the Wallet page switch saves where the keyboard reads it, and routes both chains', () async {
    await WalletModes.set(WalletMode.external);
    expect(stored['walletMode'], 'external');
    expect(WalletModes.route(solana: true, mode: WalletModes.mode.value).signer, WalletSigner.phantom);
    expect(WalletModes.route(solana: false, mode: WalletModes.mode.value).signer, WalletSigner.metamask);
    await WalletModes.set(WalletMode.internal);
    expect(stored['walletMode'], 'internal');
    expect(WalletModes.route(solana: true, mode: WalletModes.mode.value, glyfSolana: 'S').signer, WalletSigner.glyf);
  });
}
