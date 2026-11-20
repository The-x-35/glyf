package com.arpit.glyf.ime

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Test

/** The keyboard names the wallet that will sign: any Mobile Wallet Adapter
 *  wallet (the Seeker's own included) as "your wallet", else Phantom. Never
 *  "Seed Vault": the dApp Store rejects apps that name it. */
class SolanaWalletTest {
    @After fun reset() { SolanaWallet.mwaPackages = emptyList() }

    @Test fun aSeekerSaysYourWalletNeverSeedVault() {
        assertEquals("your wallet", SolanaWallet.name(listOf("com.solanamobile.wallet", "app.phantom")))
        assertEquals("Your wallet", SolanaWallet.title(listOf("com.solanamobile.wallet")))
    }

    @Test fun anotherMwaWalletIsYourWallet() {
        assertEquals("your wallet", SolanaWallet.name(listOf("com.solflare.mobile")))
        assertEquals("Your wallet", SolanaWallet.title(listOf("com.solflare.mobile")))
    }

    @Test fun noMwaWalletMeansPhantom() {
        assertEquals("Phantom", SolanaWallet.name(emptyList()))
    }

    @Test fun tradesOnSolanaNameTheSameWallet() {
        SolanaWallet.mwaPackages = listOf("com.solanamobile.wallet")
        assertEquals("Your wallet", TradeIntent.walletName("solana"))
        assertEquals("MetaMask", TradeIntent.walletName("base"))
    }
}
