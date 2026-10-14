package br.com.leopardo.leopardo_app

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.os.Build
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.text.TextUtils
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

/**
 * Versão nativa do layout "Boleto 80 mm deitado" (lib/services/boleto_renderer.dart).
 * Recibo do pagador + ficha de compensação girados 90°, código de barras I2of5
 * no tamanho oficial. Manter igual à versão em Dart.
 */
class BoletoDraw private constructor(private val c: Canvas, private val h: Float) {
    private val k = h / 576f

    companion object {
        private const val REC_LEN = 500f
        private const val GAP = 36f
        private const val FICHA_LEN = 1320f
        private const val MARGIN = 10f
        private val I25 = arrayOf("nnwwn", "wnnnw", "nwnnw", "wwnnn", "nnwnw", "wnwnn", "nwwnn", "nnnww", "wnnwn", "nwnwn")
        private val MEDIUM: Typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
        private val BOLD: Typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)

        fun totalLength() = MARGIN + REC_LEN + GAP + FICHA_LEN + MARGIN

        /** Bitmap na orientação da impressão: largura = papel, altura = comprimento. */
        fun render(d: Map<String, String>, paperDots: Int): Bitmap {
            val len = totalLength().toInt() + 1
            val bmp = Bitmap.createBitmap(paperDots, len, Bitmap.Config.ARGB_8888)
            bmp.eraseColor(Color.WHITE)
            val canvas = Canvas(bmp)
            canvas.translate(paperDots.toFloat(), 0f)
            canvas.rotate(90f)
            val r = BoletoDraw(canvas, paperDots.toFloat())
            r.recibo(d, MARGIN)
            r.cutLine(MARGIN + REC_LEN + GAP / 2)
            r.ficha(d, MARGIN + REC_LEN + GAP)
            return bmp
        }
    }

    private fun v(d: Map<String, String>, key: String) = d[key] ?: ""

    // ------------------------------------------------------------- helpers

    private fun stroke(width: Float = 1.5f) = Paint().apply {
        color = Color.BLACK
        style = Paint.Style.STROKE
        strokeWidth = max(1f, width * k)
        isAntiAlias = false
    }

    private fun rect(x: Float, y: Float, w: Float, hh: Float) = c.drawRect(x, y, x + w, y + hh, stroke())

    private fun hline(x1: Float, x2: Float, y: Float, width: Float = 1.5f) = c.drawLine(x1, y, x2, y, stroke(width))

    private fun vline(x: Float, y1: Float, y2: Float, width: Float = 1.5f) = c.drawLine(x, y1, x, y2, stroke(width))

    @Suppress("DEPRECATION")
    private fun text(
        s: String, x: Float, y: Float, maxW: Float,
        size: Float = 16f, bold: Boolean = false, align: Layout.Alignment = Layout.Alignment.ALIGN_NORMAL,
        maxLines: Int = 1
    ) {
        if (s.isEmpty() || maxW <= 4f) return
        val tp = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.BLACK
            textSize = size * k
            typeface = if (bold) BOLD else MEDIUM
        }
        val w = maxW.toInt()
        val layout = if (Build.VERSION.SDK_INT >= 23) {
            StaticLayout.Builder.obtain(s, 0, s.length, tp, w)
                .setAlignment(align)
                .setIncludePad(false)
                .setMaxLines(maxLines)
                .setEllipsize(TextUtils.TruncateAt.END)
                .build()
        } else {
            StaticLayout(s, tp, w, align, 1f, 0f, false)
        }
        val lines = min(maxLines, layout.lineCount)
        c.save()
        c.translate(x, y)
        c.clipRect(0f, 0f, maxW, layout.getLineBottom(lines - 1).toFloat())
        layout.draw(c)
        c.restore()
    }

    private fun cell(
        label: String, value: String, x: Float, y: Float, w: Float, hh: Float,
        align: Layout.Alignment = Layout.Alignment.ALIGN_NORMAL, bold: Boolean = false,
        size: Float = 20f, maxLines: Int = 1
    ) {
        rect(x, y, w, hh)
        text(label, x + 4, y + 2 * k, w - 8, size = 13.5f)
        text(value, x + 4, y + 16.5f * k, w - 8, size = size, bold = bold, align = align, maxLines = maxLines)
    }

    private fun header(d: Map<String, String>, ox: Float, len: Float, top: Float, hh: Float, right: String, rightSize: Float) {
        val nameW = 210f
        val codeW = 110f
        text(v(d, "bancoNome"), ox + 2, top + (hh - 32 * k) / 2, nameW - 6, size = 28f, bold = true)
        vline(ox + nameW, top + 4 * k, top + hh, 3f)
        text(v(d, "banco"), ox + nameW, top + (hh - 37 * k) / 2, codeW, size = 32f, bold = true,
            align = Layout.Alignment.ALIGN_CENTER)
        vline(ox + nameW + codeW, top + 4 * k, top + hh, 3f)
        text(right, ox + nameW + codeW + 8, top + (hh - rightSize * 1.15f * k) / 2, len - nameW - codeW - 12,
            size = rightSize, bold = true, align = Layout.Alignment.ALIGN_OPPOSITE)
        hline(ox, ox + len, top + hh, 3f)
    }

    private fun cutLine(x: Float) {
        val p = Paint().apply {
            color = Color.BLACK
            strokeWidth = 2f
            isAntiAlias = false
        }
        var y = 0f
        while (y < h) {
            c.drawLine(x, y, x, min(y + 7, h), p)
            y += 14
        }
    }

    private fun qr(data: String, x: Float, y: Float, size: Float) {
        val hints = mapOf(EncodeHintType.MARGIN to 0, EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.M)
        val m = try {
            QRCodeWriter().encode(data, BarcodeFormat.QR_CODE, 0, 0, hints)
        } catch (e: Exception) {
            return
        }
        val n = m.width
        val cell = floor(size / (n + 2))
        if (cell < 2) return
        val p = Paint().apply {
            color = Color.BLACK
            isAntiAlias = false
        }
        val ox = floor(x) + cell
        val oy = floor(y) + cell
        for (r in 0 until n) {
            for (col in 0 until n) {
                if (m.get(col, r)) c.drawRect(ox + col * cell, oy + r * cell, ox + (col + 1) * cell, oy + (r + 1) * cell, p)
            }
        }
    }

    /** Interleaved 2 of 5: barra fina 2 pontos, larga 6 pontos. */
    private fun i25(digits: String, x: Float, y: Float, hh: Float) {
        val narrow = 2f
        val wide = 6f
        val p = Paint().apply {
            color = Color.BLACK
            isAntiAlias = false
        }
        var cx = floor(x)
        val top = floor(y)
        val height = floor(hh)
        fun bar(w: Float) {
            c.drawRect(cx, top, cx + w, top + height, p)
            cx += w
        }
        fun space(w: Float) {
            cx += w
        }
        bar(narrow); space(narrow); bar(narrow); space(narrow)
        var i = 0
        while (i + 1 < digits.length) {
            val a = I25[digits[i] - '0']
            val b = I25[digits[i + 1] - '0']
            for (j in 0 until 5) {
                bar(if (a[j] == 'w') wide else narrow)
                space(if (b[j] == 'w') wide else narrow)
            }
            i += 2
        }
        bar(wide); space(narrow); bar(narrow)
    }

    // ------------------------------------------------------------- partes

    private val right = Layout.Alignment.ALIGN_OPPOSITE

    private fun recibo(d: Map<String, String>, ox: Float) {
        val len = REC_LEN
        val top = 6 * k
        val hh = 46 * k
        header(d, ox, len, top, hh, "Recibo do Pagador", 17f)
        val gy = top + hh
        val rh = 38 * k
        val leftW = 290f
        val rightW = len - leftW

        cell("Beneficiário", v(d, "beneficiario"), ox, gy, leftW, rh * 2, size = 17f, maxLines = 3)
        cell("Nº do Documento", v(d, "numeroDocumento"), ox, gy + rh * 2, leftW, rh)
        cell("Agência / Código Beneficiário", v(d, "agenciaCodigo"), ox, gy + rh * 3, leftW, rh)
        cell("Nosso Número", v(d, "nossoNumero"), ox, gy + rh * 4, leftW, rh)

        val rx = ox + leftW
        cell("Vencimento", v(d, "vencimento"), rx, gy, rightW, rh, align = right, bold = true, size = 21f)
        cell("(=) Valor do Documento", v(d, "valor"), rx, gy + rh, rightW, rh, align = right, bold = true, size = 21f)
        cell("(-) Desconto / Abatimento", "", rx, gy + rh * 2, rightW, rh)
        cell("(+) Mora / Multa / Juros", "", rx, gy + rh * 3, rightW, rh)
        cell("(=) Valor Cobrado", "", rx, gy + rh * 4, rightW, rh)

        val py = gy + rh * 5
        cell("Pagador", v(d, "pagador"), ox, py, len, rh * 2, size = 17f, maxLines = 3)

        val y = py + rh * 2 + 6 * k
        val bottom = h - 20 * k
        val pix = v(d, "pix")
        if (pix.isNotEmpty()) {
            val q = min(bottom - y, 250 * k)
            qr(pix, ox, y, q)
            val tx = ox + q + 10
            text("Pague com PIX", tx, y + 14 * k, len - q - 14, size = 24f, bold = true)
            text("Abra o app do seu banco e aponte a câmera para o QR Code.", tx, y + 48 * k, len - q - 14,
                size = 16f, maxLines = 5)
        } else {
            text("Linha digitável", ox + 2, y, len - 4, size = 13.5f)
            text(v(d, "linha"), ox + 2, y + 17 * k, len - 4, size = 20f, bold = true, maxLines = 3)
        }
        text("Autenticação mecânica - Recibo do Pagador", ox, h - 19 * k, len, size = 13f, align = right)
    }

    private fun ficha(d: Map<String, String>, ox: Float) {
        val len = FICHA_LEN
        val top = 6 * k
        val hh = 46 * k
        header(d, ox, len, top, hh, v(d, "linha"), 24f)

        val gy = top + hh
        val rh = 38 * k
        val rightW = 300f
        val leftW = len - rightW
        val rx = ox + leftW

        val rightCol = listOf(
            "Vencimento" to v(d, "vencimento"),
            "Agência / Código do Beneficiário" to v(d, "agenciaCodigo"),
            "Nosso Número" to v(d, "nossoNumero"),
            "(=) Valor do Documento" to v(d, "valor"),
            "(-) Desconto / Abatimento" to "",
            "(-) Outras Deduções" to "",
            "(+) Mora / Multa / Juros" to "",
            "(+) Outros Acréscimos" to "",
            "(=) Valor Cobrado" to ""
        )
        for ((i, pair) in rightCol.withIndex()) {
            val strong = i == 0 || i == 3
            cell(pair.first, pair.second, rx, gy + rh * i, rightW, rh, align = right, bold = strong,
                size = if (strong) 21f else 20f)
        }

        val local = v(d, "localPagamento").ifEmpty { "Pagável em qualquer banco até o vencimento" }
        cell("Local de Pagamento", local, ox, gy, leftW, rh, size = 18f)
        cell("Beneficiário", v(d, "beneficiario").replace("\n", "  ·  "), ox, gy + rh, leftW, rh * 2,
            size = 18f, maxLines = 3)

        val frac = floatArrayOf(0.2f, 0.25f, 0.16f, 0.11f, 0.28f)
        fun row(y: Float, cells: List<Pair<String, String>>) {
            var x = ox
            for ((i, p) in cells.withIndex()) {
                val w = leftW * frac[i]
                cell(p.first, p.second, x, y, w, rh, size = 19f)
                x += w
            }
        }
        row(gy + rh * 3, listOf(
            "Data do Documento" to v(d, "dataDocumento"),
            "Nº do Documento" to v(d, "numeroDocumento"),
            "Espécie Doc." to v(d, "especieDoc"),
            "Aceite" to v(d, "aceite"),
            "Data Processamento" to v(d, "dataProcessamento")
        ))
        row(gy + rh * 4, listOf(
            "Uso do Banco" to "",
            "Carteira" to v(d, "carteira"),
            "Espécie" to "R$",
            "Quantidade" to "",
            "(x) Valor" to ""
        ))

        val iy = gy + rh * 5
        val ih = rh * 4
        rect(ox, iy, leftW, ih)
        text("Instruções (texto de responsabilidade do beneficiário)", ox + 4, iy + 2 * k, leftW - 8, size = 13.5f)
        text(v(d, "instrucoes"), ox + 4, iy + 18 * k, leftW - 8, size = 16f, maxLines = 7)

        val py = gy + rh * 9
        val ph = 62 * k
        rect(ox, py, len, ph)
        text("Pagador", ox + 4, py + 2 * k, 160f, size = 13.5f)
        var pagador = v(d, "pagador").replace("\n", "  ·  ")
        if (v(d, "sacador").isNotEmpty()) pagador = "$pagador  ·  Sacador/Avalista: ${v(d, "sacador")}"
        text(pagador, ox + 4, py + 17 * k, len - 8, size = 18f, maxLines = 2)

        val bc = BoletoModel.barcodeFromLinha(v(d, "linha"))
        val by = py + ph + 8 * k
        val bh = min(104 * k, h - by - 4 * k)
        val bx = 40f
        val barcodeLen = 810f
        if (bc != null && bh > 20) {
            i25(bc, ox + bx, by, bh)
        } else {
            text("Linha digitável inválida.", ox + bx, by + 10 * k, len - 80, size = 20f, bold = true)
        }
        val ax = ox + bx + barcodeLen + 30
        text("Autenticação mecânica\nFicha de Compensação", ax, by + bh / 2 - 16 * k, ox + len - ax,
            size = 14f, align = right, maxLines = 2)
    }
}
