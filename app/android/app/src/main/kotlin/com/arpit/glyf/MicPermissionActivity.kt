package com.arpit.glyf

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.os.SystemClock
import android.provider.Settings

/**
 * Asks for the microphone for the keyboard's voice typing (Arpit,
 * 2026-10-06: "the mic should work inside keyboard"). A keyboard can't show
 * the dialog itself, so this asks over the app being typed in, with nothing
 * of its own on screen, and goes; the keyboard, back over that app, starts
 * listening at once ([takeFreshGrant]). Only this ask opens anything:
 * voice typing itself runs in the keyboard.
 */
class MicPermissionActivity : Activity() {

    private var askedAt = 0L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (granted(this)) { finish(); return }
        // Turned round mid-dialog: the answer still comes here.
        if (savedInstanceState != null) return
        askedAt = SystemClock.elapsedRealtime()
        requestPermissions(arrayOf(android.Manifest.permission.RECORD_AUDIO), REQUEST)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        val ok = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        if (ok) grantedAt = SystemClock.elapsedRealtime()
        // Said no for good before: Android answers at once with no dialog, so
        // the app's page in Settings, where the microphone can be allowed.
        if (!ok && askedAt > 0 && SystemClock.elapsedRealtime() - askedAt < 400 &&
            !shouldShowRequestPermissionRationale(android.Manifest.permission.RECORD_AUDIO)) {
            runCatching {
                startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.fromParts("package", packageName, null)))
            }
        }
        finish()
    }

    companion object {
        private const val REQUEST = 75
        private var lastAsk = 0L
        /** When the microphone was allowed here: the keyboard, back over the
         *  app, starts listening at once (the tap that asked meant that). */
        @Volatile private var grantedAt = 0L

        /** Allowed in the last 20 seconds, once: the keyboard listens. */
        fun takeFreshGrant(): Boolean {
            val at = grantedAt
            grantedAt = 0L
            return at > 0 && SystemClock.elapsedRealtime() - at < 20_000
        }

        fun granted(ctx: Context): Boolean =
            ctx.checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) ==
                PackageManager.PERMISSION_GRANTED

        /** From the keyboard: a second tap while the first ask opens is the same ask. */
        fun ask(ctx: Context) {
            val now = SystemClock.elapsedRealtime()
            if (now - lastAsk < 1500) return
            lastAsk = now
            ctx.startActivity(Intent(ctx, MicPermissionActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_ANIMATION))
        }
    }
}
