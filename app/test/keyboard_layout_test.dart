import 'dart:convert';

import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/profile/keyboard_screen.dart';

/// Keyboard › Layout: the letter layout picker and the number row, comma
/// and period switches. Untouched, the settings file keeps today's keyboard.
void main() {
  const bridge = MethodChannel('so.glyf/bridge');
  late Map<String, dynamic> stored;
  late List<String> writes;

  setUp(() {
    stored = {'keyTheme': 'site', 'themeBg': '', 'appearance': 'light'};
    writes = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(bridge, (call) async {
      switch (call.method) {
        case 'readSharedSettings':
          return jsonEncode(stored);
        case 'writeSharedSettings':
          final next = jsonDecode((call.arguments as Map)['json'] as String) as Map<String, dynamic>;
          writes.addAll(next.keys.where((k) => jsonEncode(next[k]) != jsonEncode(stored[k])));
          stored = next;
          return true;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(bridge, null);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> open(WidgetTester tester) async {
    // Tall enough that the whole page is built: nothing scrolls out of it.
    tester.view.physicalSize = const Size(1206, 26000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: KeyboardScreen()));
    await settle(tester);
  }

  Future<void> reveal(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
  }

  /// The switch on the row titled [title].
  Finder switchOf(String title) => find.descendant(
      of: find.ancestor(of: find.text(title), matching: find.byType(Row)).first,
      matching: find.byType(CupertinoSwitch));

  testWidgets('Layout shows QWERTY and every switch off, and writes nothing', (tester) async {
    await open(tester);
    await reveal(tester, find.text('Period beside space'));
    expect(find.text('Layout'), findsOneWidget);
    expect(find.text('Letters'), findsOneWidget);
    expect(find.text('QWERTY'), findsOneWidget);
    for (final t in ['Number row', 'Comma beside space', 'Period beside space']) {
      expect(find.text(t), findsOneWidget, reason: t);
      expect(tester.widget<CupertinoSwitch>(switchOf(t)).value, isFalse, reason: t);
    }
    expect(writes.where((k) => const {'keyLayout', 'commaKey', 'periodKey', 'numberRow'}.contains(k)), isEmpty);
    expect(stored.containsKey('keyLayout'), isFalse);
  });

  testWidgets('picking a layout saves its id and shows it', (tester) async {
    await open(tester);
    await reveal(tester, find.byKey(const ValueKey('choice:keyLayout')));
    await tester.tap(find.byKey(const ValueKey('choice:keyLayout')));
    await tester.pumpAndSettle();
    for (final name in ['QWERTY', 'QWERTZ', 'AZERTY', 'Colemak']) {
      expect(find.text(name), findsWidgets, reason: name);
    }
    expect(find.text('Dvorak'), findsNothing);
    await tester.tap(find.text('AZERTY').last);
    await tester.pumpAndSettle();
    await settle(tester);
    expect(stored['keyLayout'], 'azerty');
    expect(find.text('AZERTY'), findsOneWidget);
    expect(find.text('QWERTY'), findsNothing);
  });

  testWidgets('the comma and period switches save their own keys', (tester) async {
    await open(tester);
    await reveal(tester, find.text('Period beside space'));
    await tester.tap(switchOf('Comma beside space'));
    await settle(tester);
    expect(stored['commaKey'], isTrue);
    expect(stored.containsKey('periodKey'), isFalse);
    await tester.tap(switchOf('Period beside space'));
    await settle(tester);
    expect(stored['periodKey'], isTrue);
    await tester.tap(switchOf('Number row'));
    await settle(tester);
    expect(stored['numberRow'], isTrue);
  });

  testWidgets('Number row lives in Layout only, above Typing', (tester) async {
    await open(tester);
    expect(find.text('Number row'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Number row')).dy,
        lessThan(tester.getTopLeft(find.text('Typing')).dy));
    expect(tester.getTopLeft(find.text('Layout')).dy,
        lessThan(tester.getTopLeft(find.text('Number row')).dy));
  });

  testWidgets('an unknown saved layout reads as QWERTY', (tester) async {
    stored['keyLayout'] = 'dvorak';
    await open(tester);
    await reveal(tester, find.byKey(const ValueKey('choice:keyLayout')));
    expect(find.text('QWERTY'), findsOneWidget);
  });
}
