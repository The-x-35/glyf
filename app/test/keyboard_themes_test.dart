import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/core/themes.dart';
import 'package:glyf/profile/keyboard_screen.dart';

void main() {
  const bridge = MethodChannel('so.glyf/bridge');
  late Map<String, dynamic> stored;
  late List<String> writes;

  setUp(() {
    stored = {'keyTheme': 'site', 'themeBg': '', 'appearance': 'light'};
    writes = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(bridge, (call) async {
      switch (call.method) {
        case 'readSharedSettings':
          return jsonEncode(stored);
        case 'writeSharedSettings':
          final next = jsonDecode((call.arguments as Map)['json'] as String) as Map<String, dynamic>;
          writes.addAll(next.keys.where((k) => jsonEncode(next[k]) != jsonEncode(stored[k])));
          stored = next;
          return true;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(bridge, null);
  });

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> open(WidgetTester tester) async {
    phone(tester);
    await tester.pumpWidget(const MaterialApp(home: KeyboardScreen()));
    await settle(tester);
  }

  /// Brings [f] on screen in the page's list (each tile grid is a
  /// Scrollable too, so the list is named).
  Future<void> reveal(WidgetTester tester, Finder f, {bool up = false}) async {
    await tester.dragUntilVisible(f, find.byType(ListView), Offset(0, up ? 300 : -300));
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
  }

  Future<void> tapTile(WidgetTester tester, Finder f) async {
    await reveal(tester, f);
    await tester.tap(f);
    await settle(tester);
  }

  test('the generated table matches shared/themes/themes.json', () {
    final json = jsonDecode(File('../shared/themes/themes.json').readAsStringSync()) as List;
    expect(kbThemes.map((t) => t.id), json.map((t) => t['id']));
    Color hex(String h) => Color(int.parse('FF${h.substring(1)}', radix: 16));
    for (var i = 0; i < json.length; i++) {
      final j = json[i] as Map<String, dynamic>;
      final t = kbThemes[i];
      expect(t.name, j['name']);
      expect(t.category, j['category']);
      expect(t.tier, 'free');
      for (final mode in ['light', 'dark']) {
        final v = t.variant(mode == 'dark');
        final jv = j['variants'][mode] as Map<String, dynamic>;
        expect(v.board, [for (final c in jv['board']['colors'] as List) hex(c as String)]);
        expect(v.letter.fill, hex(jv['letterKey']['fill'] as String));
        expect(v.function.fill, hex(jv['functionKey']['fill'] as String));
        expect(v.returnPrimary.fill, hex(jv['returnPrimary']['fill'] as String));
        expect(v.border == null, jv['border'] == null);
      }
    }
  });

  testWidgets('every theme has a tile, in the spec groups, and none is picked at first',
      (tester) async {
    await open(tester);
    for (final t in kbThemes) {
      final tile = find.byKey(ValueKey('theme:${t.id}'));
      await reveal(tester, tile);
      expect(find.descendant(of: tile, matching: find.text(t.name)), findsOneWidget);
      expect(find.descendant(of: tile, matching: find.byIcon(Icons.check_circle)), findsNothing);
    }
    final groups = <String>{for (final t in kbThemes) t.category}.toList();
    String plural(String c) => switch (c) {
          'material' => 'Materials',
          'story' => 'Stories',
          'archetype' => 'Archetypes',
          _ => '${c[0].toUpperCase()}${c.substring(1)}s',
        };
    for (final label in [...groups.reversed.map(plural), 'Look']) {
      await reveal(tester, find.text(label), up: true);
      expect(find.text(label), findsOneWidget);
    }
    // No explainer lines: under Look there are only tiles and their names.
    expect(find.textContaining('theme'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  // Whatever themes.json holds: the first theme, one further on, the last.
  final first = kbThemes.first.id;
  final middle = kbThemes[kbThemes.length ~/ 2].id;
  final last = kbThemes.last.id;
  Finder tile(String id) => find.byKey(ValueKey('theme:$id'));

  testWidgets('a theme writes skin; Glyf and Glass clear it', (tester) async {
    await open(tester);
    await tapTile(tester, tile(first));
    expect(stored['skin'], first);
    expect(find.descendant(of: tile(first), matching: find.byIcon(Icons.check_circle)),
        findsOneWidget);

    await tapTile(tester, tile(middle));
    expect(stored['skin'], middle);

    await reveal(tester, find.text('Glass'), up: true);
    await tester.tap(find.text('Glass'));
    await settle(tester);
    expect(stored['skin'], '');
    expect(stored['keyTheme'], 'glass');

    await tapTile(tester, tile(last));
    expect(stored['skin'], last);
    await reveal(tester, find.text('Glyf'), up: true);
    await tester.tap(find.text('Glyf'));
    await settle(tester);
    expect(stored['skin'], '');
    expect(stored['keyTheme'], 'site');
    expect(stored['themeBg'], '');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('quick taps are written in order, none lost', (tester) async {
    await open(tester);
    final a = tile(kbThemes[0].id);
    final b = tile(kbThemes[1].id);
    await reveal(tester, b);
    await tester.tap(a);
    await tester.tap(b);
    await settle(tester);
    expect(stored['skin'], kbThemes[1].id);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a theme with its own border hides the Borders switch; a sound pack shows Theme sound',
      (tester) async {
    // The test window is light, as Appearance is here.
    final bordered = kbThemes.where((t) => t.light.border != null);
    final plain = kbThemes.where((t) => t.light.border == null && t.sound != 'system');
    final quiet = kbThemes.where((t) => t.sound == 'system');
    if (bordered.isNotEmpty) {
      stored['skin'] = bordered.first.id;
      await open(tester);
      expect(find.text('Borders around keys'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    }
    if (quiet.isNotEmpty) {
      stored['skin'] = quiet.first.id;
      await open(tester);
      expect(find.text('Theme sound'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    }
    if (plain.isNotEmpty) {
      stored['skin'] = plain.first.id;
      await open(tester);
      await reveal(tester, find.text('Borders around keys'));
      expect(find.text('Borders around keys'), findsOneWidget);
      await reveal(tester, find.text('Theme sound'));
      final sw = find.descendant(
          of: find.ancestor(of: find.text('Theme sound'), matching: find.byType(Row)),
          matching: find.byType(CupertinoSwitch));
      expect(tester.widget<CupertinoSwitch>(sw).value, isTrue);
      await tester.tap(sw);
      await settle(tester);
      expect(stored['skinSound'], isFalse);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('an unknown skin reads as no theme', (tester) async {
    stored['skin'] = 'no-such-theme';
    await open(tester);
    expect(find.descendant(
        of: find.ancestor(of: find.text('Glyf'), matching: find.byType(Column)).first,
        matching: find.byIcon(Icons.check_circle)), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
