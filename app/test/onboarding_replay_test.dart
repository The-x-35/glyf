import 'dart:convert';

import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/core/auth.dart';
import 'package:glyf/onboarding/onboarding_flow.dart';

/// Replay onboarding from Profile is for looking again, not starting over:
/// the person's own settings come in, and nothing saved is lost.
void main() {
  const bridge = MethodChannel('so.glyf/bridge');
  late Map<String, dynamic> onboarding;
  late Map<String, dynamic> settings;

  setUp(() {
    onboarding = {'done': true, 'displayName': 'Asha', 'persona': 'student'};
    settings = {'keyClicks': false, 'haptics': false, 'clipboardHistory': false, 'clipboardScreenshots': false};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(bridge, (call) async {
      final args = call.arguments is Map ? call.arguments as Map : const {};
      switch (call.method) {
        case 'launchArgs':
          return ['--glyf-test-signed-in', '--glyf-test-account=google:asha@example.com'];
        case 'keyboardEnabled':
          return true;
        case 'readSharedSettings':
          return jsonEncode(settings);
        case 'writeSharedSettings':
          settings = jsonDecode(args['json'] as String) as Map<String, dynamic>;
          return true;
        case 'readOnboardingState':
          return jsonEncode(onboarding);
        case 'writeOnboardingState':
          onboarding = jsonDecode(args['json'] as String) as Map<String, dynamic>;
          return true;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(bridge, null);
  });

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump(const Duration(milliseconds: 600));
    }
  }

  Finder close() => find.descendant(
      of: find.byWidgetPredicate((w) => w is Semantics && w.properties.identifier == 'onb:close'),
      matching: find.byType(IconButton));

  testWidgets('a replay starts at the top with the person’s own switches and keeps done and the name',
      (tester) async {
    phone(tester);
    await tester.runAsync(Auth.restore);
    var closed = 0;
    await tester.pumpWidget(MaterialApp(
      // A stale saved step must not decide where a replay opens.
      home: OnboardingFlow(replay: true, resume: const {'step': 'setup'}, onDone: () => closed++),
    ));
    await settle(tester);

    expect(find.text('Let me remember you.'), findsOneWidget);
    expect(close(), findsOneWidget);
    await tester.tap(find.text('Tell Glyf about me'));
    await settle(tester);
    await tester.tap(find.text('Skip'));
    await settle(tester);

    // Their switches, all off, not the first-run defaults.
    expect(find.text('Make it yours'), findsOneWidget);
    final switches = tester.widgetList<CupertinoSwitch>(find.byType(CupertinoSwitch)).toList();
    expect(switches, hasLength(4));
    expect(switches.any((s) => s.value), isFalse);
    await tester.tap(find.text('Continue'));
    await settle(tester);

    expect(settings['keyClicks'], isFalse);
    expect(settings['haptics'], isFalse);
    expect(settings['clipboardHistory'], isFalse);
    expect(onboarding['done'], isTrue);
    expect(onboarding['displayName'], 'Asha');
    expect(onboarding['persona'], 'student');
    expect(onboarding['step'], 'ai');

    await tester.tap(close());
    await tester.pump();
    expect(closed, 1);

    await tester.pumpWidget(const SizedBox());
  });
}
