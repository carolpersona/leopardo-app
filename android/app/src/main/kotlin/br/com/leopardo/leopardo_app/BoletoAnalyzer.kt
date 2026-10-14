package br.com.leopardo.leopardo_app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import com.google.zxing.BarcodeFormat
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.MultiFormatReader
import com.google.zxing.RGBLuminanceSource
import com.google.zxing.Result
import com.google.zxing.common.HybridBinarizer
import com.google.zxing.multi.GenericMultipleBarcodeReader
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.text.PDFTextStripper
import com.tom_roush.pdfbox.text.TextPosition
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * Lê um boleto em PDF:
 *  - textos com posição na página (PDFBox), agrupados em trechos por linha;
 *  - código de barras ITF (44 dígitos) e QR Code (PIX) a partir da página renderizada
 *    (ZXing + um decodificador tolerante para PDFs de baixa resolução);
 *  - páginas sem texto (boleto em imagem): leitura por OCR (ML Kit, no aparelho).
 * A interpretação dos campos é feita no Dart (lib/services/boleto.dart).
 */
object BoletoAnalyzer {

    private class Token(
        val page: Int, val x: Float, val right: Float, val base: Float, val size: Float, val text: String
    )

    private class Collector : PDFTextStripper() {
        var page = 0
        val tokens = ArrayList<Token>()

        init {
            setSortByPosition(true)
        }

        override fun writeString(text: String?, textPositions: MutableList<TextPosition>?) {
            val ps = textPositions ?: return
            if (ps.isEmpty()) return
            val t = text?.trim() ?: return
            if (t.isEmpty()) return
            val first = ps.first()
            val last = ps.last()
            var size = first.fontSizeInPt
            if (size < 3f) size = first.heightDir * 1.4f
            if (size < 3f) size = 7f
            tokens.add(Token(page, first.xDirAdj, last.xDirAdj + last.widthDirAdj, first.yDirAdj, size, t))
        }
    }

    fun analyze(context: Context, path: String): Map<String, Any> {
        val file = File(path)
        val pages = ArrayList<Map<String, Any>>()
        val tokens = ArrayList<Token>()
        var textError: String? = null
        try {
            PDFBoxResourceLoader.init(context.applicationContext)
            PDDocument.load(file).use { doc ->
                val collector = Collector()
                val count = minOf(doc.numberOfPages, 30)
                for (i in 0 until count) {
                    val box = doc.getPage(i).mediaBox
                    pages.add(mapOf("width" to box.width.toDouble(), "height" to box.height.toDouble()))
                    collector.page = i
                    collector.setStartPage(i + 1)
                    collector.setEndPage(i + 1)
                    collector.getText(doc)
                }
                tokens.addAll(collector.tokens)
            }
        } catch (e: Exception) {
            textError = e.message ?: "erro ao ler o texto"
        }
        val pagesWithText = tokens.map { it.page }.toSet()
        val barcodes = ArrayList<Map<String, Any>>()
        val ocrTokens = ArrayList<Token>()
        try {
            scanPages(file, pagesWithText, barcodes, ocrTokens)
        } catch (e: Exception) {
        }
        val out = HashMap<String, Any>()
        out["segments"] = group(tokens + ocrTokens)
        out["barcodes"] = barcodes
        out["pages"] = pages
        out["ocr"] = ocrTokens.isNotEmpty()
        if (textError != null) out["textError"] = textError
        return out
    }

