import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/wallet/wallet_secrets_screen.dart';

/// A 24-word phrase on the smallest phone: every number keeps clear of its
/// word, so "20 sort" never reads as "20sort".
void main() {
  const phrase = 'tonight analyst crunch buddy smile outer quote render ball surprise range travel '
      'lawsuit unknown grant bean worth quote sort sort bracket obvious during attack';

  testWidgets('a 24-word phrase shows every word with its number clear of it', (tester) async {
    tester.view.physicalSize = const Size(375 * 3, 667 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: RecoveryPhraseScreen(phrase: phrase)));
    final words = phrase.split(' ');
    for (var i = 0; i < words.length; i++) {
      final number = find.text('${i + 1}');
      expect(number, findsOneWidget);
      final word = find.text(words[i]);
      expect(word, findsWidgets);
      // Two digits of 12.5 pt semibold are about 15 pt wide: the word
      // starts at least 24 pt after its number does, never on top of it.
      final row = find.ancestor(of: number, matching: find.byType(Row)).first;
      final w = tester.getRect(find.descendant(of: row, matching: find.text(words[i])));
      expect(w.left - tester.getRect(number).left, greaterThanOrEqualTo(23.9),
          reason: 'number ${i + 1} crowds "${words[i]}" (${w.left - tester.getRect(number).left})');
    }
  });
}
