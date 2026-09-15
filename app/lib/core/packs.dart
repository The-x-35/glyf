/// §6.14 — Glyf Packs: curated key maps you apply in one tap. Applying merges
/// bindings; a diff sheet shows exactly which keys change before anything is
/// written (bindings are the user's — never clobber silently).
class GlyfPack {
  const GlyfPack(this.id, this.name, this.tagline, this.emoji, this.bindings);
  final String id;
  final String name;
  final String tagline;
  final String emoji;

  /// key letter → glyf id / surface: / connector: binding.
  final Map<String, String> bindings;
}

abstract final class Packs {
  static const all = [
    GlyfPack('writer', 'Writer', 'Polish, tighten, tone', '✍️', {
      'p': 'glyf.proofread',
      'k': 'rewrite.tighten',
      'u': 'glyf.summarize',
      'r': 'surface:tones',
    }),
    GlyfPack('operator', 'Operator', 'Live answers while you type', '⚡', {
      'w': 'keyless.weather',
      'q': 'keyless.quote',
      'c': 'connector:mockcal',
      's': 'surface:vault',
    }),
    GlyfPack('social', 'Social', 'Replies that land', '💬', {
      'x': 'social.xreply',
      'e': 'social.emotion',
      'h': 'social.hook',
      'j': 'rewrite.emoji',
    }),
    GlyfPack('desi', 'Desi', 'Hinglish + shuddh Hindi', '🇮🇳', {
      'd': 'desi.hinglish',
      'f': 'desi.formalhindi',
      't': 'surface:translate-hud',
      'r': 'surface:tones',
    }),
  ];

  static GlyfPack byId(String id) => all.firstWhere((p) => p.id == id);

  /// Keys this pack would REBIND away from something else the user has.
  static Map<String, String> conflicts(
      GlyfPack pack, Map<String, dynamic> currentBindings) {
    final out = <String, String>{};
    pack.bindings.forEach((key, glyfId) {
      final existing = currentBindings[key] as String?;
      if (existing != null && existing != glyfId) out[key] = existing;
    });
    return out;
  }
}
