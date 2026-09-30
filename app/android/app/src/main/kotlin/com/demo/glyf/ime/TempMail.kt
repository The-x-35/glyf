package com.demo.glyf.ime

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.security.SecureRandom
import java.util.concurrent.Executors

/**
 * Temp mail in the keyboard (Arpit, 2026-09-30: "option to enter temporary
 * mail and we will monitor its mails for next some times and show the mails
 * gotten on it, so user can get temporary mails directly inside their
 * keyboards"), on mail.tm: free and keyless ("i said to fucking find free temp
 * mail apis"). Its terms forbid proxying its API under another domain, so the
 * phone calls it itself and mail never passes through Glyf's server. The
 * rules, and the cases both keyboards are held to, are shared/tempmail
 * (RULES.md, cases.json). Nothing here is ever logged: not an address, a
 * sender, a subject or a code. iOS twin: Engine/TempMail.swift.
 */

/** One mail, as read by the rules below (newest first). Kept in memory only. */
data class TempMail(
    val id: String,
    val from: String,
    val fromAddress: String,
    val subject: String,
    val text: String,
    val receivedAt: Long,
    val code: String?,
    val link: String?,
)

/** The address being watched: it survives the keyboard going away, so
 *  watching carries on in the next app. Never the mails themselves. */
data class TempBox(
    val address: String,
    /** 20 random characters, kept only on this phone: it takes a new token. */
    val password: String,
    val token: String,
    val accountId: String,
    val createdAt: Long,
    /** The watch window ends here; it began [TempMailRules.WATCH_MS] before. */
    val watchUntil: Long,
    /** When the first mail with a code came in this watch (0: none yet). */
    val codeAt: Long,
    /** Mails already told about, so each one's chip shows once. */
    val seen: Set<String>,
) {
    /** Glyf's own limit: an address lives a day. */
    val expiresAt get() = createdAt + TempMailRules.LIFE_MS
    val watchStart get() = watchUntil - TempMailRules.WATCH_MS
}

object TempMailStore {
    private fun prefs(ctx: Context) = ctx.getSharedPreferences("glyf_tempmail", Context.MODE_PRIVATE)

    fun load(ctx: Context): TempBox? {
        val p = prefs(ctx)
        val address = p.getString("address", null) ?: return null
        return TempBox(address, p.getString("password", "").orEmpty(), p.getString("token", "").orEmpty(),
            p.getString("accountId", "").orEmpty(), p.getLong("createdAt", 0), p.getLong("watchUntil", 0),
            p.getLong("codeAt", 0), p.getStringSet("seenIds", emptySet()).orEmpty().toSet())
    }

    fun save(ctx: Context, box: TempBox) {
        prefs(ctx).edit()
            .putString("address", box.address).putString("password", box.password)
            .putString("token", box.token).putString("accountId", box.accountId)
            .putLong("createdAt", box.createdAt).putLong("watchUntil", box.watchUntil)
            .putLong("codeAt", box.codeAt).putStringSet("seenIds", box.seen)
            .apply()
    }

    fun clear(ctx: Context) {
        prefs(ctx).edit().clear().apply()
    }
}

object TempMailRules {
    const val DEFAULT_BASE = "https://api.mail.tm"
    /** Glyf's own limit on an address: a day from its making. */
    const val LIFE_MS = 24 * 60 * 60 * 1000L
    /** A watch window: 15 minutes from Create, Insert or opening the panel. */
    const val WATCH_MS = 15 * 60 * 1000L
    /** Every 8 s for a window's first 3 minutes (and while the panel is
     *  open), then every 20 s: a code mostly comes at once. */
    const val FAST_MS = 8_000L
    const val SLOW_MS = 20_000L
    const val FAST_FOR_MS = 3 * 60 * 1000L
    /** A code has come: two more minutes of watching, then its job is done. */
    const val AFTER_CODE_MS = 2 * 60 * 1000L
    /** Three checks in a row turned away (429) or lost: a minute's rest. */
    const val FAILS_BEFORE_REST = 3
    const val REST_MS = 60_000L

    /** "now", "2m", "3h", "2d": how long ago, as the inbox shows it. */
    fun ago(at: Long, now: Long = System.currentTimeMillis()): String {
        val s = ((now - at) / 1000).coerceAtLeast(0)
        return when {
            s < 60 -> "now"
            s < 3600 -> "${s / 60}m"
            s < 86400 -> "${s / 3600}h"
            else -> "${s / 86400}d"
        }
    }

