import 'package:flutter/material.dart';

import '../core/bridge.dart';
import '../core/catalog.dart';
import '../core/glyf_api.dart';
import '../core/telemetry.dart';
import '../core/theme.dart';
import 'key_picker.dart';

/// One row of the Skills browser — a shipped glyf or a community one.
class Skill {
  Skill.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        name = j['name'] as String? ?? j['id'] as String,
        icon = j['icon'] as String? ?? '',
        category = j['category'] as String? ?? 'Community',
        author = j['author'] as String? ?? 'anonymous',
        official = j['official'] == true,
        installs = (j['installs'] as num?)?.toInt() ?? 0,
        discloses = (j['discloses'] as List?)?.cast<String>() ?? const [],
        version = (j['version'] as num?)?.toInt() ?? 1;

  /// A shipped glyf from the on-device catalog, for when the server is out
  /// of reach: still bindable, no counts, no categories.
  Skill.local(GlyfMeta g)
      : id = g.id,
        name = g.title,
        icon = '',
        category = '',
        author = 'Glyf',
        official = true,
        installs = 0,
        discloses = const [],
        version = 1;

  final String id;
  final String name;
  final String icon;
  final String category;
  final String author;
  final bool official;
  int installs;
  final List<String> discloses;
  final int version;

  GlyfMeta? get _meta {
    for (final g in Catalog.glyfs) {
      if (g.id == id) return g;
    }
    return null;
  }

  String get title => _meta?.title ?? name;
  String? get subtitle => _meta?.subtitle;
  String get emoji => _meta?.emoji ?? _iconEmoji[icon] ?? '✨';

  /// "Glyf · 12 installs", "by Maya" — a count only once there is one.
  String get byline {
    final who = official ? 'Glyf' : 'by $author';
    return installs > 0 ? '$who · ${installsLabel(installs)}' : who;
  }

  static const _iconEmoji = {
    'sparkles': '✨', 'globe': '🌐', 'translate': '🌐', 'quote': '💬',
    'bubble': '💬', 'pencil': '✏️', 'wand': '🪄', 'chart': '📈',
    'music': '🎵', 'heart': '💛', 'bolt': '⚡', 'book': '📖',
  };
}

String installsLabel(int n) {
  if (n == 1) return '1 install';
  if (n < 1000) return '$n installs';
  final k = n / 1000;
  final text = k >= 10 ? '${k.round()}' : k.toStringAsFixed(1).replaceAll('.0', '');
  return '${text}k installs';
}

/// Which key each glyf sits on, from shared settings.
Future<Map<String, String>> boundKeys() async {
  final settings = await GlyfBridge.sharedSettings();
  final bindings =
      (settings['bindings'] as Map<String, dynamic>?) ?? <String, dynamic>{};
  final byGlyf = <String, String>{};
  for (final e in bindings.entries) {
    if (e.value is String) byGlyf.putIfAbsent(e.value as String, () => e.key);
  }
  return byGlyf;
}

/// The Skills browser (Acti's community hub, Glyf's way): search, categories,
/// the people making skills, and one list of shipped + community skills.
class SkillsScreen extends StatefulWidget {
  const SkillsScreen({super.key});

  @override
  State<SkillsScreen> createState() => _SkillsScreenState();
}

