import 'catalog.dart';

/// Per-key recommendations: tap a free key, see what belongs on it.
/// Mnemonic first (the letter IS the memory aid), then persona picks.
abstract final class Recommend {
  static const Map<String, List<String>> _byLetter = {
    'c': ['connector:mockcal', 'rewrite.tighten'],
    'd': ['keyless.define', 'desi.hinglish'],
    'e': ['social.emotion', 'rewrite.emoji'],
    'f': ['desi.formalhindi', 'keyless.quote'],
    'g': ['keyless.wiki', 'glyf.summarize'],
    'h': ['social.hook', 'desi.hinglish'],
    'j': ['rewrite.emoji', 'social.reply'],
    'k': ['rewrite.tighten', 'glyf.summarize'],
    'm': ['keyless.stock', 'keyless.quote'],
    'n': ['surface:notes', 'social.reply'],
    'p': ['glyf.proofread', 'rewrite.polite'],
    'q': ['keyless.quote', 'keyless.weather'],
    'r': ['surface:tones', 'social.reply'],
    's': ['surface:vault', 'glyf.summarize'],
    't': ['surface:translate-hud', 'rewrite.tighten'],
    'u': ['glyf.summarize', 'rewrite.expand'],
    'w': ['keyless.weather', 'social.hook'],
    'x': ['social.xreply', 'rewrite.expand'],
  };

  /// Persona → the keys that suit them (used by onboarding).
  static const Map<String, Map<String, String>> personas = {
    'student': {
      'u': 'glyf.summarize',
      'x': 'rewrite.expand',
      'r': 'surface:tones',
    },
    'working': {
      'k': 'rewrite.tighten',
      'r': 'surface:tones',
      'c': 'connector:mockcal',
    },
    'creator': {
      'h': 'social.hook',
      'x': 'social.xreply',
      'j': 'rewrite.emoji',
    },
    'texting': {
      'j': 'rewrite.emoji',
      'e': 'social.emotion',
      'r': 'surface:tones',
    },
  };

  /// Top picks for a letter, excluding what's already bound anywhere.
  static List<GlyfMeta> forLetter(String letter, Map<String, String> bound) {
    final taken = bound.values.toSet();
    final ids = [
      ...(_byLetter[letter] ?? const []),
      // Fallbacks so every letter offers something.
      'rewrite.tone', 'social.reply', 'glyf.summarize',
    ];
    final seen = <String>{};
    final out = <GlyfMeta>[];
    for (final id in ids) {
      if (taken.contains(id) || !seen.add(id)) continue;
      out.add(Catalog.byId(id));
      if (out.length == 3) break;
    }
    return out;
  }
}
