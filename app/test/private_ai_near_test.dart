import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/core/glyf_api.dart';
import 'package:glyf/profile/keyboard_screen.dart';

/// The real network, for one call to a server the test runs itself
/// (flutter_test answers every request with a 400 otherwise).
class _Network extends HttpOverrides {}

/// Private AI on NEAR (Profile › Keyboard): shared settings `privateAI` is
/// "near" while on and gone when off, and every app call then carries
/// `X-Glyf-AI: near`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const bridge = MethodChannel('so.glyf/bridge');
  late Map<String, dynamic> stored;

  setUp(() {
    stored = {'keyTheme': 'site', 'themeBg': '', 'appearance': 'light'};
    GlyfApi.privateAI = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(bridge, (call) async {
      switch (call.method) {
        case 'readSharedSettings':
          return jsonEncode(stored);
        case 'writeSharedSettings':
          stored = jsonDecode((call.arguments as Map)['json'] as String) as Map<String, dynamic>;
          return true;
      }
      return null;
    });
  });

  tearDown(() {
    GlyfApi.privateAI = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(bridge, null);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Finder switchOf(String title) => find.descendant(
      of: find.ancestor(of: find.text(title), matching: find.byType(Row)).first, matching: find.byType(CupertinoSwitch));

  testWidgets('the switch is off at first; on writes "near" and shows the receipts, off takes it away', (tester) async {
    tester.view.physicalSize = const Size(1206, 26000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: KeyboardScreen()));
    await settle(tester);

    expect(tester.widget<CupertinoSwitch>(switchOf('Private AI on NEAR')).value, isFalse);
    expect(find.text('NEAR AI receipts'), findsNothing);

    await tester.tap(switchOf('Private AI on NEAR'));
    await settle(tester);
    expect(stored['privateAI'], 'near');
    expect(GlyfApi.privateAI, 'near');
    expect(find.text('NEAR AI receipts'), findsOneWidget);

    await tester.tap(switchOf('Private AI on NEAR'));
    await settle(tester);
    expect(stored.containsKey('privateAI'), isFalse);
    expect(GlyfApi.privateAI, isNull);
    expect(find.text('NEAR AI receipts'), findsNothing);
  });

  test('loading reads "near"; the 0G build’s old bool is cleared, so nothing asks for 0G', () async {
    stored['privateAI'] = 'near';
    await GlyfApi.loadPrivateAI();
    expect(GlyfApi.privateAI, 'near');

    stored['privateAI'] = true;
    await GlyfApi.loadPrivateAI();
    expect(GlyfApi.privateAI, isNull);
    expect(stored.containsKey('privateAI'), isFalse);
  });

  test('every call carries X-Glyf-AI: near while it is on, and none while off', () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final seen = <String?>[];
      server.listen((req) {
        seen.add(req.headers.value('X-Glyf-AI'));
        req.response
          ..headers.contentType = ContentType.json
          ..write('{"ok":true}')
          ..close();
      });
      stored['backendURL'] = 'http://127.0.0.1:${server.port}';

      GlyfApi.privateAI = 'near';
      await GlyfApi.evmGet('/near/status?deposit=x');
      await GlyfApi.evmPost('/near/quote', {});
      GlyfApi.privateAI = null;
      await GlyfApi.evmGet('/health');
      expect(seen, ['near', 'near', null]);
    }, _Network());
  });
}
