import 'dart:convert';

import 'package:eth_sig_util/eth_sig_util.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/evm/evm_chains.dart';
import 'package:glyf/evm/evm_signer.dart';
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
    // Must stay word for word what the server puts in the job (lib/walletjobs.ts).
    expect(EvmSigner.connectMessage('X'), 'Glyf: use this wallet to sign\nCode: X');
  });

  test('steps go to the server the way its job takes them', () {
    final tx = TxStep(EvmChain.base, 'Swap ETH for USDC',
        EvmCall(to: '0x2626664c2603336E57B271c5C0b26F421741e481', data: '0x5ae401dc', value: BigInt.parse('50000000000000000')));
    expect(EvmSigner.stepJson(tx), {
      'type': 'tx',
      'chainId': 8453,
      'to': '0x2626664c2603336E57B271c5C0b26F421741e481',
      'data': '0x5ae401dc',
      'value': '50000000000000000',
      'label': 'Swap ETH for USDC',
    });
    final signed = EvmSigner.stepJson(TypedStep(EvmChain.base, 'Sign the stop-loss', jsonEncode(typed)));
    expect(signed['type'], 'typed');
    expect((signed['data'] as Map)['primaryType'], 'FlashOrder');
    expect(EvmSigner.stepJson(MessageStep(EvmChain.base, 'Cancel', 'hi')), {'type': 'message', 'message': 'hi', 'label': 'Cancel'});
  });

  test('opens the page inside each wallet’s own browser', () {
    const page = 'https://api.tryglyf.com/w/abc';
    expect(EvmSigner.walletLink(EvmSignerKind.metamask, page), 'https://metamask.app.link/dapp/api.tryglyf.com/w/abc');
    expect(EvmSigner.walletLink(EvmSignerKind.phantom, page),
        'https://phantom.app/ul/browse/https%3A%2F%2Fapi.tryglyf.com%2Fw%2Fabc?ref=https%3A%2F%2Fapi.tryglyf.com');
  });
}

String bytesToHexString(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
