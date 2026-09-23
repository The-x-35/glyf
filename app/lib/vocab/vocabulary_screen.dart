import 'dart:convert';

import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../core/bridge.dart';
import '../core/glyf_api.dart';
import '../core/telemetry.dart';
import '../core/theme.dart';

/// A set of words the keyboard should know: shipped (assets/vocab/packs.json)
/// or made from a description (vocab-custom.json in the shared bridge).
class VocabPack {
  VocabPack.fromJson(Map<String, dynamic> j, {this.custom = false})
      : id = j['id'] as String,
        name = j['name'] as String? ?? '',
        emoji = j['emoji'] as String? ?? '✨',
        group = j['group'] as String? ?? 'Made for you',
        words = (j['words'] as List? ?? const []).cast<String>(),
        phrases = (j['phrases'] as List? ?? const []).cast<String>();

  VocabPack.made({
    required this.id,
    required this.name,
    required this.words,
    required this.phrases,
  })  : emoji = '✨',
        group = 'Made for you',
        custom = true;

  final String id;
  final String name;
  final String emoji;
  final String group;
  final List<String> words;
  final List<String> phrases;
  final bool custom;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'group': group,
        'words': words,
        'phrases': phrases,
      };
}

/// A word the keyboard has learned from typing (or that was added here).
class LearnedWord {
  const LearnedWord(this.form, this.uses, this.added);
  final String form;
  final int uses;
  final bool added;
}

/// Vocabulary: packs of words by kind (work, local language, fun), what the
/// keyboard learned from you, and packs made from a description. Everything
/// the keyboard learns stays on the device.
class VocabularyScreen extends StatefulWidget {
  const VocabularyScreen({super.key});

  @override
  State<VocabularyScreen> createState() => _VocabularyScreenState();
}

class _VocabularyScreenState extends State<VocabularyScreen> {
  static const _groups = ['Professional', 'Local language', 'Fun'];

  List<VocabPack> _packs = [];
  List<VocabPack> _custom = [];
  Set<String> _enabled = {};
  bool _learning = true;
  List<LearnedWord> _learned = [];
  bool _loading = true;

