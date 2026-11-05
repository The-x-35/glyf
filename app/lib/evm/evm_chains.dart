/// The EVM chains Glyf signs on. `name` is the server's (and Flash's)
/// word for the chain; the keyboard says it the way people do.
class EvmChain {
  const EvmChain(this.id, this.name, this.label, this.explorer, {this.native = 'ETH', this.testnet = false});

  final int id;
  final String name;
  final String label;

  /// Transaction pages live at `$explorer/tx/<hash>`.
  final String explorer;
  final String native;
  final bool testnet;

  String txUrl(String hash) => '$explorer/tx/$hash';
  String addressUrl(String address) => '$explorer/address/$address';

  static const ethereum = EvmChain(1, 'ethereum', 'Ethereum', 'https://etherscan.io');
  static const base = EvmChain(8453, 'base', 'Base', 'https://basescan.org');
  static const arbitrum = EvmChain(42161, 'arbitrum', 'Arbitrum', 'https://arbiscan.io');
  static const optimism = EvmChain(10, 'optimism', 'Optimism', 'https://optimistic.etherscan.io');
  static const polygon = EvmChain(137, 'polygon', 'Polygon', 'https://polygonscan.com', native: 'POL');
  static const unichain = EvmChain(130, 'unichain', 'Unichain', 'https://uniscan.xyz');
  static const baseSepolia =
      EvmChain(84532, 'base-sepolia', 'Base Sepolia', 'https://sepolia.basescan.org', testnet: true);
  static const sepolia = EvmChain(11155111, 'sepolia', 'Sepolia', 'https://sepolia.etherscan.io', testnet: true);

  /// Whitechain's OP Stack testnet: USDT payment requests (GlyfPayRequest).
  static const whitechainSepolia = EvmChain(1874, 'whitechain-sepolia', 'Whitechain',
      'https://testnet.whitechain.io', native: 'WBT', testnet: true);

  /// Arkiv's DB-chain testnet: where the encrypted vault backup lives.
  static const arkiv = EvmChain(7794095, 'arkiv', 'Arkiv', 'https://rabdi.explorer.arkiv.network',
      native: 'ETH', testnet: true);

  static const all = [
    ethereum, base, arbitrum, optimism, polygon, unichain, baseSepolia, sepolia, whitechainSepolia, arkiv,
  ];

  /// Trading chains, in the order a picker shows them.
  static const trading = [base, ethereum, arbitrum, optimism, polygon, unichain];

  static EvmChain? named(String? name) {
    if (name == null) return null;
    final n = name.toLowerCase().trim();
    for (final c in all) {
      if (c.name == n || c.label.toLowerCase() == n || '${c.id}' == n) return c;
    }
    return switch (n) {
      'eth' || 'mainnet' => ethereum,
      'arb' => arbitrum,
      'op' => optimism,
      'matic' => polygon,
      'whitechain' || 'wbt' => whitechainSepolia,
      _ => null,
    };
  }

  static EvmChain? byId(int id) {
    for (final c in all) {
      if (c.id == id) return c;
    }
    return null;
  }
}
