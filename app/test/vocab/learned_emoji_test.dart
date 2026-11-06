import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/vocab/vocabulary_screen.dart';

void main() {
  test('My words › Emoji lists the habits the keyboard offers, most used first', () {
    final list = LearnedEmoji.from({
      'emoji': [
        {'x': 'you', 'e': '❤️❤️❤️', 'c': 2.0, 't': 2},
        {'x': 'haha', 'e': '😂', 'c': 5.0, 't': 5},
        {'x': 'thanks', 'e': '🙏', 'c': 1.0, 't': 1}, // once is not a habit yet
        {'x': '', 'e': '🔥', 't': 9},
      ],
    });
    expect([for (final e in list) '${e.after} ${e.run} ${e.uses}'], ['haha 😂 5', 'you ❤️❤️❤️ 2']);
    expect(LearnedEmoji.from(null), isEmpty);
    expect(LearnedEmoji.from({'words': []}), isEmpty);
  });
}
