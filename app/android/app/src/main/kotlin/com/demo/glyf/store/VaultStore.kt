package com.demo.glyf.store

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import org.json.JSONArray
import org.json.JSONObject
import java.security.KeyStore
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * §6.7 vault, Android edition: AES-GCM blob on disk, key in the Android
 * Keystore (hardware-backed where available) — the mirror of iOS's App
 * Group blob + shared-Keychain key. Same JSON schema as the Swift store.
 */
object VaultStore {
    private const val KEY_ALIAS = "so.glyf.vault"
    private const val BLOB = "vault.enc"

    private fun key(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val gen = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        gen.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build())
        return gen.generateKey()
    }

    private fun empty() = JSONObject(mapOf(
        "fields" to JSONArray(), "combos" to JSONArray(), "snippets" to JSONArray()))

    fun load(ctx: Context): JSONObject = read(ctx, forEdit = false) ?: empty()

    /** The vault; empty when there is none yet. Null when there is one that
     *  could not be read just now (the Keystore or the disk failing for a
     *  moment): an edit then stops, since saving over it would replace
     *  everything saved with nothing. A blob this phone's key can never open
     *  (restored from another phone, or damaged) is set aside for an edit,
     *  so details can be saved again. */
    private fun read(ctx: Context, forEdit: Boolean = true): JSONObject? {
        val f = Bridge.file(ctx, BLOB)
        if (!f.exists() || f.length() == 0L) return empty()
        var unopenable = false
        val vault = try {
            val raw = f.readBytes()
            if (raw.size < 12 + 16) {
                unopenable = true // shorter than its IV and tag
                null
            } else {
                val c = Cipher.getInstance("AES/GCM/NoPadding")
                c.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, raw.copyOfRange(0, 12)))
                JSONObject(String(c.doFinal(raw.copyOfRange(12, raw.size))))
            }
        } catch (_: javax.crypto.BadPaddingException) {
            unopenable = true // the tag fails: another key's blob, or damaged
            null
        } catch (_: Exception) { null }
        if (vault != null) {
            // An older blob may miss a list; the edits below need all three.
            for (list in listOf("fields", "combos", "snippets")) {
                if (vault.optJSONArray(list) == null) vault.put(list, JSONArray())
            }
            return vault
        }
        if (unopenable && forEdit) {
            f.renameTo(java.io.File(f.parentFile, "$BLOB.unreadable"))
            return empty()
        }
        return null
    }

    /** Written whole beside the old blob, then swapped in, so a crash or a
     *  full disk mid-write never leaves half a vault. */
    private fun save(ctx: Context, vault: JSONObject): Boolean = try {
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.ENCRYPT_MODE, key())
        val out = c.iv + c.doFinal(vault.toString().toByteArray())
        val f = Bridge.file(ctx, BLOB)
        val tmp = java.io.File(f.parentFile, "$BLOB.tmp")
        tmp.writeBytes(out)
        tmp.renameTo(f)
    } catch (_: Exception) { false }

    /** The kinds iOS's VaultRules allows (plus "handle", which older builds
     *  saved), so a detail saved on one phone is savable on the other. */
    private val allowedKinds = setOf(
        "name", "email", "phone", "address", "upi", "gst", "wallet",
        "link", "social", "bio", "reply", "custom", "handle")

    fun upsertField(ctx: Context, id: String?, kind: String,
                    label: String, value: String): String? {
        if (label.isBlank()) return "Give it a label"
        if (value.isBlank()) return "Add the value"
        if (kind !in allowedKinds) return "That kind of info can't be stored"
        SecretScanner.scan(value)?.let { return it }
        val vault = read(ctx) ?: return "Couldn't save"
        val fields = vault.getJSONArray("fields")
        var found = false
        for (i in 0 until fields.length()) {
            val f = fields.getJSONObject(i)
            if (f.optString("id") == id) {
                f.put("kind", kind); f.put("label", label); f.put("value", value)
                found = true
            }
        }
        if (!found) fields.put(JSONObject(mapOf(
            "id" to UUID.randomUUID().toString().lowercase(),
            "kind" to kind, "label" to label, "value" to value)))
        return if (save(ctx, vault)) null else "Couldn't save"
    }

    /** A detail added from the keyboard. The same value saved twice is kept
     *  once: a second tap on Save left two cards that said the same thing
     *  (VaultStore.swift addField twin). */
    fun addField(ctx: Context, kind: String, label: String, value: String): String? {
        val v = value.trim()
        val fields = read(ctx)?.optJSONArray("fields")
        if (fields != null && (0 until fields.length()).any {
                val f = fields.getJSONObject(it)
                f.optString("kind") == kind && f.optString("value") == v
            }) return null
        return upsertField(ctx, null, kind, label, v)
    }

    fun deleteField(ctx: Context, id: String) {
        val vault = read(ctx) ?: return
        vault.put("fields", filterOut(vault.getJSONArray("fields"), id))
        save(ctx, vault)
    }

    fun upsertCombo(ctx: Context, id: String?, label: String,
                    fieldIds: List<String>): String? {
        if (label.isBlank()) return "Give it a label"
        if (fieldIds.isEmpty()) return "Pick at least one field"
        val vault = read(ctx) ?: return "Couldn't save"
        val combos = vault.getJSONArray("combos")
        var found = false
        for (i in 0 until combos.length()) {
            val c = combos.getJSONObject(i)
            if (c.optString("id") == id) {
                c.put("label", label); c.put("fieldIds", JSONArray(fieldIds))
                found = true
            }
        }
        if (!found) combos.put(JSONObject(mapOf(
            "id" to (id ?: UUID.randomUUID().toString().lowercase()),
            "label" to label, "fieldIds" to JSONArray(fieldIds))))
        return if (save(ctx, vault)) null else "Couldn't save"
    }

    fun deleteCombo(ctx: Context, id: String) {
        val vault = read(ctx) ?: return
        vault.put("combos", filterOut(vault.getJSONArray("combos"), id))
        save(ctx, vault)
    }

    /** Why a shortcut can't be one, or null when it can: the keyboard asks
     *  before the expansion is typed, not after. */
    fun triggerRefusal(trigger: String): String? =
        if (Regex("^;[a-z0-9]{2,12}$").matches(trigger)) null
        else "Triggers look like ;sig (a ; plus 2–12 letters)"

    fun upsertSnippet(ctx: Context, trigger: String, text: String): String? {
        triggerRefusal(trigger)?.let { return it }
        if (text.isBlank()) return "Add the expansion"
        SecretScanner.scan(text)?.let { return it }
        val vault = read(ctx) ?: return "Couldn't save"
        val snippets = vault.getJSONArray("snippets")
        var found = false
        for (i in 0 until snippets.length()) {
            val s = snippets.getJSONObject(i)
            if (s.optString("trigger") == trigger) { s.put("text", text); found = true }
        }
        if (!found) snippets.put(JSONObject(mapOf("trigger" to trigger, "text" to text)))
        return if (save(ctx, vault)) null else "Couldn't save"
    }

    fun deleteSnippet(ctx: Context, trigger: String) {
        val vault = read(ctx) ?: return
        val kept = JSONArray()
        val snippets = vault.getJSONArray("snippets")
        for (i in 0 until snippets.length()) {
            val s = snippets.getJSONObject(i)
            if (s.optString("trigger") != trigger) kept.put(s)
        }
        vault.put("snippets", kept)
        save(ctx, vault)
    }

    private fun filterOut(arr: JSONArray, id: String): JSONArray {
        val kept = JSONArray()
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            if (o.optString("id") != id) kept.put(o)
        }
        return kept
    }
}
