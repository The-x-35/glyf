package com.demo.glyf

import android.app.Activity
import android.content.Context
import android.os.CancellationSignal
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import androidx.credentials.ClearCredentialStateRequest
import androidx.credentials.CredentialManager
import androidx.credentials.CredentialManagerCallback
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.GetCredentialResponse
import androidx.credentials.exceptions.ClearCredentialException
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.exceptions.NoCredentialException
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import org.json.JSONObject
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Signing in on Android: Google through Credential Manager's Sign in with
 * Google sheet, asking for an ID token issued to the web client id from
 * Google Cloud Console. The Glyf server checks that token and issues its own
 * session. Results are the same dictionaries the iOS bridge returns:
 * `idToken` (with `name` and `email`) on success, `error` otherwise.
 */
object SignIn {

    fun google(activity: Activity, serverClientId: String, nonce: String,
               done: (Map<String, Any?>) -> Unit) {
        if (!serverClientId.endsWith(".apps.googleusercontent.com")) {
            done(mapOf("error" to "not_configured"))
            return
        }
        val option = GetSignInWithGoogleOption.Builder(serverClientId)
            .setNonce(nonce)
            .build()
        val request = GetCredentialRequest.Builder().addCredentialOption(option).build()
        CredentialManager.create(activity).getCredentialAsync(
            activity, request, CancellationSignal(), activity.mainExecutor,
            object : CredentialManagerCallback<GetCredentialResponse, GetCredentialException> {
                override fun onResult(result: GetCredentialResponse) {
                    val credential = result.credential
                    if (credential !is CustomCredential ||
                        credential.type != GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL) {
                        done(mapOf("error" to "failed"))
                        return
                    }
                    try {
                        val google = GoogleIdTokenCredential.createFrom(credential.data)
                        done(mapOf("idToken" to google.idToken, "name" to google.displayName,
                            "email" to google.id))
                    } catch (_: Exception) {
                        done(mapOf("error" to "failed"))
                    }
                }

                override fun onError(e: GetCredentialException) {
                    done(mapOf("error" to when (e) {
                        is GetCredentialCancellationException -> "cancelled"
                        is NoCredentialException -> "no_account"
                        else -> e.message ?: e.type
                    }))
                }
            })
    }

    /** Forgets which Google account was picked, so the next sign-in asks. */
    fun signOut(ctx: Context) {
        CredentialManager.create(ctx).clearCredentialStateAsync(
            ClearCredentialStateRequest(), null, ctx.mainExecutor,
            object : CredentialManagerCallback<Void?, ClearCredentialException> {
                override fun onResult(result: Void?) {}
                override fun onError(e: ClearCredentialException) {}
            })
    }
}

/**
 * The Glyf session: AES-GCM on disk (no backups), key in the Android
 * Keystore. The keyboard reads it too — the server wants a session on every
 * call — but only ever to read.
 */
object SessionStore {
    private const val KEY_ALIAS = "so.glyf.session"
    private const val FILE = "session.enc"

    private fun key(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        gen.init(
            KeyGenParameterSpec.Builder(KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build())
        return gen.generateKey()
    }

    private fun file(ctx: Context) = File(ctx.noBackupFilesDir, FILE)

    fun load(ctx: Context): String? = try {
        val raw = file(ctx).takeIf { it.exists() }?.readBytes()
        raw?.let {
            val c = Cipher.getInstance("AES/GCM/NoPadding")
            c.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, it.copyOfRange(0, 12)))
            String(c.doFinal(it.copyOfRange(12, it.size)))
        }
    } catch (_: Exception) {
        null
    }

    /** Just the bearer token, and only while it is still good. */
    fun token(ctx: Context): String? = try {
        val json = load(ctx)
        val obj = json?.let { JSONObject(it) }
        val token = obj?.optString("token").orEmpty()
        when {
            token.isEmpty() -> null
            expired(token) -> null
            else -> token
        }
    } catch (_: Exception) {
        null
    }

    /** The `exp` in the session's own claims; unreadable ones are left to the
     *  server to judge. */
    private fun expired(token: String): Boolean = try {
        val parts = token.split(".")
        if (parts.size != 3) false else {
            val payload = android.util.Base64.decode(
                parts[1], android.util.Base64.URL_SAFE or android.util.Base64.NO_PADDING or android.util.Base64.NO_WRAP)
            val exp = JSONObject(String(payload)).optLong("exp", 0L)
            exp > 0L && exp * 1000L <= System.currentTimeMillis()
        }
    } catch (_: Exception) {
        false
    }

    fun save(ctx: Context, json: String): Boolean = try {
        if (json.isEmpty()) {
            false
        } else {
            val c = Cipher.getInstance("AES/GCM/NoPadding")
            c.init(Cipher.ENCRYPT_MODE, key())
            file(ctx).writeBytes(c.iv + c.doFinal(json.toByteArray()))
            true
        }
    } catch (_: Exception) {
        false
    }

    fun clear(ctx: Context) {
        file(ctx).delete()
    }
}
