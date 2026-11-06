import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/profile/brand_marks.dart';
import 'package:glyf/profile/connected_tools_screen.dart';

/// Connected tools' Trading and AI group (ETHGlobal Mumbai): Uniswap,
/// Definitive and, on the Private AI build, 0G.
void main() {
  const bridge = MethodChannel('so.glyf/bridge');
  late Map<String, dynamic> shared;

  setUp(() {
    shared = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(bridge, (call) async {
      switch (call.method) {
        case 'readSharedSettings':
          return jsonEncode(shared);
        case 'calendarStatus':
          return jsonEncode({'enabled': false, 'permission': 'notDetermined'});
        case 'googleStatus':
          return {'connected': false};
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(bridge, null);
  });

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Finder byId(String id) => find.byWidgetPredicate((w) => w is Semantics && w.properties.identifier == id);

  test('the partners, in order, with 0G only on the Private AI build', () {
    expect(ConnectedToolsScreen.partnerTools(zeroG: true).map((t) => t.title), ['Uniswap', 'Jupiter', 'Definitive', '0G']);
    expect(ConnectedToolsScreen.partnerTools(zeroG: false).map((t) => t.title), ['Uniswap', 'Jupiter', 'Definitive']);
    expect(ConnectedToolsScreen.partnerTools(zeroG: true).map((t) => t.brand), ['uniswap', 'jupiter', 'definitive', 'zerog']);
  });

  testWidgets('shows Uniswap, Definitive and 0G as on, each with its mark', (tester) async {
    phone(tester);
    await tester.pumpWidget(const MaterialApp(home: ConnectedToolsScreen(zeroG: true)));
    await settle(tester);

    expect(find.text('Trading and AI'), findsOneWidget);
    for (final id in ['tools:uniswap', 'tools:jupiter', 'tools:definitive', 'tools:zerog']) {
      expect(byId(id), findsOneWidget, reason: id);
      expect(byId('$id:on'), findsOneWidget, reason: '$id on');
    }
    expect(find.text('Uniswap'), findsOneWidget);
    expect(find.text('Definitive'), findsOneWidget);
    expect(find.text('Flash'), findsOneWidget);
    expect(find.text('0G'), findsOneWidget);
    expect(find.text('Private AI'), findsOneWidget);
    for (final brand in ['uniswap', 'jupiter', 'definitive', 'zerog']) {
      expect(find.byWidgetPredicate((w) => w is BrandMark && w.brand == brand), findsOneWidget, reason: brand);
    }
  });

  testWidgets('0G reads Off when Private AI is turned off', (tester) async {
    phone(tester);
    shared = {'privateAI': false};
    await tester.pumpWidget(const MaterialApp(home: ConnectedToolsScreen(zeroG: true)));
    await settle(tester);
    expect(byId('tools:zerog'), findsOneWidget);
    expect(byId('tools:zerog:on'), findsNothing);
    expect(find.descendant(of: byId('tools:zerog'), matching: find.text('Off')), findsOneWidget);
    expect(byId('tools:uniswap:on'), findsOneWidget);
  });

  testWidgets('a build without Private AI has no 0G row', (tester) async {
    phone(tester);
    await tester.pumpWidget(const MaterialApp(home: ConnectedToolsScreen(zeroG: false)));
    await settle(tester);
    expect(byId('tools:uniswap'), findsOneWidget);
    expect(byId('tools:definitive'), findsOneWidget);
    expect(byId('tools:zerog'), findsNothing);
    expect(find.text('0G'), findsNothing);
  });
}
