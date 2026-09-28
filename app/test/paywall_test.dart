import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/profile/paywall_sheet.dart';

void main() {
  testWidgets('plans the store hasn’t returned are shown read-only, never sold', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(onPressed: () => showPaywall(context), child: const Text('open')),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Upgrade Glyf'), findsOneWidget);
    expect(find.text('Plans open soon'), findsOneWidget);
    expect(find.text('400 runs a day'), findsOneWidget);
    expect(find.text('Get Plus'), findsNothing);
    expect(find.text('Get Max'), findsNothing);
    expect(find.textContaining('Pro'), findsNothing);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Plans open soon'), findsNothing);
  });
}