  final _describe = TextEditingController();
  bool _making = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _describe.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final raw = await rootBundle.loadString('assets/vocab/packs.json');
    final shipped = ((jsonDecode(raw) as Map<String, dynamic>)['packs'] as List)
        .cast<Map<String, dynamic>>()
        .map(VocabPack.fromJson)
        .toList();
    final custom = ((await GlyfBridge.vocabCustom())['packs'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map((j) => VocabPack.fromJson(j, custom: true))
        .toList();
    final settings = await GlyfBridge.sharedSettings();
    final words = await GlyfBridge.typingWords();
    if (!mounted) return;
    setState(() {
      _packs = shipped;
      _custom = custom;
      // Never chosen yet: the keyboards start phones set to India on Hinglish.
      final region = WidgetsBinding.instance.platformDispatcher.locale.countryCode;
      _enabled = ((settings['vocabPacks'] as List?) ??
              (region == 'IN' ? const ['local.hinglish'] : const []))
          .cast<String>()
          .toSet();
      _learning = settings['vocabLearning'] != false;
      _learned = _learnedFrom(words);
      _loading = false;
    });
  }

  /// Words the keyboard treats as yours: typed twice, kept after a
  /// correction, or added here — most used first.
  List<LearnedWord> _learnedFrom(Map<String, dynamic>? json) {
    if (json == null) return [];
    final blocked = ((json['blocked'] as List?) ?? const []).cast<String>().toSet();
    final out = <LearnedWord>[];
    for (final w in (json['words'] as List? ?? const []).cast<Map<String, dynamic>>()) {
      final key = w['k'] as String? ?? '';
      final total = (w['t'] as num?)?.toInt() ?? 0;
      final kept = (w['kept'] as num?)?.toInt() ?? 0;
      final added = w['added'] == true;
      if (blocked.contains(key) || !(total >= 2 || kept > 0 || added)) continue;
      out.add(LearnedWord(w['f'] as String? ?? key, total, added));
    }
    out.sort((a, b) => b.uses.compareTo(a.uses));
    return out;
  }

  Future<void> _setPack(String id, bool on) async {
    setState(() => on ? _enabled.add(id) : _enabled.remove(id));
    await GlyfBridge.updateSharedSettings((s) {
      s['vocabPacks'] = _enabled.toList()..sort();
      return s;
    });
    Telemetry.log('vocab_pack', {'pack': id, 'on': on});
  }

  Future<void> _setLearning(bool on) async {
    setState(() => _learning = on);
    await GlyfBridge.updateSharedSettings((s) {
      s['vocabLearning'] = on;
      return s;
    });
  }

  Future<void> _forget(LearnedWord w) async {
    await GlyfBridge.typingEdit('forget', w.form);
    setState(() => _learned.remove(w));
  }

  Future<void> _addWord() async {
    final ctrl = TextEditingController();
    final word = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Glass.radiusSheet))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(22, 22, 22, 14 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Add a word',
              style: TextStyle(color: Glass.ink, fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          Semantics(
            identifier: 'vocab:add-field',
            child: TextField(
              controller: ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.none,
              autocorrect: false,
              style: const TextStyle(color: Glass.ink, fontSize: 17),
              decoration: _fieldDecoration('Anvika, Zomato, acha…'),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
          ),
          const SizedBox(height: 14),
          PillButton(label: 'Add', onPressed: () => Navigator.pop(ctx, ctrl.text)),
        ]),
      ),
    );
    final w = word?.trim() ?? '';
    if (w.isEmpty || w.length > 32 || w.contains(RegExp(r'[\d@/:]'))) return;
    await GlyfBridge.typingEdit('add', w);
    setState(() {
      _learned.removeWhere((l) => l.form.toLowerCase() == w.toLowerCase());
      _learned.insert(0, LearnedWord(w, 0, true));
    });
  }

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Forget everything learned?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Forget', style: TextStyle(color: Glass.danger))),
        ],
      ),
    );
    if (ok != true) return;
    await GlyfBridge.typingEdit('reset');
    setState(() => _learned = []);
  }

  Future<void> _make() async {
    final description = _describe.text.trim();
    if (description.length < 3 || _making) return;
    setState(() => _making = true);
    try {
      final res = await GlyfApi.vocabGenerate(description);
      if (!mounted) return;
      final pack = VocabPack.made(
        id: 'custom.${DateTime.now().millisecondsSinceEpoch}',
        name: res['name'] as String? ?? 'My pack',
        words: (res['words'] as List? ?? const []).cast<String>(),
        phrases: (res['phrases'] as List? ?? const []).cast<String>(),
      );
      final saved = await _review(pack);
      if (saved != null) {
        _custom.add(saved);
        await _saveCustom();
        await _setPack(saved.id, true);
        _describe.clear();
      }
    } on GlyfApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack("Couldn't reach Glyf. Try again.");
    } finally {
      if (mounted) setState(() => _making = false);
    }
  }

  Future<void> _saveCustom() => GlyfBridge.saveVocabCustom({
        'updatedAt': DateTime.now().millisecondsSinceEpoch.toDouble(),
        'packs': _custom.map((p) => p.toJson()).toList(),
      });

  Future<void> _deleteCustom(VocabPack p) async {
    setState(() {
      _custom.removeWhere((c) => c.id == p.id);
      _enabled.remove(p.id);
    });
    await _saveCustom();
    await GlyfBridge.updateSharedSettings((s) {
      s['vocabPacks'] = _enabled.toList()..sort();
      return s;
    });
  }

  /// Review a made pack: tap a word to drop it, then save.
  Future<VocabPack?> _review(VocabPack pack) {
    final words = List<String>.from(pack.words);
    final name = TextEditingController(text: pack.name);
    return showModalBottomSheet<VocabPack>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Glass.radiusSheet))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(22, 22, 22, 14 + MediaQuery.of(ctx).viewInsets.bottom),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(
                  controller: name,
                  style: const TextStyle(color: Glass.ink, fontSize: 20, fontWeight: FontWeight.w800),
                  decoration: const InputDecoration(border: InputBorder.none, isDense: true),
                ),
                Text('${words.length} words',
                    style: const TextStyle(color: Glass.inkSoft, fontSize: 13)),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final w in words)
                        _wordChip(w, onRemove: () => setSheet(() => words.remove(w))),
                    ]),
                  ),
                ),
                const SizedBox(height: 16),
                Semantics(
                  identifier: 'vocab:save-pack',
                  child: PillButton(
                    label: 'Save pack',
                    onPressed: words.isEmpty
                        ? null
                        : () => Navigator.pop(
                            ctx,
                            VocabPack.made(
                              id: pack.id,
                              name: name.text.trim().isEmpty ? pack.name : name.text.trim(),
                              words: words,
                              phrases: pack.phrases,
                            )),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  void _openPack(VocabPack p) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Glass.radiusSheet))),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Text(p.emoji, style: const TextStyle(fontSize: 26)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(p.name,
                      style: const TextStyle(color: Glass.ink, fontSize: 21, fontWeight: FontWeight.w800)),
                ),
                if (p.custom)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Glass.danger),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _deleteCustom(p);
                    },
                  ),
              ]),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(spacing: 6, runSpacing: 6, children: [for (final w in p.words) _wordChip(w)]),
                    if (p.phrases.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      for (final phrase in p.phrases)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(phrase, style: const TextStyle(color: Glass.inkSoft, fontSize: 14.5)),
                        ),
                    ],
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Glass.bg,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: Glass.ink, strokeWidth: 2))
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                children: [
                  Row(children: [
                    IconButton(
                      padding: EdgeInsets.zero,
                      alignment: Alignment.centerLeft,
                      icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: Glass.ink),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ]),
                  const Text('Vocabulary',
                      style: TextStyle(color: Glass.ink, fontSize: 28, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 16),
                  _myWordsCard(),
                  const SizedBox(height: 22),
                  _makeCard(),
                  if (_custom.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    _groupLabel('Made for you'),
                    for (final p in _custom) _packTile(p),
                  ],
                  for (final g in _groups) ...[
                    const SizedBox(height: 22),
                    _groupLabel(g),
                    for (final p in _packs.where((p) => p.group == g)) _packTile(p),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _groupLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10, left: 2),
        child: Text(text,
            style: const TextStyle(color: Glass.ink, fontSize: 20, fontWeight: FontWeight.w700)),
      );

  Widget _myWordsCard() {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(
            child: Text('My words',
                style: TextStyle(color: Glass.ink, fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          Text('${_learned.length}', style: const TextStyle(color: Glass.inkSoft, fontSize: 14)),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz, color: Glass.ink),
            color: Colors.white,
            onSelected: (v) => v == 'reset' ? _reset() : null,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'reset', child: Text('Forget everything learned')),
            ],
          ),
        ]),
        Row(children: [
          const Expanded(
            child: Text('Learn as I type', style: TextStyle(color: Glass.ink, fontSize: 15)),
          ),
          Semantics(
            identifier: 'vocab:learning',
            child: CupertinoSwitch(value: _learning, activeTrackColor: Glass.ink, onChanged: _setLearning),
          ),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final w in _learned.take(60)) _wordChip(w.form, onRemove: () => _forget(w)),
          Semantics(
            identifier: 'vocab:add-word',
            button: true,
            child: GestureDetector(
              onTap: _addWord,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(color: Glass.pill, borderRadius: BorderRadius.circular(16)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add, size: 16, color: Colors.white),
                  SizedBox(width: 4),
                  Text('Add', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _makeCard() {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Make a pack',
            style: TextStyle(color: Glass.ink, fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Semantics(
          identifier: 'vocab:describe',
          child: TextField(
            controller: _describe,
            minLines: 2,
            maxLines: 4,
            maxLength: 500,
            style: const TextStyle(color: Glass.ink, fontSize: 15),
            decoration: _fieldDecoration('Cardiologist in Pune, texts in Hinglish, plays BGMI'),
          ),
        ),
        const SizedBox(height: 4),
        Semantics(
          identifier: 'vocab:make',
          child: PillButton(label: _making ? 'Making…' : 'Make words', onPressed: _making ? null : _make),
        ),
      ]),
    );
  }

  Widget _packTile(VocabPack p) {
    final on = _enabled.contains(p.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        identifier: 'vocab:pack:${p.id}',
        child: GlassCard(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          onTap: () => _openPack(p),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: const Color(0xFFF2F3F7), borderRadius: BorderRadius.circular(13)),
              child: Text(p.emoji, style: const TextStyle(fontSize: 22)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.name,
                    style: const TextStyle(color: Glass.ink, fontSize: 15.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 1),
                Text(p.words.take(4).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Glass.inkSoft, fontSize: 12.5)),
              ]),
            ),
            CupertinoSwitch(
              value: on,
              activeTrackColor: Glass.ink,
              onChanged: (v) => _setPack(p.id, v),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _wordChip(String word, {VoidCallback? onRemove}) {
    return Container(
      padding: EdgeInsets.fromLTRB(12, 6, onRemove == null ? 12 : 6, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Glass.hairline),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(word, style: const TextStyle(color: Glass.ink, fontSize: 14)),
        if (onRemove != null)
          GestureDetector(
            onTap: onRemove,
            child: const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(Icons.close, size: 15, color: Glass.inkSoft),
            ),
          ),
      ]),
    );
  }

  InputDecoration _fieldDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Glass.inkSoft),
        filled: true,
        fillColor: const Color(0xFFF6F7F9),
        counterText: '',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );
}
