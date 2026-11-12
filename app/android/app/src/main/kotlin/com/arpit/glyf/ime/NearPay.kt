package com.arpit.glyf.ime

import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale

/**
 * A pay link to ask for (POST /near/requests; docs/NEAR-SPEC.md, Hand-off:
 * the keyboard's Request button): from the bill split's chip ("$22.50
 * each") or the strip AI's near.request. The keyboard adds where the
 * person is paid and posts it; the answer's `text` goes in the chat as is.
 * The twin of NearPay.swift's PayAsk, rule for rule.
 */
data class PayAsk(
    /** The total when `each` is false and `count` is set; each payer's
     *  share when `each` is true. As typed ("22.5", "1200"). */
    val amount: String,
    val coin: String? = null,
    /** Where the requester wants to be paid, when the words said. */
    val chain: String? = null,
    val each: Boolean = false,
    val count: Int? = null,
    /** The writer is one of `count` ("$90 for 4 of us"). */
    val us: Boolean = false,
    val note: String? = null,
) {
    /** POST /near/requests' body. */
    fun body(to: String, chain: String): JSONObject {
        val b = JSONObject().put("amount", amount).put("to", to).put("chain", chain)
        coin?.let { b.put("coin", it) }
        if (each) b.put("each", true)
        count?.let { b.put("count", it) }
        if (us) b.put("us", true)
        note?.takeIf { it.isNotEmpty() }?.let { b.put("note", it) }
        return b
    }

    companion object {
        const val NO_WALLET = "Add a wallet in Glyf to get paid"

        /** The near.request action's params, as they came (checked on the server). */
        fun of(p: Map<String, String>): PayAsk? {
            val amount = p["amount"]?.takeIf { TradeIntent.number(it) != null } ?: return null
            return PayAsk(amount, coin = p["coin"], chain = p["chain"], each = p["each"] == "true",
                count = p["count"]?.let { it.toIntOrNull() ?: TradeIntent.number(it)?.toInt() },
                us = p["us"] == "true", note = p["note"])
        }

        /** The bill split's ask: the total and the headcount, "of us" or "we"
         *  making the writer one of them, and what it was for when the words
         *  lead with it ("dinner was $90 for 4 of us"). Dollars only. */
        fun split(text: String, total: Double, count: Int): PayAsk {
            val lower = text.lowercase(Locale.US)
            val us = Regex("""\b(of us|we)\b""").containsMatchIn(lower)
            return PayAsk(TradeIntent.trimmed(TradeIntent.rounded(total * 100) / 100), count = count, us = us,
                note = billNote(lower))
        }

        private val plain = setOf("bill", "check", "total", "tab", "cost", "amount", "it", "that", "this", "price")

        /** What a bill was for: "dinner was $90…", "the cabin is $1,200…",
         *  "split the cab $60…". Words that only say it's a bill don't count. */
        fun billNote(lower: String): String? {
            val patterns = listOf(
                """(?:^|[.!?]\s*)(?:the\s+|our\s+)?([a-z]{3,20})\s+(?:was|is|came to|cost|costs)\s+\$""",
                """\bsplit\s+(?:the\s+|our\s+)?([a-z]{3,20})\s+(?:of\s+)?\$""",
            )
            for (p in patterns) {
                val word = Regex(p).find(lower)?.groupValues?.get(1) ?: continue
                if (word !in plain) return word
            }
            return null
        }

        /** The requester's own receiving address: on the chain asked, the
         *  wallet there (Phantom on Solana, MetaMask on EVM chains, the saved
         *  NEAR account on NEAR); with none asked, MetaMask on Base, else the
         *  NEAR account. Null: no wallet to be paid in, nothing is posted. */
        fun receiver(chain: String?, evm: String?, solana: String?, near: String?): Pair<String, String>? {
            fun has(s: String?) = s?.takeIf { it.isNotEmpty() }
            if (chain != null) {
                if (chain == "solana") return has(solana)?.let { it to chain }
                if (chain == "near") return has(near)?.let { it to chain }
                if (chain in TradeIntent.evmChains) return has(evm)?.let { it to chain }
                return null
            }
            has(evm)?.let { return it to "base" }
            has(near)?.let { return it to "near" }
            return null
        }
    }
}

/**
 * A look at the group pot, or a payout from it to propose (docs/NEAR-SPEC.md,
 * The group pot on Sputnik DAO): read from the words on the phone ("how much
 * is in the trip pot", "pay the caterer $120 from the pot") or named by the
 * strip's AI (near.pot, near.pot.pay). NearPay.swift's PotAsk.
 */
