package br.com.leopardo.leopardo_app

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

/**
 * DANFE Simplificado para bobina (58 ou 80 mm), a partir dos dados lidos por [DanfeModel].
 *
 * Regras seguidas (Ajuste SINIEF 07/05, cl. 9ª, e NT 2020.004 v1.10):
 *  - largura mínima de 55 mm; caracteres com no mínimo 6 pontos (aqui ≥ 19 pontos de impressão ≈ 6,7 pt);
 *  - títulos dos campos em negrito e em maiúsculas;
 *  - chave de acesso e código de barras CODE-128C no alto da via;
 *  - Etiqueta: emitente (nome, UF, CNPJ, IE), tipo de operação, série, número, emissão,
 *    destinatário (nome, UF, CNPJ/CPF, IE), protocolo de autorização e, opcionalmente, o valor total.
 * O modo completo acrescenta itens, totais, transporte e informações complementares.
 */
class DanfeDraw private constructor(private val c: Canvas?, private val w: Int) {

    companion object {
        private const val M = 8f // margem lateral
        private const val S_LABEL = 19f
        private const val S_TEXT = 21f
        private const val S_VALUE = 23f
        private const val S_BIG = 28f
        private const val S_TITLE = 31f

        private val REGULAR: Typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.NORMAL)
        private val BOLD: Typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)

        /**
         * @param etiqueta  true = "DANFE Simplificado - Etiqueta" (sem itens)
         * @param valorTotal mostra o valor total na etiqueta (pode ser suprimido, NT 2020.004 v1.10)
         */
        fun render(d: Map<String, Any?>, paperDots: Int, etiqueta: Boolean, valorTotal: Boolean = true): Bitmap {
            val measure = DanfeDraw(null, paperDots)
            measure.draw(d, etiqueta, valorTotal)
            val h = max(100, measure.y.toInt() + 8)
            val bmp = Bitmap.createBitmap(paperDots, h, Bitmap.Config.ARGB_8888)
            bmp.eraseColor(Color.WHITE)
            DanfeDraw(Canvas(bmp), paperDots).draw(d, etiqueta, valorTotal)
            return bmp
        }

        // ------------------------------------------------------------- Code 128

        private val C128 = arrayOf(
            "212222", "222122", "222221", "121223", "121322", "131222", "122213", "122312", "132212", "221213",
            "221312", "231212", "112232", "122132", "122231", "113222", "123122", "123221", "223211", "221132",
            "221231", "213212", "223112", "312131", "311222", "321122", "321221", "312212", "322112", "322211",
            "212123", "212321", "232121", "111323", "131123", "131321", "112313", "132113", "132311", "211313",
            "231113", "231311", "112133", "112331", "132131", "113123", "113321", "133121", "313121", "211331",
            "231131", "213113", "213311", "213131", "311123", "311321", "331121", "312113", "312311", "332111",
            "314111", "221411", "431111", "111224", "111422", "121124", "121421", "141122", "141221", "112214",
            "112412", "122114", "122411", "142112", "142211", "241211", "221114", "413111", "241112", "134111",
            "111242", "121142", "121241", "114212", "124112", "124211", "411212", "421112", "421211", "212141",
            "214121", "412121", "111143", "111341", "131141", "114113", "114311", "411113", "411311", "113141",
            "114131", "311141", "411131", "211412", "211214", "211232"
        )
        private const val STOP = "2331112"

        /**
         * Códigos (valores 0..106) para o texto: conjunto C nos trechos numéricos
         * (a chave numérica fica 100% em CODE-128C) e B nos caracteres alfanuméricos.
         */
        fun code128(text: String): List<Int> {
            val codes = ArrayList<Int>()
            var i = 0
            var set = ' '
            fun digitsAt(p: Int): Int {
                var n = 0
                while (p + n < text.length && text[p + n].isDigit()) n++
                return n
            }
            while (i < text.length) {
                val run = digitsAt(i)
                val useC = run >= 4 || (run >= 2 && (i == 0 && run == text.length)) || (set == 'C' && run >= 2)
                if (useC) {
                    if (set != 'C') {
                        codes.add(if (codes.isEmpty()) 105 else 99); set = 'C'
                    }
                    var n = run - run % 2
                    while (n > 0) {
                        codes.add((text[i] - '0') * 10 + (text[i + 1] - '0'))
                        i += 2; n -= 2
                    }
                } else {
                    if (set != 'B') {
                        codes.add(if (codes.isEmpty()) 104 else 100); set = 'B'
                    }
                    codes.add(text[i].code - 32)
                    i++
                }
            }
            var sum = codes[0]
            for (k in 1 until codes.size) sum += codes[k] * k
            codes.add(sum % 103)
            return codes
        }

        /** Larguras em módulos (barra, espaço, barra...) incluindo o stop. */
        fun code128Widths(text: String): List<Int> {
            val out = ArrayList<Int>()
            for (code in code128(text)) C128[code].forEach { out.add(it - '0') }
            STOP.forEach { out.add(it - '0') }
            return out
        }
    }

    var y = 0f
        private set

    private fun paint(size: Float, bold: Boolean) = Paint().apply {
        color = Color.BLACK
        textSize = size
        typeface = if (bold) BOLD else REGULAR
        isAntiAlias = true
    }

    private val fill = Paint().apply {
        color = Color.BLACK
        style = Paint.Style.FILL
        isAntiAlias = false
    }

    private val inner get() = w - 2 * M

    // ------------------------------------------------------------- texto

    /** Quebra o texto em linhas que cabem em [maxW]. */
    private fun wrap(text: String, p: Paint, maxW: Float): List<String> {
        val out = ArrayList<String>()
        for (para in text.split('\n')) {
            var line = ""
            for (word0 in para.split(' ').filter { it.isNotEmpty() }) {
                var word = word0
                val tryLine = if (line.isEmpty()) word else "$line $word"
                if (p.measureText(tryLine) <= maxW) {
                    line = tryLine
                    continue
                }
                if (line.isNotEmpty()) out.add(line)
                // palavra maior que a linha: quebra por caracteres
                while (p.measureText(word) > maxW && word.length > 1) {
                    var n = word.length - 1
                    while (n > 1 && p.measureText(word.substring(0, n)) > maxW) n--
                    out.add(word.substring(0, n))
                    word = word.substring(n)
                }
                line = word
            }
            if (line.isNotEmpty()) out.add(line)
        }
        return out
    }

    private fun lineH(size: Float) = floor(size * 1.22f)

    private enum class Al { L, C, R }

    private fun text(s: String, size: Float, bold: Boolean = false, al: Al = Al.L, x0: Float = M, maxW: Float = inner) {
        if (s.isBlank()) return
        val p = paint(size, bold)
        for (l in wrap(s.trim(), p, maxW)) {
            val tw = p.measureText(l)
            val x = when (al) {
                Al.L -> x0
                Al.C -> x0 + (maxW - tw) / 2
                Al.R -> x0 + maxW - tw
            }
            c?.drawText(l, x, y + size * 0.93f, p)
            y += lineH(size)
        }
    }

    private fun gap(h: Float) {
        y += h
    }

    private fun rule(thick: Float = 2f) {
        gap(5f)
        c?.drawRect(M, y, w - M, y + thick, fill)
        y += thick
        gap(7f)
    }

    private fun dashed() {
        gap(5f)
        var x = M
        while (x < w - M) {
            c?.drawRect(x, y, min(x + 8f, w - M), y + 2f, fill)
            x += 14f
        }
        y += 2f
        gap(7f)
    }

    /** Título de bloco: faixa preta com texto branco. */
    private fun section(title: String) {
        val size = S_LABEL + 1
        val p = paint(size, true).apply { color = Color.WHITE }
        val lines = wrap(title.uppercase(), p, inner - 12f)
        val h = lineH(size) * lines.size + 6f
        c?.drawRect(M, y, w - M, y + h, fill)
        for ((i, l) in lines.withIndex()) c?.drawText(l, M + 6f, y + 3f + i * lineH(size) + size * 0.93f, p)
        y += h + 5f
    }

    /** Campo: título em negrito/maiúsculas e o valor logo abaixo. */
    private fun field(title: String, value: String?, size: Float = S_VALUE, bold: Boolean = false, x0: Float = M, maxW: Float = inner) {
        text(title.uppercase(), S_LABEL, bold = true, x0 = x0, maxW = maxW)
        text(value?.takeIf { it.isNotBlank() } ?: "-", size, bold = bold, x0 = x0, maxW = maxW)
        gap(3f)
    }

    /** Dois campos lado a lado (cada um quebra dentro da sua metade). */
    private fun pair(t1: String, v1: String?, t2: String, v2: String?, size: Float = S_VALUE) {
        if (inner < 450f) {
            // bobina de 58 mm: um campo embaixo do outro
            field(t1, v1, size)
            field(t2, v2, size)
            return
        }
        val half = (inner - 10f) / 2
        val y0 = y
        field(t1, v1, size, maxW = half)
        val y1 = y
        y = y0
        field(t2, v2, size, x0 = M + half + 10f, maxW = half)
        y = max(y, y1)
    }

    /** Texto à esquerda e valor alinhado à direita na mesma linha. */
    private fun lr(
        left: String, right: String, size: Float = S_TEXT, bold: Boolean = false, labelBold: Boolean = bold,
        rightSize: Float = size
    ) {
        val pr = paint(rightSize, bold)
        val rw = pr.measureText(right)
        val y0 = y
        val dy = max(0f, (rightSize - size) * 0.8f)
        y += dy
        text(left, size, labelBold, maxW = inner - rw - 10f)
        c?.drawText(right, w - M - rw, y0 + rightSize * 0.93f, pr)
        y = max(y, y0 + lineH(rightSize))
    }

    // ------------------------------------------------------------- códigos

    private fun barcode(chave: String) {
        val widths = code128Widths(chave)
        val modules = widths.sum()
        val quiet = 10
        // a margem do papel além da área de impressão serve de zona de silêncio
        val horizontal = floor((w - 4f) / modules).toInt()
        if (horizontal >= 2) {
            val mod = min(horizontal, 3).toFloat()
            val h = 84f
            var x = floor((w - modules * mod) / 2)
            var bar = true
            for (wd in widths) {
                if (bar) c?.drawRect(x, y, x + wd * mod, y + h, fill)
                x += wd * mod
                bar = !bar
            }
            y += h
        } else {
            // bobina estreita: código de barras na vertical (permitido em qualquer orientação)
            val mod = 2f
            val barLen = min(inner, 230f)
            val x0 = floor(M + (inner - barLen) / 2)
            y += quiet * mod
            var bar = true
            for (wd in widths) {
                if (bar) c?.drawRect(x0, y, x0 + barLen, y + wd * mod, fill)
                y += wd * mod
                bar = !bar
            }
            y += quiet * mod
        }
        gap(6f)
    }

    private fun qr(data: String) {
        val m = try {
            QRCodeWriter().encode(
                data, BarcodeFormat.QR_CODE, 0, 0,
                mapOf(EncodeHintType.MARGIN to 0, EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.M)
            )
        } catch (e: Exception) {
            return
        }
        val n = m.width
        val cell = floor(min(inner, 260f) / n)
        if (cell < 2) return
        val ox = floor((w - n * cell) / 2)
        for (r in 0 until n) for (col in 0 until n) {
            if (m.get(col, r)) c?.drawRect(ox + col * cell, y + r * cell, ox + (col + 1) * cell, y + (r + 1) * cell, fill)
        }
        y += n * cell + 8f
    }

    // ------------------------------------------------------------- DANFE

    private fun s(d: Map<String, Any?>, k: String) = (d[k] as? String ?: "").trim()

    private fun draw(d: Map<String, Any?>, etiqueta: Boolean, valorTotal: Boolean) {
        y = 6f
        val chave = s(d, "chave")

        text(if (etiqueta) "DANFE SIMPLIFICADO - ETIQUETA" else "DANFE SIMPLIFICADO", if (inner < 450f) 26f else S_TITLE, true, Al.C)
        text("Documento Auxiliar da Nota Fiscal Eletrônica", S_LABEL, al = Al.C)
        if (d["epec"] == true) text("EMITIDO EM CONTINGÊNCIA (EPEC)", S_TEXT, true, Al.C)
        gap(8f)

        // chave de acesso e código de barras no alto
        if (chave.length == 44) barcode(chave)
        text("CHAVE DE ACESSO", S_LABEL, true, Al.C)
        text(DanfeModel.formatChave(chave), S_VALUE, true, Al.C)
        text("Consulta de autenticidade no portal nacional da NF-e www.nfe.fazenda.gov.br/portal ou no site da Sefaz Autorizadora",
            S_LABEL, al = Al.C)
        gap(6f)
        text("PROTOCOLO DE AUTORIZAÇÃO DE USO", S_LABEL, true, Al.C)
        text(s(d, "protocolo").ifEmpty { "-" }, S_VALUE, al = Al.C)
        val qr = s(d, "qrcode")
        if (qr.isNotEmpty()) {
            gap(6f); qr(qr)
        }
        rule()

        // dados gerais
        text("NF-e Nº ${s(d, "numero")}   SÉRIE ${s(d, "serie")}", if (inner < 450f) 25f else S_BIG, true, Al.C)
        gap(4f)
        val tipo = when (s(d, "tipo")) {
            "0" -> "0 - ENTRADA"
            "1" -> "1 - SAÍDA"
            else -> s(d, "tipo")
        }
        pair("Tipo de operação", tipo, "Data de emissão", s(d, "emissao"))
        if (!etiqueta) field("Natureza da operação", s(d, "natureza"), S_TEXT)

        // emitente
        section("Emitente")
        field("Nome / Razão social", s(d, "emitNome"), S_VALUE, bold = true)
        pair("CNPJ", s(d, "emitCnpj"), "Inscrição estadual", s(d, "emitIe"))
        if (etiqueta) {
            field("UF", s(d, "emitUf"))
        } else {
            val end = s(d, "emitEnd").replace('\n', ' ').replace(Regex("\\s+"), " ")
            field("Endereço", end.ifEmpty { s(d, "emitUf") }, S_TEXT)
            if (end.isNotEmpty() && !end.contains(s(d, "emitUf"))) field("UF", s(d, "emitUf"))
        }

        // destinatário
        section("Destinatário / Remetente")
        field("Nome / Razão social", s(d, "destNome"), S_VALUE, bold = true)
        pair("CNPJ / CPF", s(d, "destDoc"), "Inscrição estadual", s(d, "destIe"))
        if (etiqueta) {
            field("UF", s(d, "destUf"))
        } else {
            val partes = listOf(
                s(d, "destEnd"), s(d, "destBairro"),
                listOf(s(d, "destMun"), s(d, "destUf")).filter { it.isNotEmpty() }.joinToString(" - "),
                s(d, "destCep").let { if (it.isNotEmpty()) "CEP $it" else "" }
            ).filter { it.isNotEmpty() }
            field("Endereço", partes.joinToString(", "), S_TEXT)
            if (s(d, "destFone").isNotEmpty()) field("Fone", s(d, "destFone"), S_TEXT)
        }

        if (etiqueta) {
            if (valorTotal && s(d, "vNF").isNotEmpty()) {
                rule()
                lr("VALOR TOTAL DA NF-e", "R$ ${s(d, "vNF")}", S_TEXT, bold = true, rightSize = S_BIG)
            }
            rule()
            return
        }

        // itens
        @Suppress("UNCHECKED_CAST")
        val itens = d["itens"] as? List<Map<String, String>> ?: emptyList()
        section("Produtos / Serviços (${itens.size})")
        for ((i, it) in itens.withIndex()) {
            val cod = (it["cod"] ?: "").trim()
            val desc = (it["desc"] ?: "").trim()
            text(listOf("${i + 1}.", cod, desc).filter { s -> s.isNotEmpty() }.joinToString(" "), S_TEXT, true)
            val un = (it["un"] ?: "").trim()
            lr("${it["qtd"] ?: ""} ${un} x ${it["vun"] ?: ""}".replace(Regex("\\s+"), " ").trim(), it["vtot"] ?: "", S_TEXT)
            if (i < itens.size - 1) dashed() else gap(4f)
        }

        // totais
        section("Totais")
        fun linha(t: String, k: String, sinal: String = "") {
            val v = s(d, k)
            if (!DanfeModel.isZero(v)) lr(t, sinal + v, S_TEXT, labelBold = true)
        }
        lr("VALOR TOTAL DOS PRODUTOS", s(d, "vProd").ifEmpty { "-" }, S_TEXT, labelBold = true)
        linha("VALOR DO FRETE", "vFrete")
        linha("VALOR DO SEGURO", "vSeguro")
        linha("DESCONTO", "vDesc", "- ")
        linha("OUTRAS DESPESAS ACESSÓRIAS", "vOutro")
        linha("VALOR DO IPI", "vIpi")
        linha("VALOR DO ICMS ST", "vSt")
        gap(4f)
        lr("VALOR TOTAL DA NOTA", "R$ ${s(d, "vNF")}", S_TEXT, bold = true, rightSize = S_BIG)
        if (!DanfeModel.isZero(s(d, "vTrib"))) lr("VALOR APROX. DOS TRIBUTOS", s(d, "vTrib"), S_LABEL, labelBold = true)

        // transporte
        val transp = listOf("frete", "transpNome", "volQtd", "pesoBruto").any { s(d, it).isNotEmpty() }
        if (transp) {
            section("Transporte")
            if (s(d, "frete").isNotEmpty()) field("Frete por conta", s(d, "frete"), S_TEXT)
            if (s(d, "transpNome").isNotEmpty()) field("Transportador", s(d, "transpNome"), S_TEXT)
            val vol = listOf(s(d, "volQtd"), s(d, "volEspecie")).filter { it.isNotEmpty() }.joinToString(" ")
            if (vol.isNotEmpty() || s(d, "pesoBruto").isNotEmpty()) pair("Volumes", vol, "Peso bruto", s(d, "pesoBruto"), S_TEXT)
        }

        // informações complementares
        if (s(d, "info").isNotEmpty()) {
            section("Informações complementares")
            text(s(d, "info"), S_LABEL)
        }
        rule()
    }
}
