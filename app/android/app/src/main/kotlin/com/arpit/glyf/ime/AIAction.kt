package com.arpit.glyf.ime

import org.json.JSONObject
import java.util.Locale

/**
 * The strip's recommended action from POST /suggest (server lib/actions.ts),
 * asked with actions:true: the suggestion model read the pause as a job for
 * one of Glyf's tools and named it with its values, checked on the server.
 * A tap opens that tool with the values filled in, for the person to check
 * and change; nothing runs from the strip. The twin of AIAction.swift.
 *
 * Trades go through the same reader as typed words (TradeIntent.parse), so
 * the AI's "stop-loss ETH at 3000" opens the very panel the words would.
 * Android opens what this keyboard has: trades, an event, a Meet link,
 * Search, YouTube, Shorts and Maps, translate, a rewrite and a conversion.
 */
data class AIAction(val tool: String, val label: String, val params: Map<String, String>) {

    /** The words a person would type for a trade, read by TradeIntent. */
    val tradeWords: String?
        get() {
            val p = params
            val on = p["chain"]?.let { " on $it" } ?: ""
            return when (tool) {
                "trade.swap" -> {
                    val sell = p["sell"] ?: return null
                    val buy = p["buy"] ?: return null
                    val a = p["amount"]
                    if (p["usd"] == "true" && a != null) "buy $$a of $buy with $sell$on"
                    else "swap ${a?.let { "$it " } ?: ""}$sell to $buy$on"
                }
                "trade.flash" -> {
                    val type = p["type"] ?: return null
                    val asset = p["asset"] ?: return null
                    val held = p["amount"]?.let { "$it " } ?: ""
                    val price = p["price"] ?: ""
                    when (type) {
                        "limit" -> {
                            val a = p["amount"]
                            when {
                                p["side"] == "sell" -> "sell $held$asset at $price$on"
                                p["usd"] == "true" && a != null -> "buy $$a of $asset at $price$on"
                                else -> "buy $held$asset at $price$on"
                            }
                        }
                        "stop" -> "buy $asset if it breaks $price$on"
                        "stop-loss" -> "stop loss $held$asset at $price$on"
                        "take-profit" -> "take profit $held$asset at $price$on"
                        "bracket" -> {
                            val stop = p["stopPrice"] ?: return null
                            "$held$asset tp $price sl $stop$on"
                        }
                        "trailing-stop" -> {
                            val trail = p["trailPercent"] ?: return null
                            "trail $held$asset by $trail%$on"
                        }
                        "twap" -> {
                            val a = p["amount"] ?: return null
                            val h = TradeIntent.number(p["hours"]) ?: return null
                            if (h < 1) return null
                            val span = if (h % 24 == 0.0) "${(h / 24).toInt()} days" else "${TradeIntent.rounded(h).toInt()} hours"
                            "buy $$a of $asset over $span$on"
                        }
                        else -> null
                    }
                }
                "trade.bridge" -> {
                    val a = p["amount"] ?: return null
                    val asset = p["asset"] ?: return null
                    val from = p["from"] ?: return null
                    val to = p["to"] ?: return null
                    "move $a $asset from $from to $to"
                }
                "near.swap" -> {
                    // Each side on its chain, as the server read it (a coin with no
                    // chain said sits at home, else on Base). No amount: the panel asks.
                    val sell = p["sell"] ?: return null
                    val buy = p["buy"] ?: return null
                    val from = p["sellChain"] ?: TradeIntent.nativeChain[sell.uppercase(Locale.US)] ?: "base"
                    val into = p["buyChain"] ?: TradeIntent.nativeChain[buy.uppercase(Locale.US)] ?: "base"
                    "swap ${p["amount"] ?: "1"} $sell on $from to $buy on $into"
                }
                "near.send" -> {
                    val a = p["amount"] ?: return null
                    val to = p["to"] ?: return null
                    var words = "send $a ${p["coin"] ?: "USDC"} to $to"
                    val with = p["with"]
                    if (with != null) words += " with $with" + (p["withChain"]?.let { " on $it" } ?: "")
                    else p["withChain"]?.let { words += " from $it" }
                    words
                }
                "near.earn" -> {
                    val coin = p["coin"] ?: "USDC"
                    if (p["out"] == "true") {
                        val what = p["amount"]?.let { "$it $coin" } ?: "my $coin"
                        "take $what out of earn" + (p["chain"]?.let { " to $it" } ?: "")
                    } else {
                        val a = p["amount"] ?: return null
                        "put $a $coin" + (p["chain"]?.let { " on $it" } ?: "") + " to work"
                    }
                }
                else -> null
            }
        }