class _SkillsScreenState extends State<SkillsScreen> {
  final _search = TextEditingController();
  List<Skill> _skills = [];
  List<String> _categories = [];
  List<Map<String, dynamic>> _creators = [];
  Map<String, String> _bound = {};
  String _category = 'All';
  bool _loading = true;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final bound = await boundKeys();
    try {
      final results = await Future.wait(
          [GlyfApi.skills(), GlyfApi.skillCreators()]);
      final body = results[0] as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _skills = (body['skills'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .map(Skill.fromJson)
            .toList();
        _categories = (body['categories'] as List? ?? []).cast<String>();
        _creators = results[1] as List<Map<String, dynamic>>;
        _bound = bound;
        _loading = false;
        _offline = false;
        if (_category != 'All' && !_categories.contains(_category)) {
          _category = 'All';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          if (_skills.isEmpty) {
            _skills = Catalog.bindable
                .where((g) =>
                    !g.id.startsWith('surface:') &&
                    !g.id.startsWith('connector:'))
                .map(Skill.local)
                .toList();
          }
          _categories = [];
          _category = 'All';
          _creators = [];
          _bound = bound;
          _loading = false;
          _offline = true;
        });
      }
    }
  }

  List<Skill> get _visible {
    final q = _search.text.trim().toLowerCase();
    return _skills.where((s) {
      if (_category != 'All' && s.category != _category) return false;
      if (q.isEmpty) return true;
      return s.title.toLowerCase().contains(q) ||
          s.author.toLowerCase().contains(q) ||
          (s.subtitle?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  Future<void> _open(Skill s) async {
    final added = await showSkillSheet(context, s, boundKey: _bound[s.id]);
    if (added) _load();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final browsing = _category == 'All' && _search.text.trim().isEmpty;
    return Scaffold(
      backgroundColor: Glass.bg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: Glass.ink,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
            children: [
              Row(children: [
                IconButton(
                  padding: EdgeInsets.zero,
                  alignment: Alignment.centerLeft,
                  icon: const Icon(Icons.arrow_back_ios_new,
                      size: 20, color: Glass.ink),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ]),
              const Text('Skills',
                  style: TextStyle(
                      color: Glass.ink,
                      fontSize: 28,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              _searchField(),
              const SizedBox(height: 12),
              if (_categories.isNotEmpty) _chips(),
              if (browsing && _creators.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text('Creators',
                    style: TextStyle(
                        color: Glass.ink,
                        fontSize: 20,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                _creatorsStrip(),
              ],
              const SizedBox(height: 18),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Center(
                      child: CircularProgressIndicator(
                          color: Glass.ink, strokeWidth: 2)),
                )
              else if (visible.isEmpty)
                _message(_search.text.trim().isEmpty
                    ? 'Nothing here yet'
                    : 'No skills match “${_search.text.trim()}”')
              else
                for (final s in visible)
                  SkillTile(
                    skill: s,
                    boundKey: _bound[s.id],
                    onTap: () => _open(s),
                  ),
              if (_offline && !_loading)
                _message('Server offline', action: 'Retry', onTap: _load),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchField() {
    return Semantics(
      identifier: 'skills:search',
      child: TextField(
        controller: _search,
        textInputAction: TextInputAction.search,
        style: const TextStyle(color: Glass.ink, fontSize: 16),
        decoration: InputDecoration(
          hintText: 'Search skills',
          hintStyle: const TextStyle(color: Glass.inkSoft),
          prefixIcon: const Icon(Icons.search, color: Glass.inkSoft, size: 21),
          suffixIcon: _search.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, color: Glass.inkSoft, size: 18),
                  onPressed: _search.clear,
                ),
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 13),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Glass.hairline),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Glass.hairline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Glass.ink),
          ),
        ),
      ),
    );
  }

  Widget _chips() {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length + 1,
        separatorBuilder: (_, i) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final c = i == 0 ? 'All' : _categories[i - 1];
          final selected = c == _category;
          return Semantics(
            identifier: 'skills:cat:$c',
            button: true,
            selected: selected,
            child: GestureDetector(
              onTap: () => setState(() => _category = c),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? Glass.pill : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                      color: selected ? Glass.pill : Glass.hairline),
                ),
                child: Text(c,
                    style: TextStyle(
                        color: selected ? Colors.white : Glass.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _creatorsStrip() {
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _creators.length,
        separatorBuilder: (_, i) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final c = _creators[i];
          final name = c['name'] as String? ?? 'anonymous';
          final skills = (c['skills'] as num?)?.toInt() ?? 0;
          final installs = (c['installs'] as num?)?.toInt() ?? 0;
          return GestureDetector(
            onTap: () {
              _search.text = name;
              _search.selection =
                  TextSelection.collapsed(offset: name.length);
            },
            child: Container(
              width: 112,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(Glass.radiusCard - 4),
                border: Border.all(color: Glass.hairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                        color: Glass.pill, shape: BoxShape.circle),
                    child: Text(name.characters.first.toUpperCase(),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                  ),
                  const Spacer(),
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Glass.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  Text(
                      installs > 0
                          ? installsLabel(installs)
                          : '$skills skill${skills == 1 ? '' : 's'}',
                      maxLines: 1,
                      style: const TextStyle(
                          color: Glass.inkSoft, fontSize: 11.5)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _message(String text, {String? action, VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.only(top: 36),
      child: Column(children: [
        Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Glass.inkSoft, fontSize: 14)),
        if (action != null)
          TextButton(
            onPressed: onTap,
            child: Text(action,
                style: const TextStyle(
                    color: Glass.ink, fontWeight: FontWeight.w700)),
          ),
      ]),
    );
  }
}

/// A skill row: icon, name, who made it, and Get — or the key it's on.
class SkillTile extends StatelessWidget {
  const SkillTile(
      {super.key, required this.skill, this.boundKey, required this.onTap});

  final Skill skill;
  final String? boundKey;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        identifier: 'skills:row:${skill.id}',
        button: true,
        child: GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          onTap: onTap,
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFF2F3F7),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Text(skill.emoji, style: const TextStyle(fontSize: 22)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(skill.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Glass.ink,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 1),
                    Text(skill.byline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Glass.inkSoft, fontSize: 12.5)),
                  ]),
            ),
            const SizedBox(width: 10),
            if (boundKey != null)
              _keycap(boundKey!)
            else
              Semantics(
                identifier: 'skills:get:${skill.id}',
                button: true,
                child: GestureDetector(
                  onTap: onTap,
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Glass.pill,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text('Get',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _keycap(String letter) {
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Glass.hairline),
        boxShadow: const [
          BoxShadow(color: Color(0x14000000), offset: Offset(0, 1)),
        ],
      ),
      child: Text(letter.toUpperCase(),
          style: const TextStyle(
              color: Glass.ink, fontSize: 14, fontWeight: FontWeight.w700)),
    );
  }
}

/// Detail + consent: what the skill reads, verbatim (§6.8/§6.9), then Get →
/// pick a key → bound. Returns true when the skill landed on a key.
Future<bool> showSkillSheet(BuildContext context, Skill s,
    {String? boundKey}) async {
  final get = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(Glass.radiusSheet))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F3F7),
                  borderRadius: BorderRadius.circular(19),
                ),
                child: Text(s.emoji, style: const TextStyle(fontSize: 30)),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(s.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Glass.ink,
                      fontSize: 21,
                      fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 8),
            Center(
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                _chip(s.category),
                _chip(s.official ? 'Glyf' : 'by ${s.author}'),
                if (s.installs > 0) _chip(installsLabel(s.installs)),
              ]),
            ),
            if (s.subtitle != null) ...[
              const SizedBox(height: 14),
              Text(s.subtitle!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Glass.inkSoft, fontSize: 14.5, height: 1.4)),
            ],
            if (s.discloses.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Access',
                  style: TextStyle(
                      color: Glass.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              for (final d in s.discloses)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    const Icon(Icons.remove_red_eye_outlined,
                        size: 15, color: Glass.inkSoft),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(d,
                            style: const TextStyle(
                                color: Glass.ink, fontSize: 13.5))),
                  ]),
                ),
            ],
            const SizedBox(height: 18),
            Semantics(
              identifier: 'skills:add',
              button: true,
              child: PillButton(
                label: boundKey == null
                    ? 'Get'
                    : 'On ${boundKey.toUpperCase()} — move to another key',
                onPressed: () => Navigator.pop(ctx, true),
              ),
            ),
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel',
                    style: TextStyle(color: Glass.inkSoft))),
          ],
        ),
      ),
    ),
  );
  if (get != true || !context.mounted) return false;

  if (boundKey == null) {
    try {
      final res = await GlyfApi.skillGet(s.id);
      final installs = (res['installs'] as num?)?.toInt();
      if (installs != null) s.installs = installs;
      Telemetry.log('skill_get', {'glyfId': s.id, 'official': s.official});
    } on GlyfApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
      return false;
    } catch (_) {
      // Shipped skills run without the hub — only the count goes unrecorded.
      // A community skill has to be installed server-side to run at all.
      if (!s.official) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Couldn't reach Glyf — try again")));
        }
        return false;
      }
    }
  }
  if (!context.mounted) return false;

  final letter = await pickKey(context, title: 'Put “${s.title}” on…');
  if (letter == null) return false;
  await bindGlyf(
      letter: letter,
      glyfId: s.id,
      displayName: s.official ? null : s.title);
  if (boundKey != null && boundKey != letter) {
    // Moving, not copying: the old key lets go of it.
    await GlyfBridge.updateSharedSettings((st) {
      final b = Map<String, dynamic>.from(
          (st['bindings'] as Map<String, dynamic>?) ?? {});
      if (b[boundKey] == s.id) b.remove(boundKey);
      st['bindings'] = b;
      return st;
    });
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Hold ${letter.toUpperCase()} fires ${s.title}'),
      duration: const Duration(seconds: 2),
    ));
  }
  return true;
}

Widget _chip(String text) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0xFFF2F3F7),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(text,
        style: const TextStyle(
            color: Glass.inkSoft, fontSize: 12, fontWeight: FontWeight.w600)),
  );
}
