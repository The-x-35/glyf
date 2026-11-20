package com.arpit.glyf.ime

import android.content.Context
import android.content.Intent
import android.net.Uri

/** Which wallet signs a Solana payment on this phone, as the keyboard names
 *  it. The app asks a Mobile Wallet Adapter wallet first (the Seeker's own
 *  wallet, or any other), which signs right on the phone; only without one
 *  does Phantom sign by deeplink (WalletFlow.connect). Glyf never names or
 *  touches Seed Vault itself: the dApp Store allows that to wallet apps only
 *  (rejected 20 Nov 2026 for "Connect Seed Vault"). */
object SolanaWallet {
    /** Packages that answer Mobile Wallet Adapter on this phone; empty until [refresh]. */
    @Volatile var mwaPackages: List<String> = emptyList()

    fun refresh(context: Context) {
        mwaPackages = try {
            context.packageManager
                .queryIntentActivities(Intent(Intent.ACTION_VIEW, Uri.parse("solana-wallet:/v1/associate/local")), 0)
                .map { it.activityInfo.packageName }
        } catch (_: Exception) {
            emptyList()
        }
    }

    /** "your wallet" when a Mobile Wallet Adapter wallet is here, else "Phantom". */
    fun name(packages: List<String> = mwaPackages): String =
        if (packages.isNotEmpty()) "your wallet" else "Phantom"

    /** [name] at the start of a sentence. */
    fun title(packages: List<String> = mwaPackages): String = name(packages).replaceFirstChar { it.uppercase() }
}