    /** Junta palavras da mesma linha que estão próximas (mesma célula do boleto). */
    private fun group(tokens: List<Token>): List<Map<String, Any>> {
        val out = ArrayList<Map<String, Any>>()
        for ((page, list) in tokens.groupBy { it.page }) {
            val sorted = list.sortedWith(compareBy<Token>({ it.base }, { it.x }))
            val lines = ArrayList<MutableList<Token>>()
            for (t in sorted) {
                val line = lines.lastOrNull()
                if (line != null && Math.abs(line[0].base - t.base) <= maxOf(1.5f, line[0].size * 0.3f)) {
                    line.add(t)
                } else {
                    lines.add(mutableListOf(t))
                }
            }
            for (line in lines) {
                line.sortBy { it.x }
                var cur = mutableListOf(line[0])
                for (i in 1 until line.size) {
                    val prev = cur.last()
                    val t = line[i]
                    val gap = t.x - prev.right
                    if (gap <= maxOf(prev.size, t.size) * 0.6f) {
                        cur.add(t)
                    } else {
                        out.add(segment(page, cur))
                        cur = mutableListOf(t)
                    }
                }
                out.add(segment(page, cur))
            }
        }
        return out
    }

    private fun segment(page: Int, ts: List<Token>): Map<String, Any> {
        val size = ts.maxOf { it.size }
        val x = ts.first().x
        val right = ts.maxOf { it.right }
        val base = ts.first().base
        return mapOf(
            "page" to page,
            "x" to x.toDouble(),
            "y" to (base - size * 0.8f).toDouble(),
            "w" to (right - x).toDouble(),
            "h" to size.toDouble(),
            "text" to ts.joinToString(" ") { it.text }
        )
    }

    /** Renderiza cada página uma vez e procura códigos de barras / faz OCR se não houver texto. */
    private fun scanPages(
        file: File,
        pagesWithText: Set<Int>,
        barcodes: MutableList<Map<String, Any>>,
        ocrTokens: MutableList<Token>
    ) {
        val fd = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
        fd.use {
            val renderer = PdfRenderer(fd)
            try {
                val hints = HashMap<DecodeHintType, Any>()
                hints[DecodeHintType.POSSIBLE_FORMATS] = listOf(BarcodeFormat.ITF, BarcodeFormat.QR_CODE)
                hints[DecodeHintType.TRY_HARDER] = true
                hints[DecodeHintType.ALLOWED_LENGTHS] = intArrayOf(44)
                for (i in 0 until minOf(renderer.pageCount, 30)) {
                    val page = renderer.openPage(i)
                    val scale = 2000f / page.width
                    val w = (page.width * scale).toInt()
                    val h = minOf((page.height * scale).toInt(), 6000)
                    val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
                    bmp.eraseColor(Color.WHITE)
                    val m = Matrix()
                    m.setScale(scale, scale)
                    try {
                        page.render(bmp, null, m, PdfRenderer.Page.RENDER_MODE_FOR_PRINT)
                    } finally {
                        page.close()
                    }
                    val px = IntArray(w * h)
                    bmp.getPixels(px, 0, w, 0, 0, w, h)

                    // 1) ZXing (ITF e QR Code)
                    val bin = BinaryBitmap(HybridBinarizer(RGBLuminanceSource(w, h, px)))
                    val results: Array<Result> = try {
                        GenericMultipleBarcodeReader(MultiFormatReader()).decodeMultiple(bin, hints)
                    } catch (e: Exception) {
                        emptyArray()
                    }
                    for (res in results) {
                        val ys = res.resultPoints?.filterNotNull()?.map { it.y } ?: emptyList()
                        val y = if (ys.isEmpty()) 0f else ys.average().toFloat()
                        barcodes.add(
                            mapOf(
                                "page" to i,
                                "format" to res.barcodeFormat.name,
                                "text" to (res.text ?: ""),
                                "y" to (y / scale).toDouble()
                            )
                        )
                    }

                    // 2) Decodificador tolerante (boletos em imagem de baixa resolução)
                    for ((code, y) in decodeI25(px, w, h)) {
                        barcodes.add(mapOf("page" to i, "format" to "ITF", "text" to code, "y" to (y / scale).toDouble()))
                    }

                    // 3) OCR quando a página não tem texto
                    if (!pagesWithText.contains(i)) {
                        try {
                            ocrTokens.addAll(ocr(bmp, i, scale))
                        } catch (e: Exception) {
                        }
                    }
                    bmp.recycle()
                }
            } finally {
                renderer.close()
            }
        }
    }

