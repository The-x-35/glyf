import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/core/auth.dart';
import 'package:glyf/onboarding/onboarding_flow.dart';

/// iOS ends the app the moment Full Access is granted in Settings, so
/// onboarding must save where it is and reopen there — not on the hello.
void main() {
  const bridge = MethodChannel('so.glyf/bridge');
  final saved = <Map<String, dynamic>>[];

  setUp(() {
    saved.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(bridge, (call) async {
      switch (call.method) {
        case 'launchArgs':
          return ['--glyf-test-signed-in', '--glyf-test-account=google:asha@example.com'];
        case 'keyboardEnabled':
          return true;
        case 'readSharedSettings':
          return jsonEncode({'keyClicks': false, 'haptics': true});
        case 'writeOnboardingState':
          saved.add(jsonDecode((call.arguments as Map)['json'] as String) as Map<String, dynamic>);
          return true;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(bridge, null);
  });

  /// A phone, not the 800×600 test window the steps were never laid out for.
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  /// Bridge calls settle on real async turns; the status poll runs once a
  /// second of fake time.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump(const Duration(milliseconds: 600));
    }
  }

  testWidgets('a run that was cut short reopens on the step it had saved', (tester) async {
    phone(tester);
    await tester.runAsync(Auth.restore);
    await tester.pumpWidget(MaterialApp(
      home: OnboardingFlow(resume: const {'step': 'setup', 'persona': 'student'}, onDone: () {}),
    ));
    await settle(tester);

    // The setup step, not the hello.
    expect(find.text('Settings › Apps › Glyf › Keyboards'), findsOneWidget);
    expect(find.text('Let me remember you.'), findsNothing);
    // The keyboard is asked to turn up and report Full Access straight away.
    final probe = tester.widget<TextField>(find.byType(TextField));
    expect(probe.focusNode?.hasFocus, isTrue);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('every step is saved as it is reached, so a relaunch can find it', (tester) async {
    phone(tester);
    await tester.runAsync(Auth.restore);
    await tester.pumpWidget(MaterialApp(home: OnboardingFlow(onDone: () {})));
    await settle(tester);

    expect(find.text('Let me remember you.'), findsOneWidget);
    await tester.tap(find.text('Tell Glyf about me'));
    await settle(tester);

    expect(find.text('What should I remember?'), findsOneWidget);
    expect(saved.last['step'], 'details');

    await tester.pumpWidget(const SizedBox());
  });
}
