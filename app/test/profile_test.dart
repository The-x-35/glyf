import 'dart:convert';

import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/core/auth.dart';
import 'package:glyf/core/theme.dart';
import 'package:glyf/onboarding/onboarding_flow.dart';
import 'package:glyf/profile/profile_tab.dart';

void main() {
  const bridge = MethodChannel('so.glyf/bridge');
  late bool contactsOn;
  late bool nearbyOn;
  late List<String> calls;

  setUp(() {
    contactsOn = false;
    nearbyOn = true;
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(bridge, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'launchArgs':
          return ['--glyf-test-signed-in', '--glyf-test-account=google:asha@example.com'];
        case 'contactsStatus':
          return jsonEncode({'enabled': contactsOn, 'permission': contactsOn ? 'granted' : 'notDetermined'});
        case 'contactsEnable':
          contactsOn = true;
          return jsonEncode({'ok': true, 'count': 12});
        case 'contactsDisable':
          contactsOn = false;
          return true;
        case 'locationStatus':
          return jsonEncode({'enabled': nearbyOn, 'permission': 'granted'});
        case 'locationDisable':
          nearbyOn = false;
          return true;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(bridge, null);
  });

  /// Bridge calls settle on real async turns.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// A phone, not the 800x600 test window: the page's last rows and
  /// onboarding's steps were laid out for one.
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1206, 2622);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  Finder byId(String id) =>
      find.byWidgetPredicate((w) => w is Semantics && w.properties.identifier == id);

  Finder switchFor(String id) => find.descendant(of: byId(id), matching: find.byType(CupertinoSwitch));

  bool isOn(WidgetTester tester, String id) => tester.widget<CupertinoSwitch>(switchFor(id)).value;

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

  testWidgets('the page is the account card, one row per place, and the account actions at the foot',
      (tester) async {
    phone(tester);
    await tester.runAsync(Auth.restore);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ProfileTab(onRerunOnboarding: () {})),
    ));
    await settle(tester);

    // Got a code? is part of the account card, not a row of its own.
    expect(find.descendant(of: find.byType(GlassCard).first, matching: find.text('Got a code?')),
        findsOneWidget);
    for (final row in ['Keyboard', 'Vocabulary', 'Vault', 'Search', 'Connected tools', 'Wallet', 'Tour']) {
      expect(find.text(row), findsOneWidget, reason: row);
    }
    // Folded into Search, Vocabulary and Tour.
    for (final gone in ['Contacts search', 'Nearby search', 'Tone profile', 'Take the tour', 'Replay onboarding']) {
      expect(find.text(gone), findsNothing, reason: gone);
    }
    for (final action in ['Sign out', 'Privacy policy']) {
      await tester.scrollUntilVisible(find.text(action), 200);
      expect(find.text(action), findsOneWidget, reason: action);
    }
    // No Delete account anywhere (2026-09-29).
    expect(find.text('Delete account', skipOffstage: false), findsNothing);
    expect(find.byKey(const Key('profile:delete-account'), skipOffstage: false), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Edit holds only the name: no Delete account anywhere', (tester) async {
    phone(tester);
    await tester.runAsync(Auth.restore);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ProfileTab(onRerunOnboarding: () {})),
    ));
    await settle(tester);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Your name'), findsOneWidget);
    expect(find.text('Delete account'), findsNothing);
    expect(find.byKey(const Key('profile:delete-account')), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Contacts and Nearby are one Search row, and its sheet keeps both flows', (tester) async {
    await tester.runAsync(Auth.restore);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ProfileTab(onRerunOnboarding: () {})),
    ));
    await settle(tester);
    expect(find.text('Nearby on'), findsOneWidget);

    await tester.ensureVisible(find.text('Search'));
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    await settle(tester);
    expect(find.byType(CupertinoSwitch), findsNWidgets(2));
    expect(isOn(tester, 'search:contacts'), isFalse);
    expect(isOn(tester, 'search:nearby'), isTrue);

    // On explains first, then asks the phone, then says what it did.
    await tester.tap(switchFor('search:contacts'));
    await tester.pumpAndSettle();
    expect(find.text('Contacts search'), findsOneWidget);
    expect(calls, isNot(contains('contactsEnable')));
    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();
    await settle(tester);
    expect(calls, contains('contactsEnable'));
    expect(find.text('12 contacts ready in the keyboard'), findsOneWidget);
    expect(isOn(tester, 'search:contacts'), isTrue);

    // Off asks before the keyboard forgets where you are.
    await tester.tap(switchFor('search:nearby'));
    await tester.pumpAndSettle();
    expect(find.text('Turn off Nearby search?'), findsOneWidget);
    await tester.tap(find.text('Turn off'));
    await tester.pumpAndSettle();
    await settle(tester);
    expect(calls, contains('locationDisable'));
    expect(isOn(tester, 'search:nearby'), isFalse);

    // Closed, the row says what is on now.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    await settle(tester);
    expect(find.byType(CupertinoSwitch), findsNothing);
    expect(find.text('Contacts on'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('one Tour row offers the tour and the onboarding replay', (tester) async {
    phone(tester);
    await tester.runAsync(Auth.restore);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ProfileTab(onRerunOnboarding: () {})),
    ));
    await settle(tester);

    await tester.scrollUntilVisible(find.text('Tour'), 200);
    await tester.tap(find.text('Tour'));
    await tester.pumpAndSettle();
    expect(find.text('Take the tour'), findsOneWidget);
    expect(find.text('Replay onboarding'), findsOneWidget);

    await tester.tap(find.text('Replay onboarding'));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 600));
    final flow = tester.widget<OnboardingFlow>(find.byType(OnboardingFlow));
    expect(flow.replay, isTrue);

    await tester.pumpWidget(const SizedBox());
  });
}