    /** The trade the action opens, filled in. */
    val trade: TradeIntent?
        get() {
            if (tool == "trade.dca") {
                val every = TradeIntent.number(params["every"]) ?: return null
                val asset = TradeIntent.symbol(params["asset"]) ?: return null
                val period = params["period"]?.let { RecurringPlan.Period.of(it) } ?: return null
                return TradeIntent.recurringBuy(every, asset, TradeIntent.symbol(params["spend"]), period,
                    periods = params["periods"]?.toIntOrNull(), chain = params["chain"])
            }
            if (tool == "near.earn" && tradeWords == null) {
                // "put usdc to work": no amount said, so the panel asks for it.
                return TradeIntent.earn(params["coin"] ?: "USDC", null, false, params["chain"])
            }
            val t = tradeWords?.let { TradeIntent.parse(it) } ?: return null
            // A NEAR Intents tool opens NEAR Intents' panel, never Uniswap's.
            if (tool.startsWith("near.") && !t.isNear) return null
            if (tool == "near.swap" && params["amount"] == null) t.amount = null
            return t
        }

    /** The chip it shows as; null when this phone can't open it. */
    val chip: Smart.Chip?
        get() {
            if (tool.startsWith("trade.") || tool in setOf("near.swap", "near.send", "near.earn")) {
                return trade?.let { Smart.Chip.Trade(it) }
            }
            return when (tool) {
                "calendar.event" -> {
                    val title = params["title"] ?: return null
                    val whenSaid = params["when"] ?: return null
                    val plan = EventParse.parse("$title $whenSaid")
                    if (plan.hasDay || plan.hasTime) Smart.Chip.Event(plan) else null
                }
                "meet.link" -> Smart.Chip.Action("Add a Meet link", "", "meet")
                "search", "youtube", "shorts", "maps" -> {
                    val q = params["query"]?.takeIf { it.isNotEmpty() } ?: return null
                    Smart.Chip.Action(label, q, "open:$tool")
                }
                "translate" -> {
                    val to = params["to"]?.takeIf { it.isNotEmpty() } ?: return null
                    Smart.Chip.Action(label, to.take(1).uppercase(Locale.US) + to.drop(1).lowercase(Locale.US), "open:translate")
                }
                "rewrite" -> Smart.Chip.Action(label, "", "rewrite")
                "convert" -> Smart.Chip.Action(label, params["query"] ?: "", "answer")
                // A pay link to ask for, and the group pot: their panels read the
                // params back from the query (NearPay.kt).
                "near.request" -> {
                    PayAsk.of(params) ?: return null
                    Smart.Chip.Action(label, NearPay.chipQuery(params), "near:request")
                }
                "near.pot", "near.pot.pay" -> {
                    PotAsk.of(params, tool == "near.pot.pay") ?: return null
                    Smart.Chip.Action(label, NearPay.chipQuery(params), if (tool == "near.pot") "near:pot" else "near:pot.pay")
                }
                else -> null
            }
        }

    companion object {
        /** The server's `action` object; null for anything this phone can't open. */
        fun from(json: JSONObject): AIAction? {
            val tool = json.opt("tool") as? String ?: return null
            val label = json.opt("label") as? String ?: return null
            if (label.length > 80) return null
            val params = mutableMapOf<String, String>()
            json.optJSONObject("params")?.let { p ->
                for (k in p.keys()) {
                    when (val v = p.opt(k)) {
                        is String -> params[k] = v
                        is Boolean -> params[k] = if (v) "true" else "false"
                        is Number -> params[k] = TradeIntent.trimmed(v.toDouble())
                    }
                }
            }
            val a = AIAction(tool, label, params)
            return if (a.chip == null) null else a
        }
    }
}
