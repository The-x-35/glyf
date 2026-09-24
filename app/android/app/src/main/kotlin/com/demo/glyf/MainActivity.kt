package com.demo.glyf

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var bridge: GlyfBridge? = null
    private var pendingPermission: ((Boolean) -> Unit)? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val b = GlyfBridge(applicationContext)
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, "so.glyf/bridge")
        channel.setMethodCallHandler(b)
        b.channel = channel
        b.requestContactsPermission = { done ->
            pendingPermission = done
            requestPermissions(arrayOf(android.Manifest.permission.READ_CONTACTS), 71)
        }
        b.requestLocationPermission = { done ->
            pendingPermission = done
            requestPermissions(
                arrayOf(android.Manifest.permission.ACCESS_COARSE_LOCATION), 72)
        }
        b.requestCalendarPermission = { done ->
            pendingPermission = done
            // Reading shows the day; writing adds events from the keyboard.
            // One calendar dialog answers both.
            requestPermissions(arrayOf(android.Manifest.permission.READ_CALENDAR,
                android.Manifest.permission.WRITE_CALENDAR), 74)
        }
        b.requestImagesPermission = { done ->
            pendingPermission = done
            requestPermissions(arrayOf(ScreenshotAccess.permission), 73)
        }
        b.activity = this
        bridge = b
        if (BuildConfig.DEBUG) {
            b.launchArgs = intent?.getStringArrayExtra("glyfArgs")?.toList() ?: emptyList()
            // UI-test hook, as on iOS: onboarding starts over.
            if ("--glyf-reset-onboarding" in b.launchArgs) {
                com.demo.glyf.store.Bridge.file(this, "onboarding.json").delete()
            }
        }
        intent?.dataString?.let { link ->
            if (link.startsWith("glyf://")) b.lastDeepLink = link
        }
    }

    override fun onDestroy() {
        bridge?.activity = null
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode in 71..74) {
            val ok = grantResults.firstOrNull() ==
                android.content.pm.PackageManager.PERMISSION_GRANTED
            pendingPermission?.invoke(ok)
            pendingPermission = null
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val link = intent.dataString ?: return
        if (link.startsWith("glyf://")) {
            bridge?.lastDeepLink = link
            bridge?.channel?.invokeMethod("onDeepLink", link)
        }
    }
}
