package com.demo.glyf

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * The wallet link's secrets: Phantom's session for Glyf and our half of the
 * encryption its deeplinks use. They can't move money (Phantom holds the
 * keys), but each sits sealed with a Keystore key, outside backups.
 */
object WalletSecrets {
    private const val KEY_ALIAS = "so.glyf.wallet"

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

    private fun file(ctx: Context, name: String): File {
        val dir = File(ctx.noBackupFilesDir, "wallet").apply { mkdirs() }
        return File(dir, name.filter { it.isLetterOrDigit() || it == '-' } + ".enc")
    }

    fun load(ctx: Context, name: String): String? = try {
        file(ctx, name).takeIf { it.exists() }?.readBytes()?.let {
            val c = Cipher.getInstance("AES/GCM/NoPadding")
            c.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, it.copyOfRange(0, 12)))
            String(c.doFinal(it.copyOfRange(12, it.size)))
        }
    } catch (_: Exception) {
        null
    }

    fun save(ctx: Context, name: String, value: String): Boolean = try {
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.ENCRYPT_MODE, key())
        file(ctx, name).writeBytes(c.iv + c.doFinal(value.toByteArray()))
        true
    } catch (_: Exception) {
        false
    }

    fun clear(ctx: Context, name: String) {
        file(ctx, name).delete()
    }
}
