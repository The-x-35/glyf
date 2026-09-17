import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/core/auth.dart';
import 'package:glyf/profile/profile_tab.dart';

void main() {
  const bridge = MethodChannel('so.glyf/bridge');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(bridge, (call) async {
      if (call.method == 'launchArgs') {
        return ['--glyf-test-signed-in', '--glyf-test-account=google:asha@example.com'];
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(bridge, null);
  });

  testWidgets('profile shows the account email, not an ID, and signs out after asking', (tester) async {
    await tester.runAsync(Auth.restore);
    var signedOut = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ProfileTab(onRerunOnboarding: () => signedOut++)),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    expect(find.text('asha@example.com'), findsOneWidget);
    expect(find.textContaining('UID'), findsNothing);

    final signOut = find.text('Sign out');
    await tester.scrollUntilVisible(signOut, 200);
    await tester.tap(signOut);
    await tester.pumpAndSettle();
    expect(find.text('Sign out of Glyf?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(signedOut, 0);
    expect(Auth.signedIn, isTrue);

    await tester.tap(signOut);
    await tester.pumpAndSettle();
    // The dialog's action, drawn over the page's own row.
    await tester.tap(find.text('Sign out').last);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(signedOut, 1);
    expect(Auth.signedIn, isFalse);
    expect(Auth.identity().email, isNull);

    // Dispose the page so its refresh timer doesn't outlive the test.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('closing the name sheet leaves the page working', (tester) async {
    addTearDown(tester.view.reset);
    await tester.runAsync(Auth.restore);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ProfileTab(onRerunOnboarding: () {})),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Your name'), findsOneWidget);
    // The keyboard is up while the name is edited...
    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    await tester.pumpAndSettle();

    // ...and goes down while the sheet slides away.
    await tester.tapAt(const Offset(20, 20));
    await tester.pump();
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();

    expect(find.text('Your name'), findsNothing);
    expect(find.text('Edit'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
