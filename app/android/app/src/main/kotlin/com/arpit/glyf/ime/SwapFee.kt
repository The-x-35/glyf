package com.arpit.glyf.ime

import org.json.JSONObject
import java.net.URLEncoder

/**
 * Glyf's fee on a buy: Jupiter's referral fee on Swap V2 /order
 * (docs/SWAP-FEE.md). Off while [REFERRAL_ACCOUNT] is empty, and then the
 * Buy quote is asked exactly as before. Twins: SwapFee in
 * lib/wallet/wallet_api.dart (which builds the real order) and
 * GlyfKeyboard/Engine/TokenLookup.swift. The keyboard only prices; the fee
 * must match the app's.
 */
object SwapFee {
    /** The referral account made at referral.jup.ag under Jupiter's Ultra
     *  referral project. Public, not a secret. */
    const val REFERRAL_ACCOUNT = ""

    /** 0.5%. Jupiter takes 50 to 255 and keeps a fifth of it. */
    const val BPS = 50

    /** The /order quote link for the Buy panel: keyless, no taker. */
    fun orderUrl(inputMint: String, outputMint: String, units: Long, referral: String = REFERRAL_ACCOUNT): String {
        val base = "https://api.jup.ag/swap/v2/order?inputMint=${URLEncoder.encode(inputMint, "UTF-8")}" +
            "&outputMint=${URLEncoder.encode(outputMint, "UTF-8")}&amount=$units"
        if (referral.isEmpty()) return base
        return "$base&referralAccount=${URLEncoder.encode(referral, "UTF-8")}&referralFee=$BPS"
    }

    /** The fee Jupiter says it applied for Glyf, from an /order answer. */
    fun applied(json: JSONObject): Int? {
        if (json.isNull("referralAccount") || json.optString("referralAccount").isEmpty()) return null
        return if (json.has("feeBps")) json.optInt("feeBps", BPS) else BPS
    }

    /** "Fee 0.5%". */
    fun label(bps: Int): String {
        val pct = String.format(java.util.Locale.US, "%.2f", bps / 100.0).trimEnd('0').trimEnd('.')
        return "Fee $pct%"
    }
}