data class PotAsk(
    val pay: Boolean,
    /** The word before "pot" ("trip"), which the saved pot stands for. */
    val pot: String? = null,
    /** A typed *.sputnik-dao.near. */
    val dao: String? = null,
    /** Who's paid: a NEAR account, or the words for them ("the caterer"). */
    val to: String? = null,
    val amount: String? = null,
    val coin: String = "USDC",
    val note: String? = null,
) {
    val params: Map<String, String>
        get() {
            val p = linkedMapOf<String, String>()
            pot?.let { p["pot"] = it }
            dao?.let { p["dao"] = it }
            to?.let { p["to"] = it }
            amount?.let { p["amount"] = it }
            if (pay) p["coin"] = coin
            note?.let { p["note"] = it }
            return p
        }

    /** "trip pot", or "pot". */
    val potName: String
        get() = dao?.let { it.replace(".sputnik-dao.near", "") + " pot" } ?: pot?.let { "$it pot" } ?: "pot"

    /** The chip's words, the server's (lib/actions.ts actionLabel). */
    val label: String
        get() {
            val t = to; val a = amount
            if (!pay || t == null || a == null) return "See the $potName · Sputnik DAO"
            val who = t.replace(Regex("""^the\s+""", RegexOption.IGNORE_CASE), "")
            return "Propose ${money(a, coin)} to $who from the $potName · Sputnik DAO"
        }

    /** The pot meant: the typed DAO, else the saved pot (or a Sputnik DAO
     *  saved as the NEAR account), else the word's ("trip" →
     *  trip.sputnik-dao.near). Null: "Add your pot in Glyf". */
    fun daoAccount(saved: String?, account: String?): String? {
        dao?.let { return it }
        saved?.lowercase(Locale.US)?.takeIf { isDAO(it) }?.let { return it }
        account?.lowercase(Locale.US)?.takeIf { isDAO(it) }?.let { return it }
        return pot?.let { "$it.sputnik-dao.near" }
    }

    companion object {
        const val NO_POT = "Add your pot in Glyf"

        /** The action's params (near.pot, near.pot.pay). */
        fun of(p: Map<String, String>, pay: Boolean): PotAsk? {
            val a = PotAsk(pay, pot = p["pot"], dao = p["dao"], to = p["to"], amount = p["amount"],
                coin = (p["coin"] ?: "USDC").uppercase(Locale.US), note = p["note"])
            if (pay && (a.to == null || a.amount == null)) return null
            return a
        }

        /** "$120", "5 NEAR". */
        fun money(amount: String, coin: String): String = if (coin == "USDC") TradeIntent.dollars(amount) else "$amount $coin"

        fun isDAO(s: String): Boolean = Regex("""^[a-z0-9][a-z0-9_-]*\.sputnik-dao\.near$""").matches(s)

        /** A NEAR account as Trezu pays it: a name.near or 64 hex. */
        fun isNEARAccount(s: String): Boolean = TradeIntent.nearRecipientChain(s.lowercase(Locale.US)) == "near"

        // MARK: reading (server lib/nearphrase.ts parsePotPhrase, the same phrases)

        private const val POT = """(?:(?:(?:the|our|my)\s+)?(?:([a-z][a-z0-9-]{1,20})\s+)?(?:pot|treasury|kitty)|([a-z0-9][a-z0-9_-]*\.sputnik-dao\.near))"""
        private val notPotWord = setOf("the", "our", "my", "a", "shared", "group")

        fun parse(text: String): PotAsk? {
            val t = text.trim().replace(Regex("""\s+"""), " ").replace(Regex("""[.!?]$"""), "")
            val lower = t.lowercase(Locale.US)
            if (listOf("pot", "treasury", "kitty", "sputnik").none { lower.contains(it) }) return null
            val balances = listOf(
                """^(?:how much|what)(?:'s| is| do we have)?\s+(?:left\s+)?in\s+""" + POT + """(?:\s+left)?$""",
                """^(?:check|show(?:\s+me)?|open)\s+""" + POT + """(?:\s+balance)?$""",
                "^" + POT + """\s+balance$""",
            )
            for (p in balances) {
                val m = groups(p, lower) ?: continue
                return PotAsk(false).named(m[1], m[2])
            }
            val money = """(?:\$\s?(\d+(?:\.\d+)?)|(\d+(?:\.\d+)?)\s*(usdc|usdt|near|dollars|bucks))"""
            val payP = """^(?:pay|send|give)\s+((?:the\s+)?[a-z][a-z0-9._-]{0,63}(?:\s+[a-z][a-z0-9._-]{0,30})?)\s+""" + money +
                """\s+(?:from|out of)\s+""" + POT + """(?:\s+for\s+([a-z][a-z0-9 '&-]{1,40}))?$"""
            val m = groups(payP, lower) ?: return null
            val payee = m[1] ?: return null
            val dollars = m[2] != null || (m[4] ?: "") in setOf("dollars", "bucks")
            return PotAsk(true, to = payee.trim(), amount = m[2] ?: m[3],
                coin = if (dollars) "USDC" else (m[4] ?: "usdc").uppercase(Locale.US),
                note = m[7]?.trim()).named(m[5], m[6])
        }

        private fun groups(pattern: String, text: String): List<String?>? {
            val m = Regex(pattern, RegexOption.IGNORE_CASE).find(text) ?: return null
            return (0..m.groupValues.lastIndex).map { m.groups[it]?.value }
        }
    }

    private fun named(word: String?, dao: String?): PotAsk = when {
        dao != null -> copy(dao = dao)
        word != null && word !in notPotWord -> copy(pot = word)
        else -> this
    }
}

