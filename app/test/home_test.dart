import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/home/home_tab.dart';

void main() {
  const bridge = MethodChannel('so.glyf/bridge');
  var enabled = false;

  setUp(() {
    enabled = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(bridge, (call) async {
      switch (call.method) {
        case 'keyboardEnabled':
        case 'keyboardSelected':
          return enabled;
        case 'readKeyboardPing':
          return enabled ? jsonEncode({'hasFullAccess': true}) : null;
        case 'readSharedSettings':
          return '{}';
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

  testWidgets('what’s typed in the try field, and its focus, outlive setup finishing', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HomeTab())));
    await settle(tester);
    expect(find.text('Keyboard enabled'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'hello there');
    enabled = true;
    // The next poll sees the keyboard live and the setup card goes.
    await tester.pump(const Duration(seconds: 2));
    await settle(tester);

    expect(find.text('Keyboard enabled'), findsNothing);
    expect(find.text('hello there'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus, isTrue);

    await tester.pumpWidget(const SizedBox());
  });
}
