package br.com.leopardo.leopardo_app

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import java.io.ByteArrayOutputStream
import java.io.File

/**
 * Converte o PDF gerado pelo sistema de impressão do Android em comandos
 * ESC/POS de imagem (GS v 0), na largura da bobina.
 */
object ThermalRaster {

    /** Gera os bytes ESC/POS de todas as páginas do PDF. */
    fun pdfToEscPos(pdf: File, paperDots: Int, isCancelled: () -> Boolean): ByteArray {
        val out = ByteArrayOutputStream()
        out.write(byteArrayOf(0x1B, 0x40)) // ESC @
        val fd = ParcelFileDescriptor.open(pdf, ParcelFileDescriptor.MODE_READ_ONLY)
        fd.use {
            val renderer = PdfRenderer(fd)
            try {
                for (i in 0 until renderer.pageCount) {
                    if (isCancelled()) throw InterruptedException("Impressão cancelada")
                    val page = renderer.openPage(i)
                    val bmp = try {
                        renderPage(page, paperDots)
                    } finally {
                        page.close()
                    }
                    val mono = toMono(bmp, paperDots)
                    bmp.recycle()
                    if (mono != null) {
                        writeRaster(out, mono.first, mono.second, paperDots)
                        out.write(byteArrayOf(0x1B, 0x64, 4)) // ESC d 4: avança papel
                    }
                }
            } finally {
                renderer.close()
            }
        }
        return out.toByteArray()
    }

    /** Renderiza em 2x a largura do papel para recortar margens com boa qualidade. */
    private fun renderPage(page: PdfRenderer.Page, paperDots: Int): Bitmap {
        val w = paperDots * 2
        val scale = w.toFloat() / page.width.toFloat()
        val h = minOf((page.height * scale).toInt().coerceAtLeast(1), 10000)
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        bmp.eraseColor(Color.WHITE)
        val m = Matrix()
        m.setScale(scale, scale)
        page.render(bmp, null, m, PdfRenderer.Page.RENDER_MODE_FOR_PRINT)
        return bmp
    }

    private fun lum(c: Int): Int =
        (Color.red(c) * 299 + Color.green(c) * 587 + Color.blue(c) * 114) / 1000

    /**
     * Recorta as margens em branco, ajusta à largura do papel e converte para 1 bit.
     * Retorna (bits, altura) ou null se a página estiver em branco.
     */
    private fun toMono(src: Bitmap, paperDots: Int): Pair<ByteArray, Int>? {
        val w = src.width
        val h = src.height
        val px = IntArray(w * h)
        src.getPixels(px, 0, w, 0, 0, w, h)
        var minX = w; var minY = h; var maxX = -1; var maxY = -1
        for (y in 0 until h) {
            val row = y * w
            for (x in 0 until w) {
                if (lum(px[row + x]) < 235) {
                    if (x < minX) minX = x
                    if (x > maxX) maxX = x
                    if (y < minY) minY = y
                    if (y > maxY) maxY = y
                }
            }
        }
        if (maxX < 0) return null
        val pad = 8
        val crop = Rect(
            maxOf(0, minX - pad), maxOf(0, minY - pad),
            minOf(w, maxX + 1 + pad), minOf(h, maxY + 1 + pad)
        )

        val outH = maxOf(1, (crop.height().toFloat() * paperDots / crop.width()).toInt())
        val scaled = Bitmap.createBitmap(paperDots, outH, Bitmap.Config.ARGB_8888)
        scaled.eraseColor(Color.WHITE)
        val canvas = Canvas(scaled)
        val paint = Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG)
        canvas.drawBitmap(src, crop, Rect(0, 0, paperDots, outH), paint)

        val sp = IntArray(paperDots * outH)
        scaled.getPixels(sp, 0, paperDots, 0, 0, paperDots, outH)
        scaled.recycle()

        val l = FloatArray(sp.size)
        var mid = 0
        for (i in sp.indices) {
            val v = lum(sp[i])
            l[i] = v.toFloat()
            if (v in 60..200) mid++
        }
        // Muitos tons de cinza = foto: usa pontilhado. Senão, limiar (texto nítido).
        val dither = mid > sp.size * 0.15

        val bpr = paperDots / 8
        val bits = ByteArray(bpr * outH)
        for (y in 0 until outH) {
            for (x in 0 until paperDots) {
                val i = y * paperDots + x
                val old = l[i]
                val black = if (dither) old < 128f else old < 150f
                if (black) {
                    val bi = y * bpr + (x shr 3)
                    bits[bi] = (bits[bi].toInt() or (0x80 shr (x and 7))).toByte()
                }
                if (dither) {
                    val err = old - (if (black) 0f else 255f)
                    if (x + 1 < paperDots) l[i + 1] += err * 7f / 16f
                    if (y + 1 < outH) {
                        if (x > 0) l[i + paperDots - 1] += err * 3f / 16f
                        l[i + paperDots] += err * 5f / 16f
                        if (x + 1 < paperDots) l[i + paperDots + 1] += err * 1f / 16f
                    }
                }
            }
        }
        return Pair(bits, outH)
    }

    private fun writeRaster(out: ByteArrayOutputStream, bits: ByteArray, height: Int, paperDots: Int) {
        val bpr = paperDots / 8
        val band = 96
        var y = 0
        while (y < height) {
            val h = minOf(band, height - y)
            out.write(
                byteArrayOf(
                    0x1D, 0x76, 0x30, 0x00,
                    (bpr and 0xFF).toByte(), ((bpr shr 8) and 0xFF).toByte(),
                    (h and 0xFF).toByte(), ((h shr 8) and 0xFF).toByte()
                )
            )
            out.write(bits, y * bpr, h * bpr)
            y += h
        }
    }
}
