package com.demo.glyf.ime

/**
 * The website's coach (site/components/chat/scenarios.ts) on the Android
 * keyboard, the twin of TourCoach.swift. The app's tour says which chat and
 * step it is on; this reads what the keyboard is showing and names the one
 * thing to tap next, in the website's words. Null means nothing to point
 * at: the friend is typing, the app is pointing (a bubble, Send), or the
 * keyboard is busy. Pure logic, unit tested in TourCoachTest.
 */
object TourCoach {

    /** [target] is a qa id; a trailing "*" takes the topmost visible match. */
    data class Coach(val target: String, val label: String)

    sealed class SearchView {
        data class Landing(val rows: Int) : SearchView()
        object Typing : SearchView()
        object Loading : SearchView()
        data class Results(val count: Int) : SearchView()
    }

    sealed class Panel {
        object None : Panel()
        /** [tab] is the strip's tab id: "web", "yt" or "maps". */
        data class Search(val tab: String, val view: SearchView, val query: String) : Panel()
        object Vault : Panel()
        /** The g menu's own grid of tools. */
        object Menu : Panel()
        data class Act(val working: Boolean, val options: Boolean) : Panel()
        data class Translate(val ready: Boolean, val target: String?) : Panel()
        /** Anything else that is open, and the control that closes it. */
        data class Other(val close: String) : Panel()
    }

    data class State(
        val step: String,
        val text: String,
        val panel: Panel = Panel.None,
        /** "calc", "vault:<kind>", "pay", "paste", "action", "event", "booking", "fill" or null. */
        val chip: String? = null,
        val suggestions: List<String> = emptyList(),
        val fields: List<Smart.Field> = emptyList(),
        /** Letters holding the vault and translate, if any. */
        val vaultKey: String? = null,
        val translateKey: String? = null,
        /** Tools showing on the strip right now (people can move them). */
        val stripTools: Set<String> = setOf("search", "vault", "translate"),
        /** The tour copied the address from the chat, so a paste chip holds it. */
        val copied: Boolean = false,
    )

    /** While a step is being coached the strip only offers what that step is
     *  about: any other chip would cover the tool the coach points at. */
    fun allowsChip(kind: String, step: String, copied: Boolean = false): Boolean = when (step) {
        "mom:0" -> kind == "vault:address"
        "semi:0" -> kind == "pay" || (kind == "paste" && copied)
        "zoya:0" -> kind == "calc"
        "zoya:1" -> kind == "vault:wallet"
        else -> false
    }

    /** Opens a tool: from the strip when it is there, else through the g
     *  menu, which holds only what the strip doesn't (so a tool on the strip
     *  is pointed at there even while the menu is open). */
    private fun tool(s: State, id: String, label: String): Coach = when {
        id in s.stripTools -> Coach(id, label)
        s.panel == Panel.Menu -> Coach("shell:tile:$id", label)
        else -> Coach("toolbar:glyf", "Tap g")
    }

    private fun has(s: String, part: String) = part.isNotEmpty() && s.contains(part, ignoreCase = true)
    private fun matches(s: String, pattern: String) =
        Regex(pattern, RegexOption.IGNORE_CASE).containsMatchIn(s)

    /** The search tab a step is about. */
    fun searchTab(step: String): String? = when (step) {
        "sakshi:0" -> "maps"
        "kabir:0" -> "yt"
        "kabir:1" -> "web"
        else -> null
    }

    /** What the keyboard types into search for you, per step. */
    fun searchQuery(step: String): String? = when (step) {
        "sakshi:0" -> "coffee near me"
        "kabir:0" -> "road trip songs"
        "kabir:1" -> "sunset time today"
        else -> null
    }

    /** What the keyboard types into the field for you, given what is open. */
    fun autotype(s: State): String? =
        if (s.step == "sofia:0" && s.panel is Panel.Translate && s.text.isEmpty()) "see you tomorrow" else null

    /** The website's "absolutely / sure thing" check, for a real model's
     *  rewrite: anything that is no longer the messy draft. */
    fun polished(t: String): Boolean {
        val s = t.trim().lowercase()
        return s.isNotEmpty() && s != "ya ill send it by 6 dont worry" && !s.contains("dont worry")
    }

