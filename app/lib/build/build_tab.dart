import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/bridge.dart';
import '../core/catalog.dart';
import '../core/glyf_api.dart';
import '../core/packs.dart';
import '../core/telemetry.dart';
import '../core/theme.dart';
import 'builder_screen.dart';
import 'key_picker.dart';
import 'skills_screen.dart';

/// Build — Acti-hub style: the Builder up top, §6.14 Packs, your own glyfs,
/// then Skills (shipped + community, most-installed first) with the full
/// browser one tap away. Skill → sheet with the §6.8 `discloses` verbatim
/// and Get.
class BuildTab extends StatefulWidget {
  const BuildTab({super.key, this.activeTab});

  /// The shell's selected-tab notifier — tabs live in an IndexedStack, so
  /// this is the "became visible again" signal (fresh MINE/Hub on return).
  final ValueListenable<int>? activeTab;

  @override
  State<BuildTab> createState() => _BuildTabState();
}

class _BuildTabState extends State<BuildTab> {
  List<Map<String, dynamic>> _mine = [];
  List<Skill> _skills = [];
  Map<String, String> _bound = {};
  bool _serverDown = false;

  static const _previewCount = 5;

  @override
  void initState() {
    super.initState();
    _refresh();
    widget.activeTab?.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    widget.activeTab?.removeListener(_onTabChanged);
    super.dispose();
  }

  void _onTabChanged() {
    if (widget.activeTab?.value == 1) _refresh();
  }

  Future<void> _refresh() async {
    final settings = await GlyfBridge.sharedSettings();
    Catalog.rememberCustomTitles(
        settings['customTitles'] as Map<String, dynamic>?);
    final bound = await boundKeys();
    if (mounted) setState(() => _bound = bound);
    try {
      final results = await Future.wait([GlyfApi.myGlyfs(), GlyfApi.skills()]);
      final skills = ((results[1] as Map<String, dynamic>)['skills'] as List? ??
              [])
          .cast<Map<String, dynamic>>()
          .map(Skill.fromJson)
          .toList();
      if (mounted) {
        setState(() {
          _mine = results[0] as List<Map<String, dynamic>>;
          _skills = skills;
          _serverDown = false;
        });
      }
    } catch (_) {
      // Server down — Mine hides; Skills falls back to the on-device catalog.
      if (mounted) setState(() => _serverDown = true);
    }
  }

