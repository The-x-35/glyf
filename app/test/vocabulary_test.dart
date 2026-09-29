import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/vocab/vocabulary_screen.dart';

/// Tone profile moved off Profile into Vocabulary, beside My words: both are
/// what the keyboard learned from you.
void main() {
  const bridge = MethodChannel('so.glyf/bridge');
  const hint = 'The user tends to prefer writing that is brief and to the point.';
  // Written for the model; shown to the person about themselves.
  const shown = 'You like writing that’s brief and to the point.';
  late Map<String, dynamic> tone;
  late List<String> calls;

  setUp(() {
    tone = {'accepted': {'concise': 4}, 'discarded': {}, 'hint': hint};
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(bridge, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'toneProfile':
          return jsonEncode(tone);
        case 'toneReset':
          tone = {'accepted': {}, 'discarded': {}, 'hint': ''};
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

  testWidgets('Vocabulary shows the tone it learned and resets it', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: VocabularyScreen()));
    await settle(tester);

    final card = find.byWidgetPredicate((w) => w is Semantics && w.properties.identifier == 'vocab:tone');
    expect(find.descendant(of: card, matching: find.text('Tone profile')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text(shown)), findsOneWidget);

    await tester.tap(find.descendant(of: card, matching: find.byIcon(Icons.more_horiz)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset tone'));
    await tester.pumpAndSettle();
    await settle(tester);

    expect(calls, contains('toneReset'));
    expect(find.text(shown), findsNothing);
    expect(find.descendant(of: card, matching: find.text('Learning from your edits')), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
