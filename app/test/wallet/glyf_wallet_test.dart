import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyf/evm/evm_signer.dart';
import 'package:glyf/evm/evm_wallet.dart';
import 'package:glyf/wallet/base58.dart';
import 'package:glyf/wallet/flash_solana.dart';
import 'package:glyf/wallet/glyf_keys.dart';
import 'package:glyf/wallet/hd_keys.dart';
import 'package:glyf/wallet/solana.dart';
import 'package:glyf/wallet/wallet_flow.dart';
import 'package:glyf/wallet/wallet_mode.dart';
import 'package:pinenacl/ed25519.dart' as ed;

const abandon = 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
// web3dart's createRandom made keys like this one before phrases (hardhat #0).
const oldKey = 'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';
const oldAddress = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const bridge = MethodChannel('so.glyf/bridge');
  late Map<String, String> secrets;
  late Map<String, dynamic> shared;

  setUp(() {
    secrets = {};
    shared = {};
    GlyfKeys.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(bridge, (call) async {
      final args = (call.arguments as Map?)?.cast<String, Object?>() ?? const {};
      switch (call.method) {
        case 'walletSecretLoad':
          return secrets[args['name']];
        case 'walletSecretSave':
          secrets[args['name'] as String] = args['value'] as String;
          return true;
        case 'walletSecretClear':
          secrets.remove(args['name']);
          return true;
        case 'readSharedSettings':
          return jsonEncode(shared);
        case 'writeSharedSettings':
          shared = jsonDecode(args['json'] as String) as Map<String, dynamic>;
          return true;
      }
      return null;
    });
  });

  tearDown(() async {
    await EvmWallet.forget();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(bridge, null);
  });

  group('the Glyf wallet', () {
    test('a new wallet is 24 words, both addresses from them, only public ones shared', () async {
      final evm = await EvmWallet.ensure();
      final phrase = secrets[GlyfKeys.phraseName]!;
      expect(Bip39.isValid(phrase), isTrue);
      final keys = PhraseKeys.of(phrase);
      expect(GlyfKeys.solanaAddress.value, keys.solanaAddress);
      expect(GlyfKeys.evmKeyHex, keys.evmKeyHex);
      expect(shared['evmAddress'], evm);
      await WalletFlow.load();
      expect(shared['walletAddress'], keys.solanaAddress);
      // No secret ever reaches the keyboard's settings.
      final text = jsonEncode(shared);
      expect(text.contains(phrase.split(' ').first) && text.contains(phrase), isFalse);
      expect(text.contains(keys.evmKeyHex.substring(2)), isFalse);
      expect(text.contains(keys.solanaSecretBase58), isFalse);
    });

    test('a phrase on the phone opens the addresses MetaMask and Phantom show', () async {
      secrets[GlyfKeys.phraseName] = abandon;
      expect(await EvmWallet.load(), '0x9858EfFD232B4033E47d90003D41EC34EcaEda94');
      expect(GlyfKeys.solanaAddress.value, 'HAgk14JpMQLgt6rVgv7cBQFJWFto5Dqxi472uT3DKpqk');
      expect(GlyfKeys.hasPhrase, isTrue);
    });

    test('an old random-key wallet keeps its address, and ensure never replaces it', () async {
      secrets[GlyfKeys.legacyName] = oldKey;
      expect(await EvmWallet.load(), oldAddress);
      expect(await EvmWallet.ensure(), oldAddress);
      expect(GlyfKeys.isLegacyOnly, isTrue);
      expect(GlyfKeys.solanaAddress.value, isNull);
      expect(GlyfKeys.evmKeyHex, '0x$oldKey');
      expect(secrets[GlyfKeys.phraseName], isNull);
    });

    test('switching an old wallet to a phrase keeps the old key and its address reachable', () async {
      secrets[GlyfKeys.legacyName] = oldKey;
      await EvmWallet.load();
      final fresh = await EvmWallet.switchToPhrase();
      expect(fresh, isNot(oldAddress));
      expect(secrets[GlyfKeys.legacyName], oldKey);
      expect(GlyfKeys.oldEvmAddress.value, oldAddress);
      expect(GlyfKeys.oldEvmKeyHex, '0x$oldKey');
      expect(GlyfKeys.solanaAddress.value, isNotNull);
      // A second switch changes nothing.
      expect(await EvmWallet.switchToPhrase(), fresh);
    });
  });

  group('Sign with: one switch, every chain', () {
    test('internal is the Glyf wallet on Ethereum and Solana', () {
      final evm = WalletModes.route(solana: false, mode: WalletMode.internal, glyfEvm: '0xA', metamask: '0xM');
      expect((evm.signer, evm.address, evm.missing), (WalletSigner.glyf, '0xA', null));
      final sol = WalletModes.route(solana: true, mode: WalletMode.internal, glyfSolana: 'So1', phantom: 'Ph');
      expect((sol.signer, sol.address), (WalletSigner.glyf, 'So1'));
    });

    test('external is Phantom on Solana and MetaMask on Ethereum', () {
      final evm = WalletModes.route(solana: false, mode: WalletMode.external, glyfEvm: '0xA', metamask: '0xM');
      expect((evm.signer, evm.address), (WalletSigner.metamask, '0xM'));
      final sol = WalletModes.route(solana: true, mode: WalletMode.external, glyfSolana: 'So1', phantom: 'Ph');
      expect((sol.signer, sol.address), (WalletSigner.phantom, 'Ph'));
    });

    test('says how to get what is missing, in one line', () {
      expect(WalletModes.route(solana: true, mode: WalletMode.external).missing, 'Connect Phantom in Profile › Wallet');
      expect(WalletModes.route(solana: false, mode: WalletMode.external, glyfEvm: '0xA').missing,
          'Connect MetaMask in Profile › Wallet');
      expect(WalletModes.route(solana: false, mode: WalletMode.internal).missing,
          'Make your Glyf wallet in Profile › Wallet');
      expect(WalletModes.route(solana: true, mode: WalletMode.internal, glyfEvm: '0xA').missing,
          'Make a recovery phrase in Profile › Wallet to use Solana');
      // Never falls through to the other kind of wallet.
      expect(WalletModes.route(solana: true, mode: WalletMode.external, glyfSolana: 'So1').address, isNull);
    });

    test('unset is internal, unless the phone had picked MetaMask before the switch existed', () {
      expect(WalletMode.of(null), WalletMode.internal);
      expect(WalletMode.of('external'), WalletMode.external);
      expect(WalletModes.fromSettings({}), WalletMode.internal);
      expect(WalletModes.fromSettings({'evmSigner': 'glyf'}), WalletMode.internal);
      expect(WalletModes.fromSettings({'evmSigner': 'metamask'}), WalletMode.external);
      expect(WalletModes.fromSettings({'evmSigner': 'metamask', 'walletMode': 'internal'}), WalletMode.internal);
    });

    test('the app follows the switch and tells the keyboard', () async {
      secrets[GlyfKeys.phraseName] = abandon;
      shared['evmWallets'] = {'metamask': '0x52908400098527886E0F7030069857D2E4169EE7'};
      await EvmSigner.load();
      await WalletFlow.load();
      expect(EvmSigner.kind.value, EvmSignerKind.glyf);
      expect(shared['evmAddress'], '0x9858EfFD232B4033E47d90003D41EC34EcaEda94');
      expect(WalletFlow.link.value?.internal, isTrue);
      expect(shared['walletAddress'], 'HAgk14JpMQLgt6rVgv7cBQFJWFto5Dqxi472uT3DKpqk');

      await WalletModes.set(WalletMode.external);
      await EvmSigner.follow();
      await WalletFlow.load();
      expect(shared['walletMode'], 'external');
      expect(EvmSigner.kind.value, EvmSignerKind.metamask);
      expect(shared['evmSigner'], 'metamask');
      expect(shared['evmAddress'], '0x52908400098527886E0F7030069857D2E4169EE7');
      // No Phantom connected: no Solana wallet signs, and the keyboard has none.
      expect(WalletFlow.link.value, isNull);
      expect(shared.containsKey('walletAddress'), isFalse);
      expect(WalletFlow.route.missing, 'Connect Phantom in Profile › Wallet');
    });
  });

  group('the Glyf wallet signs Solana here', () {
    final keys = PhraseKeys.of(abandon);
    final key = keys.solanaSigner;
    final me = keys.solanaAddress;

    test('a transfer, signed in its own slot, verifies against its address', () {
      final tx = Sol.transferSol(
          from: me, to: '7dHbWXmci3dT8UFYWYZweBLXgycu7Y3iL6trKn1Y7ARj', lamports: BigInt.from(1000),
          blockhash: '4cUD1L9xmQxZD1fRzYRie6q4Bm5DLe3UDfzUuJgGfJTd');
      final signed = SolanaSigning.signTransaction(tx, key)!;
      final parts = FlashSvm.split(signed)!;
      expect(FlashSvm.verify(parts.message, parts.signatures.first, Sol.key(me)!), isTrue);
      expect(WalletFlow.txSignature(signed), Base58.encode(parts.signatures.first));
    });

    test('Flash\'s setup and order message pass the checks Phantom\'s answers do', () {
      final setup = Sol.compileLegacy(feePayer: me, blockhash: '4cUD1L9xmQxZD1fRzYRie6q4Bm5DLe3UDfzUuJgGfJTd', instructions: [
        Instruction('TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA', [AccountMeta(me, signer: true, writable: true)],
            Uint8List.fromList([17])),
      ]);
      expect(FlashSvm.isSignedSetup(SolanaSigning.signTransaction(setup, key)!, setup, me), isTrue);
      const message = 'DFS|m=So11111111111111111111111111111111111111112|t=100000000|h=FmUTW5JA5S4Y71sibJaYv2';
      expect(FlashSvm.verifyMessage(message, SolanaSigning.signMessage(utf8.encode(message), key), me), isTrue);
    });

    test('refuses a transaction it isn\'t a signer of', () {
      final other = ed.SigningKey.fromSeed(Uint8List.fromList(List.filled(32, 9)));
      final tx = Sol.transferSol(
          from: Base58.encode(other.verifyKey.asTypedList), to: me, lamports: BigInt.one,
          blockhash: '4cUD1L9xmQxZD1fRzYRie6q4Bm5DLe3UDfzUuJgGfJTd');
      expect(SolanaSigning.signTransaction(tx, key), isNull);
    });
  });
}
