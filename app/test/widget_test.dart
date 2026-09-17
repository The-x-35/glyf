import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/main.dart';
import 'package:glyf/onboarding/onboarding_flow.dart';

void main() {
  testWidgets('fresh install plays the launch, then lands on sign-in', (tester) async {
    await tester.pumpWidget(const GlyfApp());
    // The native bridge is absent in tests; its calls settle only on real
    // async turns. Nothing is saved and nobody is signed in.
    for (var i = 0; i < 25 && find.byType(OnboardingFlow).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    // The launch (about 1.7 s) and its glide onto the sign-in orb.
    for (var i = 0; i < 200; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('Continue with Google'), findsOneWidget);
    // Dispose the flow so its timers don't outlive the test.
    await tester.pumpWidget(const SizedBox());
  });
}