    fun coach(s: State): Coach? {
        val text = s.text
        return when (s.step) {
            "sakshi:0" -> search(s, "maps", "Maps") { it.contains("📍") }

            "mom:0" -> vault(s, "address")

            "semi:0" -> when {
                text.startsWith("💸") -> null
                s.panel is Panel.Other -> Coach(s.panel.close, "Close")
                s.panel != Panel.None -> null
                // A copied address is the paste, with Send beside it.
                s.chip == "pay" -> Coach("strip:smart:extra|strip:smart", "Send")
                s.chip == "paste" && s.copied -> Coach("strip:smart", "Paste")
                else -> null // the chat points at the address to copy
            }

            "neha:0" -> when (val p = s.panel) {
                is Panel.Act -> if (!p.working && p.options) Coach("act:option:work", "Professional") else null
                Panel.None -> {
                    val t = text.trim()
                    if (t.isEmpty() || polished(t)) null else Coach("key:space", "Hold glyf")
                }
                else -> closer(p)
            }

            "zoya:0" -> when {
                text.contains("59") -> null
                s.panel != Panel.None -> closer(s.panel)
                s.chip == "calc" -> Coach("strip:smart", "Tap")
                text.isEmpty() -> null
                else -> Coach("key:delete", "Delete")
            }

            "zoya:1" -> {
                val wallet = s.fields.firstOrNull { it.kind == "wallet" }
                when {
                    wallet != null && has(text, wallet.value) -> null
                    s.panel == Panel.Vault && wallet != null ->
                        Coach("vault:card:${s.fields.indexOf(wallet)}", "Tap ${wallet.label}")
                    s.panel != Panel.None -> closer(s.panel)
                    s.chip == "vault:wallet" -> Coach("strip:smart", "Tap")
                    text.isEmpty() || matches(text, "wallet address is\\s*$") -> null
                    else -> Coach("key:delete", "Delete")
                }
            }

            "kabir:0" -> search(s, "yt", "YouTube") { it.contains("youtu") || it.contains("🎥") || it.contains("▶") }

            "kabir:1" -> search(s, "web", "Google") { matches(it, "\\d{1,2}:\\d{2}") }

            "sofia:0" -> {
                val p = s.panel
                when {
                    has(text, "mañana") -> null
                    p is Panel.Translate -> when {
                        p.ready -> Coach("hud:replace", "Replace")
                        p.target != null && p.target != "Spanish" && matches(text, "^\\s*see you tomorrow\\s*$") ->
                            Coach("hud:direction", "Spanish")
                        text.isEmpty() || matches(text, "^\\s*see you tomorrow\\s*$") -> null
                        else -> Coach("key:delete", "Delete")
                    }
                    s.translateKey != null && p == Panel.None ->
                        Coach("key:${s.translateKey}", "Hold ${s.translateKey.uppercase()}")
                    p != Panel.None && p != Panel.Menu -> closer(p)
                    else -> tool(s, "translate", "Translate")
                }
            }

            else -> null
        }
    }

    private fun closer(panel: Panel): Coach? = when (panel) {
        Panel.None -> null
        is Panel.Search -> Coach("search:close", "Close")
        Panel.Vault -> Coach("panel:back", "Close")
        Panel.Menu -> Coach("toolbar:glyf", "Close")
        is Panel.Act -> Coach(if (panel.working) "act:cancel" else "act:close", "Close")
        is Panel.Translate -> Coach("hud:close", "Close")
        is Panel.Other -> Coach(panel.close, "Close")
    }

    private fun search(s: State, tab: String, label: String, done: (String) -> Boolean): Coach? {
        if (done(s.text)) return null
        val p = s.panel
        if (p !is Panel.Search) {
            if (p != Panel.None && p != Panel.Menu) return closer(p)
            return tool(s, "search", "Search")
        }
        if (p.tab != tab) return Coach("search:tab:$tab", label)
        return when (val v = p.view) {
            is SearchView.Results -> if (v.count > 0) Coach("search:card:*", "Tap to share") else null
            SearchView.Loading -> null
            else -> if (p.query.isNotBlank()) Coach("search:go", "Search") else null
        }
    }

    private fun vault(s: State, kind: String): Coach? {
        val field = s.fields.firstOrNull { it.kind == kind }
        return when {
            field != null && has(s.text, field.value) -> null
            s.panel == Panel.Vault ->
                field?.let { Coach("vault:card:${s.fields.indexOf(it)}", "Tap ${it.label}") }
            s.chip == "vault:$kind" -> Coach("strip:smart", "Tap")
            field == null -> if (s.panel == Panel.None) null else closer(s.panel)
            s.vaultKey != null && s.panel == Panel.None -> Coach("key:${s.vaultKey}", "Hold ${s.vaultKey.uppercase()}")
            s.panel != Panel.None && s.panel != Panel.Menu -> closer(s.panel)
            else -> tool(s, "vault", "Vault")
        }
    }
}
