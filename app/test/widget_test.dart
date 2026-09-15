import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/main.dart';

void main() {
  testWidgets('fresh install lands on the onboarding hello step',
      (tester) async {
    await tester.pumpWidget(const GlyfApp());
    // Let the async onboarding-state load resolve (bridge is absent in tests).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Set up Glyf'), findsOneWidget);
    expect(find.text('Every key is a Glyf.'), findsOneWidget);
    // Dispose the flow so its polling timer doesn't outlive the test.
    await tester.pumpWidget(const SizedBox());
  });
}
