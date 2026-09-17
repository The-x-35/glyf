/// Client-side catalog mirror (ids + display). The server's /glyf/catalog is
/// the source of truth (adds discloses/version); this list keeps binding UI
/// working offline. §13: definitions live server-side in Builder format.
class GlyfMeta {
  const GlyfMeta(this.id, this.title, this.subtitle, this.emoji);
  final String id;
  final String title;
  final String subtitle;
  final String emoji;
}

abstract final class Catalog {
  static const glyfs = [
    GlyfMeta('rewrite.polite', 'Make it polite',
        'Rewrite the draft with a courteous tone', '🤝'),
    GlyfMeta('rewrite.tighten', 'Tighten', 'Same message, half the words', '✂️'),
    GlyfMeta('rewrite.professional', 'Professional',
        'Polish for a work audience', '💼'),
    GlyfMeta('glyf.translate', 'Translate', 'Translate the draft', '🌐'),
    GlyfMeta('rewrite.emoji', 'Emoji-fy', 'Say it in emoji', '😊'),
    GlyfMeta('glyf.proofread', 'Proofread',
        'Fix grammar and spelling only', '✅'),
    GlyfMeta('dictation.clean', 'Clean dictation',
        'Strip fillers, fix punctuation', '🎙️'),
    GlyfMeta('dictation.formal', 'Formal dictation',
        'Dictation, elevated to formal text', '📝'),
    // M5 (§6.13 default map + step-engine glyfs)
    GlyfMeta('rewrite.tone', 'Tone shift', 'Rewrite in the tone you pick', '🎭'),
    GlyfMeta('rewrite.expand', 'Expand', 'Bullet thoughts → full prose', '📖'),
    GlyfMeta('glyf.summarize', 'Summarize', 'Long text → three lines', '🗜️'),
    GlyfMeta('social.reply', 'Smart reply', 'A warm reply to any message', '💬'),
    GlyfMeta('social.hook', 'Hook writer', 'Openers that stop the scroll', '🪝'),
    GlyfMeta('social.emotion', 'Emotion check', 'How will this land?', '💛'),
    GlyfMeta('social.xreply', 'Super X reply', 'A reply that earns the repost', '🐦'),
    GlyfMeta('desi.hinglish', 'Hinglish', 'Casual Hinglish rewrite', '🌶️'),
    GlyfMeta('desi.formalhindi', 'Shuddh Hindi', 'Formal, respectful Hindi', '🪷'),
    GlyfMeta('keyless.weather', 'Weather', 'Live conditions, no login', '⛅'),
    GlyfMeta('keyless.quote', 'Price check', 'Live crypto quote, no login', '📈'),
    GlyfMeta('keyless.define', 'Define', 'Dictionary, no login', '📖'),
    GlyfMeta('keyless.wiki', 'Wiki lookup', 'One-paragraph summary', '🌍'),
    GlyfMeta('keyless.stock', 'Stock check', 'Live quote, no login', '💹'),
    // In-keyboard surfaces + connectors (bindable, not runnable-from-app)
    GlyfMeta('surface:vault', 'Vault', 'Vault', '🗂️'),
    GlyfMeta('surface:translate-hud', 'Translate', 'Translate', '🌐'),
    GlyfMeta('surface:tones', 'Rewrite', 'Rewrite', '🎚️'),
    GlyfMeta('connector:mockcal', 'Calendar picker',
        'Drop an event into your text', '📅'),
    GlyfMeta('surface:notes', 'Notes',
        'Your notes, one hold away', '📝'),
  ];

  static GlyfMeta byId(String id) => glyfs.firstWhere(
        (g) => g.id == id,
        orElse: () => GlyfMeta(id, _customTitles[id] ?? id, 'Custom glyf', '✨'),
      );

  /// Display names for builder/hub glyfs, mirrored from shared settings
  /// (`customTitles`) by whoever loads settings — keeps byId() sync.
  static final Map<String, String> _customTitles = {};

  static void rememberCustomTitles(Map<String, dynamic>? titles) {
    if (titles == null) return;
    titles.forEach((k, v) {
      if (v is String) _customTitles[k] = v;
    });
  }

  /// Bindable-from-keyboard set (dictation runs from the mic flow, not keys).
  static List<GlyfMeta> get bindable =>
      glyfs.where((g) => !g.id.startsWith('dictation.')).toList();
}
