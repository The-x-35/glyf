import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/evm/metamask_link.dart';

/// The same MetaMask signer on Android: its deeplinks open through the
/// bridge's openMetaMask (GlyfBridge.kt there, GlyfBridge.swift on the
/// iPhone), say which platform is asking, and a phone without MetaMask
/// says so instead of waiting.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const bridge = MethodChannel('so.glyf/bridge');
  late List<String> opened;
  late bool installed;

  setUp(() {
    opened = [];
    installed = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(bridge, (call) async {
      final args = (call.arguments as Map?)?.cast<String, Object?>() ?? const {};
      switch (call.method) {
        case 'readSharedSettings':
          return jsonEncode({'mmChannel': '00000000-0000-4000-8000-000000000000'});
        case 'writeSharedSettings':
          return true;
        case 'launchArgs':
          return <String>[];
        case 'openMetaMask':
          opened.add(args['url'] as String);
          return installed;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(bridge, null);
  });

  test('the request says which platform is asking', () {
    expect(MetaMaskLink.originatorFor('android')['platform'], 'android');
    expect(MetaMaskLink.originatorFor('ios')['platform'], 'ios');
    expect(MetaMaskLink.originatorFor('android')['dappId'], 'tryglyf.com');
  });

  test('connect opens metamask:// through the bridge and answers on glyf://mmsdk', () async {
    final (id, url) = await MetaMaskLink.connectLink('Sign in to Glyf');
    expect(url, startsWith('metamask://connect?scheme=glyf'));
    final info = jsonDecode(utf8.decode(base64.decode(Uri.parse(url).queryParameters['originatorInfo']!))) as Map;
    expect(info['title'], 'Glyf');
    final reply = MetaMaskLink.send(id, url, stop: Completer<void>().future);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(opened, [url]);
    final message = base64.encode(utf8.encode(jsonEncode({
      'data': {'id': id, 'result': '0xsig', 'accounts': ['0xabc'], 'chainId': '0x2105'}
    })));
    expect(MetaMaskLink.handle(Uri.parse('glyf://mmsdk?message=${Uri.encodeComponent(message)}')), isTrue);
    expect((await reply).result, '0xsig');
  });

  test('without MetaMask installed the signer says so at once', () async {
    installed = false;
    final (id, url) = await MetaMaskLink.connectLink('Sign in to Glyf');
    await expectLater(MetaMaskLink.send(id, url, stop: Completer<void>().future),
        throwsA(isA<MetaMaskError>().having((e) => e.message, 'message', 'Install MetaMask to sign with it')));
  });
}