  List<Skill> get _preview {
    if (_skills.isNotEmpty) return _skills.take(_previewCount).toList();
    return Catalog.bindable
        .where((g) =>
            !g.id.startsWith('surface:') && !g.id.startsWith('connector:'))
        .take(_previewCount)
        .map(Skill.local)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _refresh,
        color: Glass.ink,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          children: [
            const Text('Build',
                style: TextStyle(
                    color: Glass.ink, fontSize: 28, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),

            // §6.8 the Builder
            Semantics(
              identifier: 'build:open-builder',
              button: true,
              child: GlassCard(
                onTap: _openBuilder,
                child: Row(children: [
                  const KeycapGMark(size: 44),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text('Build your own',
                        style: TextStyle(
                            color: Glass.ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                  ),
                  const Icon(Icons.add_circle_outline,
                      color: Glass.ink, size: 22),
                ]),
              ),
            ),
            const SizedBox(height: 20),

            // §6.14 Packs
            _sectionLabel('Packs'),
            const SizedBox(height: 8),
            SizedBox(
              height: 116,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: Packs.all.length,
                separatorBuilder: (_, i) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final p = Packs.all[i];
                  return Semantics(
                    identifier: 'pack:${p.id}',
                    button: true,
                    child: GestureDetector(
                      onTap: () => _applyPack(p),
                      child: Container(
                        width: 128,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(Glass.radiusCard),
                          border: Border.all(color: Glass.hairline),
                        ),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.emoji,
                                  style: const TextStyle(fontSize: 22)),
                              const Spacer(),
                              Text(p.name,
                                  style: const TextStyle(
                                      color: Glass.ink,
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w700)),
                              Text(p.tagline,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Glass.inkSoft, fontSize: 11)),
                            ]),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 18),

            // My glyfs (builder output)
            if (_mine.isNotEmpty) ...[
              _sectionLabel('Mine'),
              const SizedBox(height: 8),
              for (final g in _mine) _mineCard(g),
              const SizedBox(height: 12),
            ],

            // Skills: shipped + community, most-installed first.
            Row(children: [
              Expanded(child: _sectionLabel('Skills')),
              Semantics(
                identifier: 'build:open-skills',
                button: true,
                child: TextButton(
                  onPressed: _openSkills,
                  child: const Text('See all',
                      style: TextStyle(
                          color: Glass.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ]),
            const SizedBox(height: 4),
            for (final skill in _preview)
              SkillTile(
                skill: skill,
                boundKey: _bound[skill.id],
                onTap: () async {
                  final added = await showSkillSheet(context, skill,
                      boundKey: _bound[skill.id]);
                  if (added) _refresh();
                },
              ),
            if (_serverDown)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('Server offline',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Glass.inkSoft, fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(text,
      style: const TextStyle(
          color: Glass.ink, fontSize: 20, fontWeight: FontWeight.w700));

  Future<void> _openSkills() async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const SkillsScreen()));
    _refresh();
  }

  Future<void> _openBuilder() async {
    final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const BuilderScreen()));
    if (changed == true) _refresh();
  }

  // ---- §6.14 pack apply --------------------------------------------------

  Future<void> _applyPack(GlyfPack p) async {
    final settings = await GlyfBridge.sharedSettings();
    final current =
        (settings['bindings'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final conflicts = Packs.conflicts(p, current);
    if (!mounted) return;
    final apply = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(Glass.radiusSheet))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
          child:
              Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${p.emoji}  ${p.name} Pack',
                style: const TextStyle(
                    color: Glass.ink, fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            for (final e in p.bindings.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2F3F7),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(e.key.toUpperCase(),
                        style: const TextStyle(
                            color: Glass.ink, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(Catalog.byId(e.value).title,
                              style: const TextStyle(
                                  color: Glass.ink,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600)),
                          if (conflicts.containsKey(e.key))
                            Text(
                                'replaces ${Catalog.byId(conflicts[e.key]!).title}',
                                style: const TextStyle(
                                    color: Color(0xFFC08109), fontSize: 11.5)),
                        ]),
                  ),
                ]),
              ),
            const SizedBox(height: 8),
            PillButton(
                label: conflicts.isEmpty
                    ? 'Apply pack'
                    : 'Apply — rebind ${conflicts.length} '
                        'key${conflicts.length == 1 ? '' : 's'}',
                onPressed: () => Navigator.pop(ctx, true)),
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel',
                    style: TextStyle(color: Glass.inkSoft))),
          ]),
        ),
      ),
    );
    if (apply != true) return;
    await GlyfBridge.updateSharedSettings((s) {
      final b = Map<String, dynamic>.from(
          (s['bindings'] as Map<String, dynamic>?) ?? {});
      b.addAll(p.bindings);
      s['bindings'] = b;
      return s;
    });
    Telemetry.log('pack_applied', {'pack': p.id});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${p.name} Pack applied — hold the keys to fire')));
    }
  }

  // ---- mine / hub cards --------------------------------------------------

  Widget _mineCard(Map<String, dynamic> g) {
    final id = g['id'] as String;
    final published = g['published'] == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(g['name'] as String? ?? id,
                  style: const TextStyle(
                      color: Glass.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
              Text(published ? 'Published' : 'Private',
                  style: TextStyle(
                      color: published
                          ? const Color(0xFF2E9E63)
                          : Glass.inkSoft,
                      fontSize: 12)),
            ]),
          ),
          IconButton(
            tooltip: 'Bind to a key',
            icon: const Icon(Icons.keyboard_alt_outlined,
                size: 20, color: Glass.ink),
            onPressed: () async {
              final letter =
                  await pickKey(context, title: 'Bind “${g['name']}” to…');
              if (letter != null) {
                await bindGlyf(
                    letter: letter,
                    glyfId: id,
                    displayName: g['name'] as String?);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(
                          'Hold ${letter.toUpperCase()} fires ${g['name']}')));
                }
              }
            },
          ),
          if (!published)
            IconButton(
              tooltip: 'Publish to Hub',
              icon: const Icon(Icons.public, size: 20, color: Glass.ink),
              onPressed: () async {
                try {
                  await GlyfApi.hubPublish(id);
                  Telemetry.log('hub_publish', {'glyfId': id});
                  _refresh();
                } on GlyfApiException catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(e.message)));
                  }
                }
              },
            ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline,
                size: 20, color: Color(0xFFC03A2E)),
            onPressed: () async {
              await GlyfApi.deleteGlyf(id);
              _refresh();
            },
          ),
        ]),
      ),
    );
  }
}
