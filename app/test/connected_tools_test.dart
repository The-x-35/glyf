import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/profile/brand_marks.dart';
import 'package:glyf/profile/connected_tools_screen.dart';

/// Connected tools' Trading group: Uniswap, Jupiter and Definitive.
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

  test('the partners, in order, and no 0G', () {
    expect(ConnectedToolsScreen.partnerTools.map((t) => t.title), ['Uniswap', 'Jupiter', 'Definitive']);
    expect(ConnectedToolsScreen.partnerTools.map((t) => t.brand), ['uniswap', 'jupiter', 'definitive']);
  });

  testWidgets('shows Uniswap, Jupiter and Definitive as on, each with its mark', (tester) async {
    phone(tester);
    // An older build's Private AI setting changes nothing here.
    shared = {'privateAI': true};
    await tester.pumpWidget(const MaterialApp(home: ConnectedToolsScreen()));
    await settle(tester);

    expect(find.text('Trading'), findsOneWidget);
    for (final id in ['tools:uniswap', 'tools:jupiter', 'tools:definitive']) {
      expect(byId(id), findsOneWidget, reason: id);
      expect(byId('$id:on'), findsOneWidget, reason: '$id on');
    }
    expect(find.text('Uniswap'), findsOneWidget);
    expect(find.text('Definitive'), findsOneWidget);
    expect(find.text('Flash'), findsOneWidget);
    for (final brand in ['uniswap', 'jupiter', 'definitive']) {
      expect(find.byWidgetPredicate((w) => w is BrandMark && w.brand == brand), findsOneWidget, reason: brand);
    }
    expect(byId('tools:zerog'), findsNothing);
    expect(find.text('0G'), findsNothing);
    expect(find.text('Private AI'), findsNothing);
  });
}
