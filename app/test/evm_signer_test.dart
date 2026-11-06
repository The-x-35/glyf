import 'dart:convert';

import 'package:eth_sig_util/eth_sig_util.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/evm/evm_chains.dart';
import 'package:glyf/evm/evm_signer.dart';
import 'package:glyf/evm/metamask_link.dart';
import 'package:glyf/evm/evm_wallet.dart';
import 'package:web3dart/crypto.dart' show hexToBytes;
import 'package:web3dart/web3dart.dart';

void main() {
  // A throwaway key: hardhat's first test account, public everywhere.
  const keyHex = 'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';
  const signer = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266';
  final key = hexToBytes(keyHex);

  // Flash's order typed data, as its /quote hands it back (EIP712Domain listed).
  final typed = {
    'types': {
      'EIP712Domain': [
        {'name': 'name', 'type': 'string'},
        {'name': 'version', 'type': 'string'},
        {'name': 'chainId', 'type': 'uint256'},
        {'name': 'verifyingContract', 'type': 'address'},
      ],
      'FlashOrder': [
        {'name': 'quoteId', 'type': 'string'},
        {'name': 'funder', 'type': 'address'},
      ],
    },
    'primaryType': 'FlashOrder',
    'domain': {
      'name': 'DefinitiveFlashAllowance',
      'version': '1',
      'chainId': '8453',
      'verifyingContract': '0x5d00000873b6BF41539e6f5365B0Ff7d3c368f78',
    },
    'message': {'quoteId': 'q-123', 'funder': signer},
  };

  test('recovers who signed typed data, the check on what MetaMask sends back', () {
    final sig = EthSigUtil.signTypedData(privateKeyInBytes: key, jsonData: jsonEncode(typed), version: TypedDataVersion.V4);
    expect(EvmSigner.recoverTyped(typed, sig).toLowerCase(), signer.toLowerCase());
    // The same signature over a different order names someone else.
    final edited = jsonDecode(jsonEncode(typed)) as Map<String, dynamic>;
    (edited['message'] as Map)['quoteId'] = 'q-999';
    expect(EvmSigner.recoverTyped(edited, sig).toLowerCase(), isNot(signer.toLowerCase()));
  });

  test('recovers a personal_sign message: the connect code and Flash’s cancel', () {
    final account = EthPrivateKey.fromHex(keyHex);
    for (final message in [EvmSigner.connectMessage('abcDEF123_-xyz0987654'), 'Definitive Flash v1 — Cancel Order\nOrder: 1']) {
      final sig = '0x${bytesToHexString(account.signPersonalMessageToUint8List(utf8.encode(message)))}';
      expect(EvmSigner.recoverMessage(message, sig).toLowerCase(), signer.toLowerCase());
    }
    expect(EvmSigner.connectMessage('X'), 'Glyf: use this wallet to sign\nCode: X');
  });

  test('builds MetaMask’s requests the way eth_sendTransaction, typed data and personal_sign take them', () {
    const from = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266';
    final tx = EvmCall(to: '0x2626664c2603336E57B271c5C0b26F421741e481', data: '0x5ae401dc',
        value: BigInt.parse('50000000000000000'), gas: BigInt.from(21000));
    expect(EvmSigner.txJson(from, tx), {
      'from': from,
      'to': '0x2626664c2603336E57B271c5C0b26F421741e481',
      'data': '0x5ae401dc',
      'value': '0xb1a2bc2ec50000',
      'gas': '0x5208',
    });
    final typedRpc = EvmSigner.signRpc(from, TypedStep(EvmChain.base, 'Sign the stop-loss', jsonEncode(typed)));
    expect(typedRpc['method'], 'eth_signTypedData_v4');
    expect((jsonDecode((typedRpc['params'] as List)[1] as String) as Map)['primaryType'], 'FlashOrder');
    expect(EvmSigner.signRpc(from, MessageStep(EvmChain.base, 'Cancel', 'hi')),
        {'method': 'personal_sign', 'params': ['0x6869', from]});
  });

  test('speaks MetaMask’s deeplink protocol: a base64 message on mmsdk, an answer back on glyf://mmsdk', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const from = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266';
    final (id, url) = await MetaMaskLink.requestLink('personal_sign', ['0x6869', from], account: from, chainId: 8453);
    final uri = Uri.parse(url);
    expect('${uri.scheme}://${uri.host}', 'metamask://mmsdk');
    expect(uri.queryParameters['scheme'], 'glyf');
    expect(uri.queryParameters['account'], '$from@0x2105');
    final sent = jsonDecode(utf8.decode(base64.decode(uri.queryParameters['message']!))) as Map;
    expect(sent, {'id': id, 'jsonrpc': '2.0', 'method': 'personal_sign', 'params': ['0x6869', from]});
    // What MetaMask opens with: data carries the answer, the accounts and the chain it's on.
    final answer = base64.encode(utf8.encode(jsonEncode(
        {'data': {'id': id, 'result': '0xsig', 'accounts': [from], 'chainId': '0x2105'}, 'name': 'metamask-provider'})));
    expect(MetaMaskLink.handle(Uri.parse('glyf://mmsdk?message=${Uri.encodeComponent(answer)}')), isTrue);
    expect(MetaMaskLink.walletChain, '0x2105');
    final reply = MetaMaskReply.from({'id': '7', 'error': {'code': 4001, 'message': 'User rejected'}});
    expect(reply.error?.refused, isTrue);
    expect(MetaMaskLink.handle(Uri.parse('glyf://phantom?x=1')), isFalse);
  });
}

String bytesToHexString(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
