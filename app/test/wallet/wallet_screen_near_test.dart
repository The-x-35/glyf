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

  testWidgets('the NEAR card’s Group pot row: its value and nothing under it, saved as nearPot', (tester) async {
    shared = {'nearAccount': 'arpit.near', 'nearPublicKey': 'ed25519:7xKX', 'nearWallet': 'hot', 'haptics': false};
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: WalletScreen()));
    await tester.pump();
    await tester.pump();

    final row = find.bySemanticsIdentifier('wallet:near:pot');
    expect(find.descendant(of: row, matching: find.text('Group pot')), findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('Add')), findsOneWidget);
    // Just the label and its value: no sentence under the row.
    expect(find.descendant(of: row, matching: find.byType(Text)), findsNWidgets(2));
    // Under the NEAR account, in its card.
    expect(tester.getTopLeft(row).dy, greaterThan(tester.getTopLeft(find.text('HOT Wallet · arpit.near')).dy));

    await tester.tap(row);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'alice.near');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('A pot is a Sputnik DAO, like trip.sputnik-dao.near'), findsOneWidget);
    expect(shared.containsKey('nearPot'), isFalse);

    await tester.enterText(find.byType(TextField), 'Trip');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(shared['nearPot'], 'trip.sputnik-dao.near');
    // What else was saved stays.
    expect(shared['nearAccount'], 'arpit.near');
    expect(shared['haptics'], false);
    expect(find.descendant(of: row, matching: find.text('trip.sputnik-dao.near')), findsOneWidget);

    // Saved empty, it is forgotten.
    await tester.tap(row);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(shared.containsKey('nearPot'), isFalse);
    expect(find.descendant(of: row, matching: find.text('Add')), findsOneWidget);
  });

  testWidgets('the Group pot row shows with no NEAR account connected too', (tester) async {
    shared = {'nearPot': 'build.sputnik-dao.near'};
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: WalletScreen()));
    await tester.pump();
    await tester.pump();
    expect(find.bySemanticsIdentifier('wallet:hot:connect'), findsOneWidget);
    expect(find.descendant(of: find.bySemanticsIdentifier('wallet:near:pot'), matching: find.text('build.sputnik-dao.near')),
        findsOneWidget);
  });
}
