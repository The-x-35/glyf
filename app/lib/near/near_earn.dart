import '../evm/evm_chains.dart';
import '../evm/evm_rpc.dart';

/// One of Earn's vaults as the app needs it before any quote: where its
/// shares live and what they are, so "take my usdc out of earn" can read
/// how many shares the person holds (docs/NEAR-SPEC.md, Earn).
class EarnVault {
  const EarnVault({
    required this.id,
    required this.chain,
    required this.underlying,
    required this.receipt,
    required this.share,
    required this.decimals,
  });

  /// The server's vault id: `gtusdcp`, `kamino-sol`, `taler-usdc`.
  final String id;

  /// The Glyf chain the shares live on.
  final String chain;

  /// The coin it takes and pays back.
  final String underlying;

  /// The shares' symbol, as 1Click names them.
  final String receipt;

  /// The shares' ERC-20 contract, or their SPL mint on Solana.
  final String share;
  final int decimals;
}

/// The pure parts of Earn: which vault a hand-off means, whose address goes
/// where, how the share balance is asked for and read, and what the
/// keyboard hears at the end.
abstract final class NearEarn {
  static const gtusdcp = EarnVault(
      id: 'gtusdcp',
      chain: 'base',
      underlying: 'USDC',
      receipt: 'gtUSDCp',
      share: '0x0bb69b79bc829e1cfcc34a740110886d98d2bd14',
      decimals: 18);
  static const kaminoSol = EarnVault(
      id: 'kamino-sol',
      chain: 'solana',
      underlying: 'SOL',
      receipt: 'kV-gtSOLb',
      share: '5EBsGgVTubrd7ShJgE89k6nC2bnLzqGCjXb2ejrhtdBK',
      decimals: 9);
  static const talerUsdc = EarnVault(
      id: 'taler-usdc',
      chain: 'ethereum',
      underlying: 'USDC',
      receipt: 'TLO',
      share: '0x0f38f1ce62776d4a0038bc6cac66877a5687383b',
      decimals: 8);

  static const vaults = [gtusdcp, kaminoSol, talerUsdc];

  /// The vault the keyboard named, else the coin's own: USDC → Gauntlet
  /// USDC Prime on Base, SOL → Kamino SOL Balanced. Null for a vault Glyf
  /// doesn't know or a coin with none.
  static EarnVault? vaultFor({String? vault, required String coin}) {
    final id = vault?.trim().toLowerCase() ?? '';
    if (id.isNotEmpty) {
      for (final v in vaults) {
        if (v.id == id || v.receipt.toLowerCase() == id) return v;
      }
      return null;
    }
    return switch (coin.trim().replaceFirst(r'$', '').toUpperCase()) {
      'USDC' => gtusdcp,
      'SOL' => kaminoSol,
      _ => null,
    };
  }

  /// Whose address goes where (docs/NEAR-SPEC.md, POST /near/earn/quote).
  /// In: the shares land in the person's wallet on the vault's chain, and a
  /// refund goes back where the coins came from ([chain]). Out: the shares
  /// are what's paid, so a refund brings them back on the vault's chain,
  /// and the coins land on [chain]. [own] is the person's wallet on a chain.
  static ({String? refundTo, String? recipient}) addresses({
    required bool out,
    required String vaultChain,
    required String chain,
    required String? Function(String chain) own,
  }) =>
      out ? (refundTo: own(vaultChain), recipient: own(chain)) : (refundTo: own(chain), recipient: own(vaultChain));

  /// ERC-20 `balanceOf(owner)` calldata.
  static String balanceOfData(String owner) {
    final hex = owner.toLowerCase().replaceFirst('0x', '');
    if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(hex)) throw ArgumentError.value(owner, 'owner', 'not an EVM address');
    return '0x70a08231${hex.padLeft(64, '0')}';
  }

  /// An eth_call's uint256 answer. A bare "0x" (some nodes, for an account
  /// with nothing) is zero; anything else that isn't hex is null.
  static BigInt? uint256(Object? result) {
    if (result is! String || !result.startsWith('0x')) return null;
    final hex = result.substring(2);
    if (hex.isEmpty) return BigInt.zero;
    if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) return null;
    return BigInt.parse(hex, radix: 16);
  }

  /// [owner]'s balance of the ERC-20 [token] on [chain], through the app's
  /// own read-only EVM RPC (POST /evm/rpc).
  static Future<BigInt> erc20Balance(EvmChain chain, String token, String owner) async {
    final result = await EvmRpc.call(chain, 'eth_call', [
      {'to': token, 'data': balanceOfData(owner)},
      'latest',
    ]);
    final value = uint256(result);
    if (value == null) throw EvmRpcException('The network gave no balance');
    return value;
  }

  /// Whole coins for the last line: dollar coins to the cent, others to
  /// four places, no trailing zeros ("20.01", "0.4685", "50").
  static String coins(String amount, String coin) {
    final d = double.tryParse(amount);
    if (d == null) return amount;
    final cents = const {'USDC', 'USDT', 'DAI'}.contains(coin.toUpperCase());
    var s = d.toStringAsFixed(cents ? 2 : 4);
    while (s.contains('.') && (s.endsWith('0') || s.endsWith('.'))) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  /// The last line and its detail; the keyboard says them as one
  /// ("Earning on 50 USDC · Morpho", "20 USDC back on Base").
  static (String, String?) done({
    required bool out,
    required String amount,
    required String coin,
    required String protocol,
    required String chainName,
  }) {
    final said = '${coins(amount, coin)} ${coin.toUpperCase()}';
    if (out) return ('$said back on $chainName', null);
    return ('Earning on $said', protocol.isEmpty ? null : protocol);
  }
}