    private fun ocr(bmp: Bitmap, page: Int, scale: Float): List<Token> {
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        try {
            val result = Tasks.await(recognizer.process(InputImage.fromBitmap(bmp, 0)), 60, TimeUnit.SECONDS)
            val out = ArrayList<Token>()
            for (block in result.textBlocks) {
                for (line in block.lines) {
                    for (el in line.elements) {
                        val bb = el.boundingBox ?: continue
                        val size = bb.height() / scale * 1.2f
                        out.add(Token(page, bb.left / scale, bb.right / scale, bb.bottom / scale, size, el.text))
                    }
                }
            }
            return out
        } finally {
            recognizer.close()
        }
    }

    // ------------------------------------------------------------ Interleaved 2 of 5

    private val I25 = arrayOf("nnwwn", "wnnnw", "nwnnw", "wwnnn", "nnwnw", "wnwnn", "nwwnn", "nnnww", "wnnwn", "nwnwn")

    private fun lum(c: Int): Int =
        (((c shr 16) and 0xFF) * 299 + ((c shr 8) and 0xFF) * 587 + (c and 0xFF) * 114) / 1000

    /** Classifica 5 larguras: as 2 maiores são largas. */
    private fun digit(runs: IntArray, start: Int): Int {
        val idx = intArrayOf(0, 1, 2, 3, 4).sortedByDescending { runs[start + it * 2] }
        val sb = CharArray(5) { 'n' }
        sb[idx[0]] = 'w'
        sb[idx[1]] = 'w'
        return I25.indexOf(String(sb))
    }

    private fun barcodeDv(bc: String): Int {
        val base = bc.substring(0, 4) + bc.substring(5)
        var sum = 0
        var weight = 2
        for (i in base.length - 1 downTo 0) {
            sum += (base[i] - '0') * weight
            weight = if (weight == 9) 2 else weight + 1
        }
        val dv = 11 - sum % 11
        return if (dv == 0 || dv == 10 || dv == 11) 1 else dv
    }

    /** Varre linhas da imagem procurando o código de barras do boleto (44 dígitos, DV válido). */
    private fun decodeI25(px: IntArray, w: Int, h: Int): List<Pair<String, Float>> {
        val found = HashMap<String, MutableList<Int>>()
        val runs = IntArray(w + 1)
        val black = BooleanArray(w + 1)
        var y = 0
        while (y < h) {
            var n = 0
            var cur = lum(px[y * w]) < 140
            var len = 0
            for (x in 0 until w) {
                val b = lum(px[y * w + x]) < 140
                if (b == cur) {
                    len++
                } else {
                    black[n] = cur
                    runs[n] = len
                    n++
                    cur = b
                    len = 1
                }
            }
            black[n] = cur
            runs[n] = len
            n++
            var i = 1
            while (i + 226 < n) {
                if (black[i]) {
                    val narrow = (runs[i] + runs[i + 1] + runs[i + 2] + runs[i + 3]) / 4f
                    val okStart = runs[i - 1] >= narrow * 5 &&
                        (0..3).all { runs[i + it] <= narrow * 1.8f }
                    if (okStart) {
                        val sb = StringBuilder()
                        var ok = true
                        var g = i + 4
                        for (k in 0 until 22) {
                            val a = digit(runs, g)
                            val b = digit(runs, g + 1)
                            if (a < 0 || b < 0) {
                                ok = false
                                break
                            }
                            sb.append(a).append(b)
                            g += 10
                        }
                        val stopBar = runs[i + 224]
                        if (ok && stopBar > runs[i + 225] * 1.4f && stopBar > runs[i + 226] * 1.4f) {
                            val code = sb.toString()
                            if (code[0] != '8' && barcodeDv(code) == code[4] - '0') {
                                found.getOrPut(code) { mutableListOf() }.add(y)
                            }
                        }
                    }
                }
                i++
            }
            y += 3
        }
        return found.filter { it.value.size >= 2 }.map { Pair(it.key, it.value.average().toFloat()) }
    }
}
