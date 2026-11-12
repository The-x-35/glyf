package com.arpit.glyf.ime

import android.graphics.Color
import android.graphics.pdf.PdfDocument
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import java.io.File

/**
 * A long copied text as a PDF, made on the phone, for apps where a wall of
 * text reads badly (Arpit, 2026-11-07: "if we copied a really big text can
 * we ... convert it to pdf file ... and paste that"). The twin of
 * TextPDF.swift: US Letter pages, 0.75 inch margins, the system font at
 * 11 pt, as many pages as the text needs. Android lets a keyboard hand a
 * file to a field that takes PDFs (commitContent); anywhere else it goes on
 * the clipboard and the person pastes it, the way stickers and GIFs do.
 */
object TextPDF {
    /** Copies this long offer the PDF button. */
    const val MIN_LENGTH = 1_000

    const val PAGE_W = 612
    const val PAGE_H = 792
    const val MARGIN = 54

    fun offers(text: String): Boolean {
        val t = text.trim()
        return t.codePointCount(0, t.length) >= MIN_LENGTH
    }

    /** The document's title: its first line, short. */
    fun title(text: String): String {
        val first = text.split('\n', '\r').firstOrNull { it.isNotBlank() } ?: text
        val t = first.trim()
        return if (t.length > 60) t.take(57) + "…" else t
    }

    /** A file name from the title: letters, digits and dashes, "Glyf" when none. */
    fun fileName(text: String): String {
        val slug = title(text).removeSuffix("…").lowercase()
            .replace(Regex("[^a-z0-9]+"), "-").trim('-').take(40).trim('-')
        return (slug.ifEmpty { "glyf" }) + ".pdf"
    }

    /** Where each page starts, as line indexes, for lines of [lineBottoms]
     *  (each line's bottom from the top of the text) on pages [pageHeight]
     *  tall: a line goes on the next page when it would cross the bottom. */
    fun pageStarts(lineBottoms: List<Int>, pageHeight: Int): List<Int> {
        if (lineBottoms.isEmpty()) return listOf(0)
        val starts = mutableListOf(0)
        var top = 0
        for ((i, bottom) in lineBottoms.withIndex()) {
            if (bottom - top > pageHeight && i > starts.last()) {
                starts.add(i)
                top = if (i > 0) lineBottoms[i - 1] else 0
            }
        }
        return starts
    }

    /** Writes [text] as a PDF to [file]. */
    fun write(text: String, file: File) {
        val box = PAGE_W - 2 * MARGIN
        val boxH = PAGE_H - 2 * MARGIN
        val paint = TextPaint(TextPaint.ANTI_ALIAS_FLAG).apply { textSize = 11f; color = Color.BLACK }
        val layout = StaticLayout.Builder.obtain(text, 0, text.length, paint, box)
            .setAlignment(Layout.Alignment.ALIGN_NORMAL)
            .setLineSpacing(2f, 1f)
            .build()
        val bottoms = (0 until layout.lineCount).map { layout.getLineBottom(it) }
        val starts = pageStarts(bottoms, boxH)
        val doc = PdfDocument()
        try {
            for ((n, first) in starts.withIndex()) {
                val page = doc.startPage(PdfDocument.PageInfo.Builder(PAGE_W, PAGE_H, n + 1).create())
                val c = page.canvas
                val top = layout.getLineTop(first)
                val end = if (n + 1 < starts.size) layout.getLineTop(starts[n + 1]) else layout.height
                c.save()
                c.translate(MARGIN.toFloat(), (MARGIN - top).toFloat())
                c.clipRect(0, top, box, end)
                layout.draw(c)
                c.restore()
                doc.finishPage(page)
            }
            file.outputStream().use { doc.writeTo(it) }
        } finally {
            doc.close()
        }
    }
}