    // MARK: reading a mail (shared/tempmail/RULES.md)

    private val ENTITIES = mapOf("amp" to "&", "lt" to "<", "gt" to ">", "quot" to "\"", "apos" to "'",
        "nbsp" to " ", "#39" to "'")

    /** HTML as the text a person reads. */
    fun htmlToText(html: String): String {
        var t = html.replace(Regex("<(script|style|head)[\\s\\S]*?</\\1>", RegexOption.IGNORE_CASE), " ")
        t = t.replace(Regex("<br\\s*/?>|</(p|div|tr|li|h[1-6])>", RegexOption.IGNORE_CASE), "\n")
        t = t.replace(Regex("<[^>]+>"), " ")
        t = Regex("&(#\\d+|#x[0-9a-f]+|[a-z]+);", RegexOption.IGNORE_CASE).replace(t) { m ->
            val k = m.groupValues[1].lowercase()
            ENTITIES[k] ?: when {
                k.startsWith("#x") -> k.drop(2).toIntOrNull(16)?.let { String(Character.toChars(it)) }
                k.startsWith("#") -> k.drop(1).toIntOrNull()?.let { String(Character.toChars(it)) }
                else -> null
            } ?: m.value
        }
        t = t.replace(Regex("[ \\t\\f\\u000B\\u00A0]+"), " ")
        t = t.replace(Regex("\\s*\\n\\s*"), "\n")
        t = t.replace(Regex("\\n{3,}"), "\n\n")
        return t.trim()
    }

    /** The mail's text: its own when it has some, else its HTML read out. */
    fun text(text: String, html: List<String>): String =
        (if (text.isNotBlank()) text else htmlToText(html.joinToString("\n"))).trim().take(4000)

    private val CANDIDATE = Regex(
        "(?<![\\w\$€£₹.,/:-])((?:[A-Z]{1,3}-)?\\d{3}[ -]?\\d{3}|(?:[A-Z]{1,3}-)?\\d{4,8})(?![\\w%\$€£₹/:]|[.,]\\d)")
    private val CODE_WORDS = Regex(
        "\\b(codes?|otp|passcode|pass code|pin|verification|verify|security|confirmation|confirm|one[- ]time|log ?in|sign[- ]?in|2fa|two[- ]factor|token|password)\\b",
        RegexOption.IGNORE_CASE)
    private val NOT_A_CODE = Regex(
        "\\b(phone|call|tel|order|invoice|ref|reference|account (?:number|no\\.?|#)|zip|postal)\\b",
        RegexOption.IGNORE_CASE)
    private val PREFIX = Regex("^[A-Z]{1,3}-")

    /** A one-time code in a mail ("482913", "G-482913", "123 456"): a number
     *  that the subject holds or a code word stands near; never a year, a
     *  price, a phone number or an order number. */
    fun extractCode(subject: String, text: String): String? {
        val hay = "$subject\n$text".take(6000)
        var best: String? = null
        var bestScore = 0
        for (m in CANDIDATE.findAll(hay)) {
            val raw = m.groupValues[1]
            val prefixed = PREFIX.containsMatchIn(raw)
            val digits = raw.replace(PREFIX, "").replace(Regex("[ -]"), "")
            if (digits.length !in 4..8) continue
            // A year on its own is a date, not a code.
            if (digits.length == 4 && Regex("^(19|20)\\d\\d$").matches(digits) && !prefixed) continue
            val at = m.range.first
            var score = 0
            if (at < subject.length) score += 3
            if (CODE_WORDS.containsMatchIn(hay.substring(maxOf(0, at - 80), minOf(hay.length, at + raw.length + 40)))) score += 3
            score += if (digits.length == 6) 2 else 1
            if (prefixed) score += 1
            if (NOT_A_CODE.containsMatchIn(hay.substring(maxOf(0, at - 30), at))) score -= 4
            if (score >= 4 && (best == null || score > bestScore)) {
                best = if (prefixed) raw.replace(" ", "") else digits
                bestScore = score
            }
        }
        return best
    }

