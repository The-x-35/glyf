import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/core/auth.dart';
import 'package:glyf/profile/profile_tab.dart';

/// Delete account (App Store 5.1.1(v), Google Play): a row at Profile's
/// foot, a sheet that says what goes, then the server, then the phone.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const bridge = MethodChannel('so.glyf/bridge');
  late List<String> calls;
  late List<String> args;
  late Map<String, dynamic> settings;

  /// A session the app takes as live (the server checks the signature).
  String session() {
    String part(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
    final exp = DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch ~/ 1000;
    return '${part({'alg': 'HS256'})}.${part({'iss': 'glyf', 'sub': 'google:1', 'exp': exp})}.sig';
  }

  setUp(() {
    calls = [];
    args = ['--glyf-test-signed-in', '--glyf-test-account=google:asha@example.com'];
    settings = {'deviceId': 'phone-0000-aaaa', 'backendURL': 'http://127.0.0.1:9'};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(bridge, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'launchArgs':
          return args;
        case 'readSharedSettings':
          return jsonEncode(settings);
        case 'writeSharedSettings':
          settings = jsonDecode((call.arguments as Map)['json'] as String) as Map<String, dynamic>;
          return true;
        case 'sessionSave':
        case 'signOutProviders':
          return true;
        case 'eraseLocalData':
          settings = {};
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
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> openSheet(WidgetTester tester, VoidCallback onRerun) async {
    phone(tester);
    await tester.runAsync(Auth.restore);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ProfileTab(onRerunOnboarding: onRerun))));
    await settle(tester);
    final row = find.byKey(const Key('profile:delete-account'));
    await tester.scrollUntilVisible(row, 200);
    await tester.tap(row);
    await tester.pumpAndSettle();
  }

  testWidgets('the sheet says what goes, and Cancel leaves everything as it was', (tester) async {
    var rerun = 0;
    await openSheet(tester, () => rerun++);

    expect(find.text('Delete your account?'), findsOneWidget);
    final what = tester.widget<Text>(find.byKey(const Key('delete-account:what'))).data!;
    for (final thing in ['account', 'server', 'vault', 'clipboard', 'learned words', "can't be undone"]) {
      expect(what, contains(thing));
    }
    expect(find.textContaining("A subscription isn't cancelled"), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Delete your account?'), findsNothing);
    expect(calls, isNot(contains('eraseLocalData')));
    expect(calls, isNot(contains('signOutProviders')));
    expect(Auth.signedIn, isTrue);
    expect(rerun, 0);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Delete account erases the phone, signs out and goes back to sign-in', (tester) async {
    var rerun = 0;
    await openSheet(tester, () => rerun++);

    await tester.tap(find.text('Delete account').last);
    await settle(tester);
    await tester.pumpAndSettle();

    expect(calls, containsAllInOrder(['signOutProviders', 'eraseLocalData']));
    expect(Auth.signedIn, isFalse);
    expect(Auth.identity().email, isNull);
    expect(find.text('Delete your account?'), findsNothing);
    expect(rerun, 1);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a server that refuses leaves the phone alone and says so', (tester) async {
    // flutter_test answers every HTTP request with a 400.
    args = ['--glyf-test-session=${session()}'];
    var rerun = 0;
    await openSheet(tester, () => rerun++);

    await tester.tap(find.text('Delete account').last);
    await settle(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('delete-account:error')), findsOneWidget);
    expect(find.text("Couldn't delete your account right now. Try again."), findsOneWidget);
    expect(calls, isNot(contains('eraseLocalData')));
    expect(Auth.signedIn, isTrue);
    expect(rerun, 0);

    // Back out of it: the sheet's Cancel still works after a failure.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Delete your account?'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  group('against a server', () {
    late HttpServer server;
    late List<({String method, String path, String? auth, Map<String, dynamic>? body})> seen;
    late int deleteStatus;
    HttpOverrides? saved;

    setUp(() async {
      saved = HttpOverrides.current;
      HttpOverrides.global = null;
      seen = [];
      deleteStatus = 200;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final text = await utf8.decoder.bind(req).join();
        seen.add((
          method: req.method,
          path: req.uri.path,
          auth: req.headers.value('authorization'),
          body: text.isEmpty ? null : jsonDecode(text) as Map<String, dynamic>,
        ));
        req.response.headers.contentType = ContentType.json;
        if (req.method == 'POST' && req.uri.path == '/me/delete') {
          req.response.write(jsonEncode({'ok': true, 'confirm': 'c-123', 'expiresIn': 300}));
        } else if (req.method == 'DELETE' && req.uri.path == '/me') {
          req.response.statusCode = deleteStatus;
          req.response.write(jsonEncode({'ok': deleteStatus == 200}));
        } else {
          req.response.statusCode = 404;
        }
        await req.response.close();
      });
      settings['backendURL'] = 'http://127.0.0.1:${server.port}';
      args = ['--glyf-test-session=${session()}'];
      await Auth.restore();
    });

    tearDown(() async {
      await server.close(force: true);
      HttpOverrides.global = saved;
    });

    test('asks for a confirmation, deletes with it and the phone id, then erases', () async {
      final token = Auth.bearer;
      expect(await Auth.deleteAccount(), isNull);

      expect(seen.map((r) => '${r.method} ${r.path}'), ['POST /me/delete', 'DELETE /me']);
      expect(seen.every((r) => r.auth == 'Bearer $token'), isTrue);
      expect(seen.last.body, {'confirm': 'c-123', 'deviceIds': ['phone-0000-aaaa']});
      expect(calls, containsAllInOrder(['signOutProviders', 'eraseLocalData']));
      expect(Auth.signedIn, isFalse);
    });

    test('a failed delete keeps the session and the phone as they were', () async {
      deleteStatus = 503;
      expect(await Auth.deleteAccount(), "Couldn't delete your account right now. Try again.");
      expect(calls, isNot(contains('eraseLocalData')));
      expect(Auth.signedIn, isTrue);
    });

    test('a session the server no longer takes asks to sign in again', () async {
      deleteStatus = 401;
      expect(await Auth.deleteAccount(), 'Sign in again, then delete your account.');
      expect(calls, isNot(contains('eraseLocalData')));
    });
  });
}