/** GET /near/pot's answer, as the pot card shows it. NearPay.swift's PotView. */
data class PotView(
    val text: String? = null,
    val dao: String? = null,
    val trezu: String? = null,
    /** Open proposals (still taking votes), newest first. */
    val open: List<Proposal> = emptyList(),
    val error: String? = null,
) {
    data class Proposal(val id: Int, val line: String, val url: String?)

    companion object {
        fun of(ok: Boolean, obj: JSONObject?): PotView {
            if (!ok || obj == null || obj.optBoolean("ok", true) == false) {
                val words = obj?.optString("error").orEmpty()
                return PotView(error = words.ifEmpty { "NEAR didn't answer. Try again in a moment" })
            }
            val open = mutableListOf<Proposal>()
            val list = obj.optJSONArray("proposals") ?: JSONArray()
            for (k in 0 until list.length()) {
                val p = list.optJSONObject(k) ?: continue
                if (p.optString("status") != "InProgress") continue
                val id = NearPay.number(p.opt("id"))?.toInt() ?: continue
                open.add(Proposal(id, line(p, id), NearPay.string(p, "url")))
            }
            return PotView(text = NearPay.string(obj, "text"), dao = NearPay.string(obj, "dao"),
                trezu = obj.optJSONObject("links")?.let { NearPay.string(it, "trezu") }, open = open)
        }

        /** "#5 12.5 NEAR to caterer.near · 1 more approval"; a proposal that
         *  isn't a payout reads by its description. */
        fun line(p: JSONObject, id: Int): String {
            val amount = NearPay.string(p, "amount"); val coin = NearPay.string(p, "coin"); val to = NearPay.string(p, "receiver")
            val what = if (amount != null && coin != null && to != null) "$amount $coin to $to" else {
                val d = (NearPay.string(p, "description") ?: "").split("\n").first()
                d.ifEmpty { NearPay.string(p, "kind") ?: "Proposal" }
            }
            var line = "#$id $what"
            val n = NearPay.number(p.opt("approvalsNeeded"))?.toInt()
            if (n != null && n > 0) line += " · $n more approval${if (n == 1) "" else "s"}"
            return line
        }
    }
}

/** GET /near/pot/propose-link's answer, as the payout panel shows it. */
data class PotProposal(
    val url: String? = null,
    val text: String? = null,
    /** "Propose $120 to caterer.near · needs 2 of 3 · bond 0.1 NEAR". */
    val headline: String? = null,
    /** "Type 120 USDC, note: catering": what Trezu doesn't prefill. */
    val fill: String? = null,
    /** The person can't file it: "Only members can propose from this pot". */
    val notMember: Boolean = false,
    val error: String? = null,
) {
    companion object {
        const val MEMBERS_ONLY = "Only members can propose from this pot"

        fun of(ok: Boolean, obj: JSONObject?, to: String, account: String?): PotProposal {
            if (!ok || obj == null || obj.optBoolean("ok", true) == false) {
                val words = obj?.optString("error").orEmpty()
                return PotProposal(error = words.ifEmpty { "NEAR didn't answer. Try again in a moment" })
            }
            val fill = obj.optJSONObject("fill")
            val amount = fill?.let { NearPay.string(it, "amount") } ?: ""
            val coin = fill?.let { NearPay.string(it, "coin") } ?: "USDC"
            var head = "Propose ${PotAsk.money(amount, coin)} to $to"
            obj.optJSONObject("threshold")?.let { NearPay.string(it, "words") }?.let { head += " · needs $it" }
            NearPay.string(obj, "bond")?.let { head += " · bond $it NEAR" }
            val note = fill?.let { NearPay.string(it, "note") }?.takeIf { it.isNotEmpty() }
            val proposers = obj.optJSONArray("proposers")
            val notMember = proposers != null &&
                (0 until proposers.length()).none { proposers.optString(it) == (account ?: "").lowercase(Locale.US) }
            return PotProposal(url = NearPay.string(obj, "url"), text = NearPay.string(obj, "text"), headline = head,
                fill = "Type $amount $coin" + (note?.let { ", note: $it" } ?: ""), notMember = notMember)
        }
    }
}