    private val LINK_WORDS = Regex(
        "(verif|confirm|activat|validat|magic|log-?in|sign-?in|signin|auth|reset|token|onboard|welcome|join|invite)",
        RegexOption.IGNORE_CASE)
    private val ANCHOR = Regex("<a\\b[^>]*?href\\s*=\\s*[\"'](https://[^\"']+)[\"'][^>]*>([\\s\\S]*?)</a>",
        RegexOption.IGNORE_CASE)
    private val URL_IN_TEXT = Regex("https://[^\\s<>\"']+")

    /** The link a mail asks to be opened (verify, confirm, sign in); never a
     *  logo or an unsubscribe link. */
    fun extractLink(text: String, html: String): String? {
        for (m in ANCHOR.findAll(html)) {
            val url = m.groupValues[1].replace("&amp;", "&")
            val words = m.groupValues[2].replace(Regex("<[^>]+>"), " ")
            if (LINK_WORDS.containsMatchIn(url) || LINK_WORDS.containsMatchIn(words)) return url
        }
        for (m in URL_IN_TEXT.findAll(text)) {
            val url = m.value.trimEnd('.', ',', ';')
            if (LINK_WORDS.containsMatchIn(url)) return url
        }
        return null
    }

    /** A mail.tm message (with its body, `GET /messages/{id}`) as the keyboard shows it. */
    fun mail(json: JSONObject): TempMail? {
        val id = json.optString("id").takeIf { it.isNotEmpty() } ?: return null
        val from = json.optJSONObject("from")
        val fromAddress = from?.optString("address").orEmpty()
        val subject = json.optString("subject").trim()
        val html = json.optJSONArray("html")?.let { a -> (0 until a.length()).map { a.optString(it) } } ?: emptyList()
        val raw = json.optString("text")
        val text = text(raw, html)
        val received = runCatching { java.time.Instant.parse(json.optString("createdAt")).toEpochMilli() }
            .getOrDefault(System.currentTimeMillis())
        return TempMail(id, from?.optString("name")?.trim()?.ifEmpty { null } ?: fromAddress, fromAddress,
            subject, text, received, extractCode(subject, text), extractLink(raw, html.joinToString("\n")))
    }
}

/** mail.tm, called by the phone (shared/tempmail/RULES.md). Every call runs
 *  on its own worker; [done] runs there too. */
object MailTm {

    private val pool = Executors.newSingleThreadExecutor()
    private val random = SecureRandom()
    /** An address's word (iOS draws from the same sixteen). */
    private val WORDS = listOf("amber", "maple", "cedar", "cobalt", "ember", "willow", "lunar", "harbor",
        "meadow", "orbit", "pebble", "river", "sable", "swift", "tidal", "quiet")

    /** What came back: the HTTP status (0: no answer) and the body. */
    class Reply(val status: Int, val body: String?) {
        val ok get() = status in 200..299
        fun json() = body?.let { runCatching { JSONObject(it) }.getOrNull() }
        /** A plain array, or JSON-LD's "hydra:member" if that is what came. */
        fun array(): JSONArray? = body?.trim()?.let { b ->
            if (b.startsWith("[")) runCatching { JSONArray(b) }.getOrNull()
            else runCatching { JSONObject(b).optJSONArray("hydra:member") }.getOrNull()
        }
    }

    private fun call(base: String, method: String, path: String, token: String? = null, body: JSONObject? = null): Reply = try {
        val c = (URL(base.trimEnd('/') + path).openConnection() as HttpURLConnection).apply {
            requestMethod = method
            connectTimeout = 6000
            readTimeout = 12000
            setRequestProperty("Accept", "application/json")
            token?.let { setRequestProperty("Authorization", "Bearer $it") }
            if (body != null) {
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
            }
        }
        body?.let { b -> c.outputStream.use { it.write(b.toString().toByteArray()) } }
        val status = c.responseCode
        val stream = if (status in 200..299) c.inputStream else c.errorStream
        Reply(status, stream?.bufferedReader()?.use { it.readText() })
    } catch (_: Exception) {
        Reply(0, null)
    }

    private fun hex(n: Int) = (1..n).joinToString("") { "0123456789abcdef"[random.nextInt(16)].toString() }
    private fun password() = (1..20).joinToString("") {
        "abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"[random.nextInt(56)].toString()
    }

