package com.arpit.glyf.ime

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Test

/** The keyboard names the wallet that will sign: Seed Vault on a Seeker,
 *  another Mobile Wallet Adapter wallet as "your wallet", else Phantom. */
class SolanaWalletTest {
    @After fun reset() { SolanaWallet.mwaPackages = emptyList() }

    @Test fun aSeekerNamesSeedVault() {
        assertEquals("Seed Vault", SolanaWallet.name(listOf("com.solanamobile.wallet", "app.phantom")))
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
        assertEquals("Seed Vault", TradeIntent.walletName("solana"))
        assertEquals("MetaMask", TradeIntent.walletName("base"))
    }
}
