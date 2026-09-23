import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/bridge.dart';
import '../core/catalog.dart';
import '../core/glyf_api.dart';
import '../core/theme.dart';
import 'builder_screen.dart';
import 'key_picker.dart';

/// Build — make your own glyfs. The Builder up top, then the glyfs you made,
/// each with the key it sits on. Nothing here is shared or published.
class BuildTab extends StatefulWidget {
  const BuildTab({super.key, this.activeTab});

  /// The shell's selected-tab notifier — tabs live in an IndexedStack, so
  /// this is the "became visible again" signal (fresh list on return).
  final ValueListenable<int>? activeTab;

  @override
  State<BuildTab> createState() => _BuildTabState();
}

class _BuildTabState extends State<BuildTab> {
  List<Map<String, dynamic>> _mine = [];
  Map<String, String> _bound = {};
  bool _serverDown = false;

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
      final mine = await GlyfApi.myGlyfs();
      await _syncTitles(mine);
      if (mounted) {
        setState(() {
          _mine = mine;
          _serverDown = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _serverDown = true);
    }
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

            if (_mine.isNotEmpty) ...[
              _sectionLabel('Mine'),
              const SizedBox(height: 8),
              for (final g in _mine) _mineCard(g),
            ],
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

  /// The keyboard's "My glyfs" list reads names from shared settings, so
  /// every glyf made here is listed there, bound to a key or not.
  Future<void> _syncTitles(List<Map<String, dynamic>> mine) async {
    final titles = {
      for (final g in mine)
        g['id'] as String: (g['name'] as String?) ?? g['id'] as String,
    };
    await GlyfBridge.updateSharedSettings((s) {
      s['customTitles'] = titles;
      return s;
    });
    Catalog.rememberCustomTitles(titles);
  }

  Widget _sectionLabel(String text) => Text(text,
      style: const TextStyle(
          color: Glass.ink, fontSize: 20, fontWeight: FontWeight.w700));

  Future<void> _openBuilder() async {
    final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const BuilderScreen()));
    if (changed == true) _refresh();
  }

  Widget _mineCard(Map<String, dynamic> g) {
    final id = g['id'] as String;
    final key = _bound[id];
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
              Text(key == null ? 'Not on a key' : 'Hold ${key.toUpperCase()}',
                  style: const TextStyle(color: Glass.inkSoft, fontSize: 12)),
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
                _refresh();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(
                          'Hold ${letter.toUpperCase()} fires ${g['name']}')));
                }
              }
            },
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline,
                size: 20, color: Color(0xFFC03A2E)),
            onPressed: () async {
              // One tap on a small red icon should not be able to lose
              // something that took a while to build.
              final go = await showCupertinoDialog<bool>(
                context: context,
                builder: (ctx) => CupertinoAlertDialog(
                  title: Text('Delete ${g['name']}?'),
                  content: const Text('\nIt comes off its key too. This cannot be undone.'),
                  actions: [
                    CupertinoDialogAction(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel')),
                    CupertinoDialogAction(
                        isDestructiveAction: true,
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Delete')),
                  ],
                ),
              );
              if (go != true) return;
              await GlyfApi.deleteGlyf(id);
              await unbindGlyf(id);
              _refresh();
            },
          ),
        ]),
      ),
    );
  }
}
