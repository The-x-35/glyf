import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/vault/vault_screen.dart';

/// A UPI detail added on the keyboard stays UPI when it is edited in the app
/// (the app's list of kinds had none, so its editor turned it into Other);
/// outside India a new detail is not offered UPI.
void main() {
  const bridge = MethodChannel('so.glyf/bridge');
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(bridge, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'vaultList':
          return jsonEncode({
            'fields': [
              {'id': 'f1', 'kind': 'upi', 'label': 'My UPI', 'value': 'sim@okaxis'},
            ],
            'snippets': [],
          });
        case 'notesList':
          return jsonEncode([]);
        case 'launchArgs':
          return <String>[];
        case 'vaultUpsertField':
          return true;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(bridge, null);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('a UPI detail is edited as UPI, and a new one is not offered UPI outside India', (tester) async {
    tester.platformDispatcher.localeTestValue = const Locale('en', 'US');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    await tester.pumpWidget(const MaterialApp(home: VaultScreen()));
    await settle(tester);

    await tester.tap(find.text('sim@okaxis'));
    await tester.pumpAndSettle();
    final dropdown = find.byType(DropdownButtonFormField<String>);
    expect(dropdown, findsOneWidget);
    expect(find.descendant(of: dropdown, matching: find.text('UPI')), findsOneWidget);
    expect(find.descendant(of: dropdown, matching: find.text('Other')), findsNothing);

    // Closed without saving; a new detail in the US offers no UPI.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    await tester.tap(find.text('Add').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.text('Wallet address'), findsWidgets);
    expect(find.text('UPI'), findsNothing);
    expect(calls.where((c) => c.method == 'vaultUpsertField'), isEmpty);
  });
}
