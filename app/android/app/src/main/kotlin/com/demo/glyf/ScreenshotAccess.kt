package com.demo.glyf

import android.content.ContentUris
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.MediaStore

/**
 * Recent screenshots for the keyboard's clipboard, the way Gboard keeps them:
 * only when the person turned it on, only screenshots, only the last hour.
 */
object ScreenshotAccess {
    val permission: String
        get() = if (Build.VERSION.SDK_INT >= 33) android.Manifest.permission.READ_MEDIA_IMAGES
                else android.Manifest.permission.READ_EXTERNAL_STORAGE

    fun granted(ctx: Context): Boolean =
        ctx.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    data class Shot(val uri: Uri, val takenMs: Long)

    /** Newest first, taken within the last two days — the same window a copy
     *  keeps for, since a screenshot from yesterday is exactly what people
     *  come to the clipboard looking for. Matches iOS's ClipboardPanel. */
    fun recent(ctx: Context, limit: Int = 6, maxAgeSeconds: Long = 48 * 3600): List<Shot> {
        if (!granted(ctx)) return emptyList()
        val since = System.currentTimeMillis() / 1000 - maxAgeSeconds
        val out = mutableListOf<Shot>()
        val projection = arrayOf(MediaStore.Images.Media._ID, MediaStore.Images.Media.DATE_ADDED)
        val selection = "${MediaStore.Images.Media.DATE_ADDED} >= ? AND (" +
            "${MediaStore.Images.Media.RELATIVE_PATH} LIKE ? OR " +
            "${MediaStore.Images.Media.BUCKET_DISPLAY_NAME} = ?)"
        val args = arrayOf(since.toString(), "%Screenshots%", "Screenshots")
        runCatching {
            ctx.contentResolver.query(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, projection,
                selection, args, "${MediaStore.Images.Media.DATE_ADDED} DESC")?.use { c ->
                val idCol = c.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
                val addedCol = c.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_ADDED)
                while (c.moveToNext() && out.size < limit) {
                    out.add(Shot(ContentUris.withAppendedId(
                        MediaStore.Images.Media.EXTERNAL_CONTENT_URI, c.getLong(idCol)),
                        c.getLong(addedCol) * 1000))
                }
            }
        }
        return out
    }
}