    /** A new address: a domain, an account (another name when one is
     *  taken, up to three), and its token. [done] gets the box, or the
     *  status that stopped it (0: no answer) for [createNotice]. */
    fun create(base: String, done: (TempBox?, Int) -> Unit) = pool.execute {
        val domains = call(base, "GET", "/domains")
        val usable = domains.array()?.let { a -> (0 until a.length()).mapNotNull { a.optJSONObject(it) } }
            ?.filter { it.optBoolean("isActive", true) && !it.optBoolean("isPrivate", false) }
            ?.mapNotNull { it.optString("domain").takeIf { d -> d.isNotEmpty() } }.orEmpty()
        if (!domains.ok || usable.isEmpty()) return@execute done(null, domains.status)
        val domain = usable[random.nextInt(usable.size)]
        val pass = password()
        var made: JSONObject? = null
        var address = ""
        var last = 0
        for (attempt in 1..3) {
            address = WORDS[random.nextInt(WORDS.size)] + hex(6) + "@" + domain
            val r = call(base, "POST", "/accounts", body = JSONObject().put("address", address).put("password", pass))
            last = r.status
            if (r.ok) { made = r.json(); break }
            if (r.status != 422) break
        }
        val id = made?.optString("id").orEmpty()
        if (id.isEmpty()) return@execute done(null, last)
        val t = call(base, "POST", "/token", body = JSONObject().put("address", address).put("password", pass))
        val token = t.json()?.optString("token").orEmpty()
        if (!t.ok || token.isEmpty()) return@execute done(null, t.status)
        val now = System.currentTimeMillis()
        done(TempBox(address, pass, token, id, now, now + TempMailRules.WATCH_MS, 0L, emptySet()), 200)
    }

    /** What to say when mail.tm didn't make one. */
    fun createNotice(status: Int) = when (status) {
        0 -> "Couldn't reach temp mail. Check the connection"
        429 -> "Temp mail is busy. Try again in a minute"
        else -> "Temp mail didn't answer. Try again in a moment"
    }

    /** A fresh token for the stored address and password. */
    fun token(base: String, box: TempBox): Reply =
        call(base, "POST", "/token", body = JSONObject().put("address", box.address).put("password", box.password))

    /** A call with the box's token. A 401 takes a new token with the stored
     *  password and tries once more, so a 401 that comes back is the second
     *  one (the address is gone). The box returned carries the token used. */
    private fun authed(base: String, box: TempBox, method: String, path: String): Pair<Reply, TempBox> {
        val r = call(base, method, path, box.token)
        if (r.status != 401) return r to box
        val t = token(base, box)
        val fresh = t.json()?.optString("token").orEmpty()
        if (!t.ok || fresh.isEmpty()) return (if (t.ok) Reply(0, null) else t) to box
        return call(base, method, path, fresh) to box.copy(token = fresh)
    }

    /** Mails read in one look at most (mail.tm counts requests); the rest
     *  are read on the next. */
    private const val READS_PER_LOOK = 20

    /** The inbox (newest first), with the mails [known] doesn't have yet
     *  read once each. [done] gets the mails and 200; the mails read so far
     *  and the status of a read that was turned away or lost (the rest wait
     *  for the next look); or no mails and the status that stopped the list
     *  (401: the address is gone). The box carries the token it ended with. */
    fun check(base: String, box: TempBox, known: Map<String, TempMail>,
              done: (mails: List<TempMail>?, status: Int, box: TempBox) -> Unit) = pool.execute {
        var (list, b) = authed(base, box, "GET", "/messages?page=1")
        if (!list.ok) return@execute done(null, list.status, b)
        val items = list.array() ?: return@execute done(null, 0, b)
        val mails = mutableListOf<TempMail>()
        var status = 200
        var reads = 0
        for (i in 0 until items.length()) {
            val id = items.optJSONObject(i)?.optString("id").orEmpty()
            if (id.isEmpty()) continue
            val have = known[id]
            if (have != null) { mails.add(have); continue }
            if (status != 200 || reads >= READS_PER_LOOK) continue
            reads++
            val (one, used) = authed(base, b, "GET", "/messages/$id")
            b = used
            when {
                one.ok -> one.json()?.let { TempMailRules.mail(it) }?.let { mails.add(it) }
                one.status == 404 -> {}   // deleted since the list
                else -> status = one.status
            }
        }
        done(mails.sortedByDescending { it.receivedAt }, status, b)
    }

    fun delete(base: String, box: TempBox) = pool.execute {
        authed(base, box, "DELETE", "/accounts/${box.accountId}")
    }
}