/** Earn's answer (POST /near/earn/quote, or GET /near/earn/vaults for
 *  everything out), as the trade panel's Earn mode shows it. EarnQuote in
 *  TradeIntent.swift. */
data class EarnQuote(
    /** "≈ $49.75 in Gauntlet USDC Prime at 4.5% APY". */
    val words: String? = null,
    val vaultName: String? = null,
    val protocolName: String? = null,
    /** Percent a year; null when the vault's own API didn't say. */
    val apy: Double? = null,
    val seconds: Int? = null,
    val error: String? = null,
) {
    /** "4.5% APY", or "APY n/a" when no one said. */
    val apyText: String get() = apy?.let { "${TradeIntent.trimmed(TradeIntent.rounded(it * 100) / 100)}% APY" } ?: "APY n/a"

    /** "Morpho · 4.5% APY". */
    fun vaultLine(fallback: String): String = "${protocolName ?: fallback} · $apyText"

    /** "~52 s", "~2 min". */
    val time: String?
        get() {
            val s = seconds ?: return null
            if (s <= 0) return null
            return if (s < 90) "~$s s" else "~${TradeIntent.rounded(s / 60.0).toInt()} min"
        }

    companion object {
        /** 1Click's ToS §7, in a line. */
        const val NOTICE = "Yield isn't guaranteed; NEAR Intents doesn't run the vault"

        fun of(ok: Boolean, obj: JSONObject?): EarnQuote {
            if (!ok || obj == null || obj.optBoolean("ok", true) == false) {
                val words = obj?.optString("error").orEmpty()
                return EarnQuote(error = words.ifEmpty { "No quote right now" })
            }
            val vault = obj.optJSONObject("vault")
            return EarnQuote(words = NearPay.string(obj, "words"), vaultName = vault?.let { NearPay.string(it, "name") },
                protocolName = vault?.let { NearPay.string(it, "protocol") }, apy = NearPay.number(vault?.opt("apy")),
                seconds = NearPay.number(obj.opt("timeSeconds"))?.let { TradeIntent.rounded(it).toInt() })
        }

        /** GET /near/earn/vaults' row for [id]: the vault without a quote. */
        fun vault(id: String, list: JSONObject?): EarnQuote {
            val rows = list?.optJSONArray("vaults") ?: return EarnQuote()
            for (k in 0 until rows.length()) {
                val r = rows.optJSONObject(k) ?: continue
                if (r.optString("id") != id) continue
                return EarnQuote(vaultName = NearPay.string(r, "name"), protocolName = NearPay.string(r, "protocol"),
                    apy = NearPay.number(r.opt("apy")))
            }
            return EarnQuote()
        }
    }
}

object NearPay {
    /** The params a chip carries in its query, as JSON (keys sorted, as iOS). */
    fun chipQuery(params: Map<String, String>): String {
        val o = JSONObject()
        for (k in params.keys.sorted()) o.put(k, params[k])
        return o.toString()
    }

    fun params(query: String): Map<String, String> {
        val o = runCatching { JSONObject(query) }.getOrNull() ?: return emptyMap()
        val out = linkedMapOf<String, String>()
        for (k in o.keys()) (o.opt(k) as? String)?.let { out[k] = it }
        return out
    }

    /** A number as the server sends it: a number or a string. */
    fun number(any: Any?): Double? = when (any) {
        is Number -> any.toDouble()
        is String -> TradeIntent.number(any)
        else -> null
    }

    /** A string field, null when missing or JSON null. */
    fun string(o: JSONObject, key: String): String? = if (o.isNull(key)) null else o.opt(key) as? String
}
