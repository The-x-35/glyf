package com.arpit.glyf

/**
 * MetaMask's own deeplinks on Android (lib/evm/metamask_link.dart): Glyf
 * opens metamask://connect and metamask://mmsdk in the MetaMask app by its
 * package, and MetaMask answers on glyf://mmsdk, which MainActivity's glyf
 * filter hands to Dart like every other glyf:// link. The bridge's
 * openMetaMask (GlyfBridge.kt) answers false when MetaMask isn't installed,
 * as iOS's does.
 */
object MetaMaskLinks {
    /** MetaMask Mobile on Google Play. */
    const val PACKAGE = "io.metamask"

    /** Only MetaMask's own scheme is opened this way, nothing else. */
    fun accepts(url: String?): Boolean =
        url != null && url.length <= 64_000 && url.startsWith("metamask://", ignoreCase = true)
}
