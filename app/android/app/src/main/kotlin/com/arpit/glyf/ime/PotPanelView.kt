package com.arpit.glyf.ime

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.Locale
import java.util.concurrent.Executors

/**
 * The group pot over the keys (docs/NEAR-SPEC.md, Hand-off: the pot), the
 * twin of PotSurface.swift: a look at a Sputnik DAO's treasury (GET
 * /near/pot: its line, then the proposals still taking votes, each with
 * Vote), or a payout to propose for the members' vote (GET
 * /near/pot/propose-link), filed in Trezu, where the person signs in with
 * their own NEAR wallet. A payee given by name ("the caterer") is asked for
 * as a NEAR account, typed on the letter keys and checked on NEAR. Nothing
 * is signed here; Insert puts the answer's words in the chat.
 */
@SuppressLint("ViewConstructor", "SetTextI18n")
class PotPanelView(
    ctx: Context,
    private val palette: GlyfKeyboardView.KeyPalette,
    private val backendURL: String,
    private val ask: PotAsk,
    private val dao: String,
    /** The person's own NEAR account (shared settings `nearAccount`), for
     *  "Only members can propose from this pot". */
    private val nearAccount: String?,
    private val onInsert: (String) -> Unit,
    /** A proposal to vote on, or the payout to file, in Trezu. */
    private val onOpen: (String) -> Unit,
    /** The account is being typed (true): the letter keys come up under
     *  the panel's strip; false: back to the panel's own height. */
    private val onTyping: (Boolean) -> Unit = {},
) : FrameLayout(ctx), StripField {

    private val main = Handler(Looper.getMainLooper())
    private val blue = Color.rgb(0x0A, 0x84, 0xFF)
    private val red = Color.rgb(0xFF, 0x3B, 0x30)

    /** The payee's NEAR account: what was typed when it is one, else asked here. */
    private var account: String? = ask.to?.takeIf { PotAsk.isNEARAccount(it) }?.lowercase(Locale.US)
    private var accountProblem: String? = null
    private var checking = false
    private var view: PotView? = null
    private var proposal: PotProposal? = null
    private var loading = true
    private var editing = false
    private var typed = ""
    private var serial = 0

    /** The account's strip while it takes the keys (GlyfIME feeds it). */
    val typing: StripField? get() = if (editing) this else null

    override val stripText: String get() = typed
    override fun setStripText(text: String) { typed = text; render() }
    override fun endStrip() {
        if (!editing) return
        editing = false
        onTyping(false)
        check(typed)
    }

    private val body = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL }
    private val scroll = ScrollView(ctx).apply {
        isVerticalScrollBarEnabled = false
        overScrollMode = OVER_SCROLL_NEVER
        addView(body)
    }

    companion object {
        private val pool = Executors.newFixedThreadPool(2)
        private fun q(s: String) = URLEncoder.encode(s, "UTF-8")
    }

    /** The strip's name for the panel. */
    val title: String get() = if (ask.pay) "Pay from the pot" else "Group pot"

    /** "caterer", from "the caterer". */
    private val payeeWords: String
        get() = (ask.to ?: "").replace(Regex("""^the\s+""", RegexOption.IGNORE_CASE), "")

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()
    private fun soft(a: Int, c: Int) = Color.argb(a, Color.red(c), Color.green(c), Color.blue(c))

    init {
        setBackgroundColor(palette.board)
        addView(scroll, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        load()
    }

    // MARK: asking

    private fun load() {
        val n = ++serial
        loading = true
        render()
        if (!ask.pay) {
            http("/near/pot?dao=${q(dao)}") { ok, obj ->
                if (n != serial) return@http
                loading = false
                view = PotView.of(ok, obj)
                render()
            }
            return
        }
        // The payout waits for the account it pays.
        val to = account ?: run { loading = false; render(); return }
        var path = "/near/pot/propose-link?dao=${q(dao)}&to=${q(to)}&amount=${q(ask.amount ?: "")}&coin=${q(ask.coin)}"
        ask.note?.let { path += "&note=${q(it)}" }
        http(path) { ok, obj ->
            if (n != serial) return@http
            loading = false
            proposal = PotProposal.of(ok, obj, to, nearAccount)
            render()
        }
    }

    /** The typed account, checked on NEAR (GET /names/resolve) before the
     *  payout is asked for: "No NEAR account caterer.near". */
    private fun check(raw: String) {
        val name = raw.trim().lowercase(Locale.US)
        if (!PotAsk.isNEARAccount(name)) {
            accountProblem = if (name.isEmpty()) null else "Pay out to a NEAR account, like caterer.near"
            render()
            return
        }
        if (Regex("""^[0-9a-f]{64}$""").matches(name)) { account = name; accountProblem = null; load(); return }
        checking = true
        accountProblem = null
        render()
        val n = ++serial
        http("/names/resolve?name=${q(name)}") { ok, obj ->
            if (n != serial) return@http
            checking = false
            when {
                ok && obj?.optBoolean("exists", true) != false -> { account = name; load() }
                obj?.optBoolean("found", true) == false || obj?.optBoolean("exists", true) == false -> {
                    accountProblem = "No NEAR account $name"; render()
                }
                else -> { accountProblem = "Couldn't check $name on NEAR"; render() }
            }
        }
    }

    private fun beginAccount() {
        typed = account ?: ""
        editing = true
        onTyping(true)
        render()
    }

    // MARK: render

    private fun label(text: String, size: Float, bold: Boolean, color: Int, lines: Int = 1) = TextView(context).apply {
        this.text = text; textSize = size; setTextColor(color); maxLines = lines
        ellipsize = null
        if (bold) typeface = Typeface.DEFAULT_BOLD
    }

    private fun full(h: Int = LinearLayout.LayoutParams.WRAP_CONTENT, top: Int = 0) =
        LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, h).apply { topMargin = top }

    private fun cardBg() = GradientDrawable().apply { cornerRadius = dp(14).toFloat(); setColor(palette.card) }

    private fun button(text: String, on: Boolean, primary: Boolean, qa: String, onTap: () -> Unit) =
        label(text, 15f, true, if (!on) palette.inkSoft else if (primary) Color.WHITE else palette.ink).apply {
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                cornerRadius = dp(12).toFloat()
                setColor(if (on && primary) blue else soft(if (palette.darkChrome) 26 else 16, palette.ink))
            }
            setTag(com.arpit.glyf.R.id.qa_id, qa)
            if (on) setOnClickListener { onTap() }
        }

    private fun render() {
        body.removeAllViews()
        body.setPadding(dp(10), dp(6), dp(10), dp(8))
        if (editing) { renderAccountStrip(); return }
        if (ask.pay) renderPay() else renderLook()
    }

    /** The card: its headline, then a quieter line and a red one when there are. */
    private fun card(headline: String, detail: String? = null, warning: String? = null) {
        val c = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            background = cardBg()
            setPadding(dp(14), dp(10), dp(14), dp(10))
            setTag(com.arpit.glyf.R.id.qa_id, "pot:card")
        }
        c.addView(label(headline, 15f, true, palette.ink, lines = 4).apply { setTag(com.arpit.glyf.R.id.qa_id, "pot:text") })
        detail?.let { c.addView(label(it, 13f, false, palette.inkSoft, lines = 2).apply { setTag(com.arpit.glyf.R.id.qa_id, "pot:fill") }, full(top = dp(4))) }
        warning?.let { c.addView(label(it, 13f, true, red, lines = 2).apply { setTag(com.arpit.glyf.R.id.qa_id, "pot:warning") }, full(top = dp(4))) }
        body.addView(c, full(top = dp(2)))
    }

    private fun renderLook() {
        val v = view
        when {
            loading -> card("Reading the pot…")
            v?.error != null -> card(v.error ?: "")
            else -> card(v?.text ?: "", detail = if (v?.open.isNullOrEmpty()) "No proposals open" else null)
        }
        for (p in view?.open.orEmpty()) {
            val row = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                background = cardBg()
                minimumHeight = dp(44)
                setPadding(dp(12), dp(4), dp(10), dp(4))
                setTag(com.arpit.glyf.R.id.qa_id, "pot:proposal:${p.id}")
            }
            row.addView(label(p.line, 14f, false, palette.ink, lines = 2),
                LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            row.addView(label("Vote", 14f, true, blue).apply {
                gravity = Gravity.CENTER
                background = GradientDrawable().apply { cornerRadius = dp(14).toFloat(); setColor(soft(36, blue)) }
                setPadding(dp(14), 0, dp(14), 0)
                setTag(com.arpit.glyf.R.id.qa_id, "pot:vote:${p.id}")
                p.url?.let { url -> setOnClickListener { onOpen(url) } }
            }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, dp(28)).apply { leftMargin = dp(8) })
            body.addView(row, full(top = dp(5)))
        }
        val text = view?.text
        body.addView(button("Insert", text != null && !loading, true, "pot:go") { text?.let(onInsert) }, full(dp(42), dp(8)))
    }

    private fun renderPay() {
        val money = PotAsk.money(ask.amount ?: "", ask.coin)
        val needsAccount = ask.to?.let { !PotAsk.isNEARAccount(it) } ?: false
        val p = proposal
        when {
            account == null -> card("Propose $money to $payeeWords from the ${ask.potName}", warning = accountProblem)
            loading -> card("Asking the pot…")
            p == null || p.error != null -> card("Propose $money to ${account ?: ""}", warning = p?.error)
            else -> card(p.headline ?: "", detail = p.fill, warning = if (p.notMember) PotProposal.MEMBERS_ONLY else null)
        }
        if (needsAccount) {
            val row = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                background = cardBg()
                setPadding(dp(12), 0, dp(12), 0)
                setTag(com.arpit.glyf.R.id.qa_id, "pot:account")
                setOnClickListener { beginAccount() }
            }
            row.addView(label("$payeeWords's NEAR account", 14.5f, false, palette.inkSoft),
                LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            row.addView(label(if (checking) "Checking…" else account ?: "Add", 14.5f, true, blue))
            body.addView(row, full(dp(44), dp(6)))
        }
        val ready = p != null && p.error == null && !loading && account != null
        val line = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL }
        line.addView(button("Propose in Trezu", ready && p?.url != null && p.notMember != true, true, "pot:go") {
            p?.url?.let(onOpen)
        }, LinearLayout.LayoutParams(0, dp(42), 1f))
        line.addView(button("Insert", ready && p?.text != null, false, "pot:insert") { p?.text?.let(onInsert) },
            LinearLayout.LayoutParams(dp(96), dp(42)).apply { leftMargin = dp(8) })
        body.addView(line, full(top = dp(8)))
    }

    /** The account's strip over the letter keys: its name, the field and Done. */
    private fun renderAccountStrip() {
        body.setPadding(dp(10), dp(4), dp(10), dp(4))
        body.addView(label("$payeeWords's NEAR account", 12.5f, true, palette.inkSoft))
        val top = LinearLayout(context).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        top.addView(InlineField(context, "name.near").apply {
            show(typed)
            active = true
            setTag(com.arpit.glyf.R.id.qa_id, "pot:editor")
        }, LinearLayout.LayoutParams(0, dp(36), 1f))
        top.addView(label("Done", 14f, true, palette.board).apply {
            gravity = Gravity.CENTER
            background = GradientDrawable().apply { cornerRadius = dp(16).toFloat(); setColor(palette.ink) }
            setPadding(dp(16), 0, dp(16), 0)
            setTag(com.arpit.glyf.R.id.qa_id, "pot:done")
            setOnClickListener { endStrip() }
        }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, dp(32)).apply { leftMargin = dp(8) })
        body.addView(top, full(dp(40), dp(2)))
    }

    /** GET JSON from the server's pot routes, with the session; the object
     *  whatever the status, and whether it was a 2xx; on the main thread. */
    private fun http(path: String, done: (Boolean, JSONObject?) -> Unit) {
        pool.execute {
            var conn: HttpURLConnection? = null
            var ok = false
            val obj = try {
                conn = (URL(backendURL + path).openConnection() as HttpURLConnection).apply {
                    connectTimeout = 6000
                    readTimeout = 15000
                    BackendClient.session(this)
                }
                ok = conn.responseCode in 200..299
                val stream = if (ok) conn.inputStream else conn.errorStream
                stream?.bufferedReader()?.readText()?.let { JSONObject(it) }
            } catch (e: Exception) {
                android.util.Log.w("GlyfKB", "pot $path: $e")
                null
            } finally {
                conn?.disconnect()
            }
            main.post { if (isAttachedToWindow) done(ok, obj) }
        }
    }
}
