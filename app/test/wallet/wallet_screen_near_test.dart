import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/near/hot_wallet.dart';
import 'package:glyf/wallet/wallet_screen.dart';

/// Profile › Wallet with HOT Wallet beside MetaMask and Phantom: its own
/// NEAR card, the account when connected, Disconnect that forgets only it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const bridge = MethodChannel('so.glyf/bridge');
  late Map<String, dynamic> shared;

  setUp(() {
    shared = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(bridge, (call) async {
      final args = (call.arguments as Map?)?.cast<String, Object?>() ?? const {};
      switch (call.method) {
        case 'readSharedSettings':
          return jsonEncode(shared);
        case 'writeSharedSettings':
          shared = jsonDecode(args['json'] as String) as Map<String, dynamic>;
          return true;
        case 'launchArgs':
          return <String>[];
      }
      return null;
    });
  });

  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(bridge, null));

  testWidgets('three cards side by side; NEAR shows the HOT account and Disconnect forgets only it', (tester) async {
    shared = {'nearAccount': 'arpit.near', 'nearPublicKey': 'ed25519:7xKX', 'nearWallet': 'hot', 'haptics': false};
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: WalletScreen()));
    await tester.pump();
    await tester.pump();
    expect(find.text('Ethereum'), findsOneWidget);
    expect(find.text('Solana'), findsOneWidget);
    expect(find.text('NEAR'), findsWidgets);
    expect(find.text('HOT Wallet · arpit.near'), findsOneWidget);
    await tester.tap(find.bySemanticsIdentifier('wallet:hot:disconnect'));
    await tester.pump();
    await tester.pump();
    expect(shared.keys.where((k) => k.startsWith('near')), isEmpty);
    expect(shared['haptics'], false);
    expect(HotWallet.account.value, isNull);
    expect(find.bySemanticsIdentifier('wallet:hot:connect'), findsOneWidget);
    expect(find.text('HOT Wallet'), findsOneWidget);
  });
}
