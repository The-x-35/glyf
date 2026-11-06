// Whitechain Sepolia network constants (docs.whitechain.io/learn/network/reference).
import { defineChain } from 'viem';

export const whitechainSepolia = defineChain({
  id: 1874,
  name: 'Whitechain Sepolia',
  nativeCurrency: { name: 'WBT', symbol: 'WBT', decimals: 18 },
  rpcUrls: { default: { http: [process.env.WHITECHAIN_RPC || 'https://rpc.testnet.whitechain.io'] } },
  blockExplorers: { default: { name: 'Whitechain Explorer', url: 'https://explorer.testnet.whitechain.io' } },
  testnet: true,
});

export const EXPLORER = 'https://explorer.testnet.whitechain.io';
export const TEST_USDT = '0xcedfB56113143d55b2358b8CFbB0dEB5Ad2f55a7';
