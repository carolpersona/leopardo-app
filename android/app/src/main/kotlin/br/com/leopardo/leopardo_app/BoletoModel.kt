package br.com.leopardo.leopardo_app

import java.util.Calendar
import java.util.TimeZone
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Versão nativa (Kotlin) da leitura do boleto, usada pelo serviço de impressão
 * do Android. Mesmas regras de lib/services/boleto.dart — manter as duas iguais.
 */
object BoletoModel {

    // ------------------------------------------------------------- regras

    fun onlyDigits(s: String) = s.filter { it in '0'..'9' }

    private fun mod10(d: String): Int {
        var sum = 0
        var w = 2
        for (i in d.length - 1 downTo 0) {
            var p = (d[i] - '0') * w
            if (p > 9) p = p / 10 + p % 10
            sum += p
            w = if (w == 2) 1 else 2
        }
        return (10 - sum % 10) % 10
    }

    fun barcodeDv(bc: String): Int {
        val base = bc.substring(0, 4) + bc.substring(5)
        var sum = 0
        var w = 2
        for (i in base.length - 1 downTo 0) {
            sum += (base[i] - '0') * w
            w = if (w == 9) 2 else w + 1
        }
        val dv = 11 - sum % 11
        return if (dv == 0 || dv == 10 || dv == 11) 1 else dv
    }

    fun isValidBarcode(bc: String) =
        bc.length == 44 && bc.all { it in '0'..'9' } && bc[0] != '8' && barcodeDv(bc) == bc[4] - '0'

    fun barcodeFromLinha(linha: String): String? {
        val d = onlyDigits(linha)
        if (d.length != 47) return null
        val bc = d.substring(0, 4) + d.substring(32, 33) + d.substring(33, 47) +
            d.substring(4, 9) + d.substring(10, 20) + d.substring(21, 31)
        return if (isValidBarcode(bc)) bc else null
    }

    fun linhaFromBarcode(bc: String): String {
        val f1 = bc.substring(0, 4) + bc.substring(19, 24)
        val f2 = bc.substring(24, 34)
        val f3 = bc.substring(34, 44)
        val c1 = f1 + mod10(f1)
        val c2 = f2 + mod10(f2)
        val c3 = f3 + mod10(f3)
        return "${c1.substring(0, 5)}.${c1.substring(5)} ${c2.substring(0, 5)}.${c2.substring(5)} " +
            "${c3.substring(0, 5)}.${c3.substring(5)} ${bc[4]} ${bc.substring(5, 19)}"
    }

    private fun dateFrom(y: Int, m: Int, d: Int, plusDays: Int): Calendar {
        val c = Calendar.getInstance(TimeZone.getTimeZone("UTC"))
        c.clear()
        c.set(y, m - 1, d)
        c.add(Calendar.DAY_OF_MONTH, plusDays)
        return c
    }

    fun dueDate(bc: String): String? {
        val fator = bc.substring(5, 9).toInt()
        if (fator == 0) return null
        val a = dateFrom(1997, 10, 7, fator)
        var pick = a
        if (fator >= 1000) {
            val b = dateFrom(2025, 2, 22, fator - 1000)
            val now = System.currentTimeMillis()
            if (abs(b.timeInMillis - now) < abs(a.timeInMillis - now)) pick = b
        }
        return String.format(
            "%02d/%02d/%04d",
            pick.get(Calendar.DAY_OF_MONTH), pick.get(Calendar.MONTH) + 1, pick.get(Calendar.YEAR)
        )
    }

    fun formatCents(cents: Long): String {
        val reais = (cents / 100).toString()
        val sb = StringBuilder()
        for (i in reais.indices) {
            val fromEnd = reais.length - i
            sb.append(reais[i])
            if (fromEnd > 1 && fromEnd % 3 == 1) sb.append('.')
        }
        return "$sb," + (cents % 100).toString().padStart(2, '0')
    }

    private val BANKS = mapOf(
        "001" to "Banco do Brasil", "004" to "Banco do Nordeste", "021" to "Banestes", "033" to "Santander",
        "037" to "Banpará", "041" to "Banrisul", "047" to "Banese", "070" to "BRB", "077" to "Banco Inter",
        "085" to "Ailos", "104" to "Caixa", "136" to "Unicred", "197" to "Stone", "208" to "BTG Pactual",
        "212" to "Banco Original", "237" to "Bradesco", "260" to "Nubank", "290" to "PagBank",
        "323" to "Mercado Pago", "336" to "C6 Bank", "341" to "Itaú", "380" to "PicPay", "389" to "Mercantil",
        "422" to "Safra", "633" to "Rendimento", "655" to "Votorantim", "707" to "Daycoval", "748" to "Sicredi",
        "756" to "Sicoob"
    )

    private fun bankDv(code: String): String {
        if (code == "104") return "0"
        val w = intArrayOf(4, 3, 2)
        var sum = 0
        for (i in 0 until 3) sum += (code[i] - '0') * w[i]
        val dv = 11 - sum % 11
        return when (dv) {
            11 -> "0"
            10 -> "X"
            else -> dv.toString()
        }
    }

    fun applyBarcode(d: MutableMap<String, String>, bc: String) {
        d["linha"] = linhaFromBarcode(bc)
        dueDate(bc)?.let { d["vencimento"] = it }
        val cents = bc.substring(9, 19).toLong()
        if (cents > 0) d["valor"] = formatCents(cents)
        val code = bc.substring(0, 3)
        d["banco"] = "$code-${bankDv(code)}"
        d["bancoNome"] = BANKS[code] ?: "Banco $code"
    }

    // ------------------------------------------------------------- leitura

    private class Seg(val page: Int, val x: Double, val y: Double, val w: Double, val h: Double, val text: String) {
        val norm = normalize(text)
        val right: Double get() = x + w
    }

    private const val FROM = "áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ"
    private const val TO = "aaaaaeeeeiiiiooooouuuucaaaaaeeeeiiiiooooouuuuc"

    fun normalize(s: String): String {
        val sb = StringBuilder(s.length)
        for (ch in s) {
            val i = FROM.indexOf(ch)
            sb.append(if (i >= 0) TO[i] else ch.lowercaseChar())
        }
        return sb.toString()
    }

    private val LABELS: Map<String, Regex> = linkedMapOf(
        "localPagamento" to Regex("^local d[eo] pagamento"),
        "beneficiario" to Regex("^(beneficiario|cedente)(?!\\s*final)"),
        "vencimento" to Regex("^(data d[eo] )?vencimento"),
        "agenciaCodigo" to Regex("^(agencia|ag\\.?)\\s*/?\\s*(codigo|cod\\.?|conta)|^codigo d[oa] (beneficiario|cedente)|^agencia"),
        "dataDocumento" to Regex("^data d[oa]? ?doc"),
        "numeroDocumento" to Regex("^(n[o°º.]*|num\\.?|numero)\\s*(d[oa])?\\s*doc"),
        "especieDoc" to Regex("^especie\\s*d(oc|o documento)"),
        "aceite" to Regex("^aceite"),
        "dataProcessamento" to Regex("^data (d[eo] )?proc"),
        "nossoNumero" to Regex("^nosso\\s*n"),
        "usoBanco" to Regex("^uso do banco"),
        "carteira" to Regex("^carteira"),
        "especie" to Regex("^(especie(?!\\s*d)|moeda)"),
        "quantidade" to Regex("^(quantidade|qtd|qtde)"),
        "valor" to Regex("^(\\(\\s*=\\s*\\)\\s*)?valor"),
        "instrucoes" to Regex("^instru"),
        "pagador" to Regex("^(pagador|sacado)(?!r)"),
        "sacador" to Regex("^(sacador|beneficiario final)"),
        "desconto" to Regex("^\\(\\s*-\\s*\\)"),
        "acrescimo" to Regex("^\\(\\s*\\+\\s*\\)"),
        "cobrado" to Regex("^\\(\\s*=\\s*\\)"),
        "autenticacao" to Regex("^autentica"),
        "recibo" to Regex("^(recibo do pagador|ficha de compensacao)"),
        "baixa" to Regex("^codigo de baixa")
    )

    private fun isLabel(s: Seg) = LABELS.values.any { it.containsMatchIn(s.norm) }

    private class Code(val bc: String, val page: Int, val y: Double?)

    private fun num(v: Any?): Double = (v as? Number)?.toDouble() ?: 0.0

    /** Interpreta o resultado de BoletoAnalyzer.analyze(): um mapa de campos por boleto. */
    @Suppress("UNCHECKED_CAST")
    fun read(raw: Map<String, Any>): List<MutableMap<String, String>> {
        val segs = (raw["segments"] as? List<Map<String, Any>> ?: emptyList()).map {
            Seg(num(it["page"]).toInt(), num(it["x"]), num(it["y"]), num(it["w"]), num(it["h"]), it["text"] as String)
        }
        val barcodes = raw["barcodes"] as? List<Map<String, Any>> ?: emptyList()

        val codes = ArrayList<Code>()
        val seen = HashSet<String>()
        for (b in barcodes) {
            if (b["format"] != "ITF") continue
            val bc = onlyDigits(b["text"] as String)
            if (!isValidBarcode(bc) || !seen.add(bc)) continue
            codes.add(Code(bc, num(b["page"]).toInt(), num(b["y"])))
        }
        val linhaRe = Regex("(\\d{5})\\D?(\\d{5})\\s*(\\d{5})\\D?(\\d{6})\\s*(\\d{5})\\D?(\\d{6})\\s*(\\d)\\s*(\\d{14})")
        for (s in segs) {
            for (m in linhaRe.findAll(s.text)) {
                val bc = barcodeFromLinha(m.value) ?: continue
                if (!seen.add(bc)) continue
                codes.add(Code(bc, s.page, null))
            }
        }
        codes.sortWith(compareBy<Code>({ it.page }, { it.y ?: 0.0 }))

        val pix = barcodes.filter { it["format"] == "QR_CODE" && (it["text"] as String).startsWith("000201") }

        val out = ArrayList<MutableMap<String, String>>()
        for (c in codes) {
            val samePage = codes.filter { it.page == c.page }
            var minY = -1.0
            var maxY = 1e9
            if (samePage.size > 1 && samePage.all { it.y != null }) {
                val idx = samePage.indexOf(c)
                if (idx > 0) minY = samePage[idx - 1].y!!
                maxY = c.y!!
            }
            val region = segs.filter { it.page == c.page && it.y > minY && it.y < maxY }
            val d = HashMap<String, String>()
            applyBarcode(d, c.bc)
            fill(d, region, c.bc)
            val q = pix.firstOrNull {
                val y = num(it["y"])
                num(it["page"]).toInt() == c.page && y > minY && y < maxY + 400
            }
            if (q != null) d["pix"] = q["text"] as String
            out.add(d)
        }
        return out
    }

    private fun findLabel(segs: List<Seg>, key: String): Seg? {
        val re = LABELS[key]!!
        var best: Seg? = null
        for (s in segs) {
            if (!re.containsMatchIn(s.norm)) continue
            val b = best
            if (b == null || s.y > b.y + 1 || (abs(s.y - b.y) <= 1 && s.x < b.x)) best = s
        }
        return best
    }

    private fun valueLines(segs: List<Seg>, key: String, lines: Int): List<String> {
        val label = findLabel(segs, key) ?: return emptyList()
        val re = LABELS[key]!!
        val out = ArrayList<String>()

        val m = re.find(label.norm)!!
        val end = m.range.last + 1
        var rest = if (label.text.length >= end) label.text.substring(end) else ""
        val colon = rest.indexOf(':')
        rest = if (colon >= 0) {
            rest.substring(colon + 1).trim()
        } else {
            rest.replaceFirst(Regex("^[^\\s\\-–/]*"), "").replaceFirst(Regex("^[\\s\\-–/]+"), "").trim()
        }
        val restIsLabel = !Regex("\\d").containsMatchIn(rest) &&
            Regex("^(d[oae]s?|e)\\b", RegexOption.IGNORE_CASE).containsMatchIn(rest)
        if (rest.length >= 2 && !rest.startsWith("(") && !restIsLabel) out.add(rest)

        fun same(s: Seg) = abs(s.y - label.y) <= max(label.h, s.h) * 0.6

        var colEnd = 1e9
        for (s in segs) {
            if (s === label || !same(s)) continue
            if (s.x > label.right + 2 && isLabel(s) && s.x < colEnd) colEnd = s.x
        }

        var lastY: Double? = null
        var valueX = label.x
        if (out.isEmpty()) {
            val sm = segs.filter { it !== label && same(it) && it.x > label.right && it.x < colEnd && !isLabel(it) }
                .sortedBy { it.x }
            if (sm.isNotEmpty()) {
                out.add(sm.joinToString("  ") { it.text })
                lastY = sm[0].y
                valueX = sm[0].x
            }
        }

        val below = segs.filter {
            !same(it) && it.y > label.y && it.x >= min(label.x, valueX) - 8 && it.x < colEnd - 2 && it.y < label.y + 400
        }.sortedWith(compareBy<Seg>({ it.y }, { it.x }))
        val maxFirstGap = max(24.0, label.h * 3.2)
        for (s in below) {
            if (isLabel(s)) break
            val ly = lastY
            if (ly != null && abs(s.y - ly) <= 2 && out.isNotEmpty()) {
                out[out.size - 1] = out.last() + " " + s.text
                continue
            }
            if (out.size >= lines) break
            if (ly == null) {
                if (s.y - label.y > maxFirstGap) break
            } else if (s.y - ly > s.h * 2.2) {
                break
            }
            out.add(s.text)
            lastY = s.y
        }
        return out.map { it.trim() }.filter { it.isNotEmpty() }
    }

    private fun one(segs: List<Seg>, key: String, mustMatch: Regex? = null): String {
        for (v in valueLines(segs, key, 2)) {
            if (mustMatch == null) return v
            val m = mustMatch.find(v)
            if (m != null) return m.value
        }
        return ""
    }

    private fun fill(d: MutableMap<String, String>, segs: List<Seg>, bc: String) {
        val date = Regex("\\d{2}/\\d{2}/\\d{4}")
        val digits = Regex("[\\d][\\d\\s./\\-xX]*[\\dxX]")
        fun put(k: String, v: String) {
            if (v.isNotBlank()) d[k] = v.trim()
        }

        val code = bc.substring(0, 3)
        val bankRe = Regex("(^|\\D)$code\\s*-\\s*([0-9xX])(\\D|$)")
        for (s in segs) {
            val m = bankRe.find(s.text)
            if (m != null) {
                d["banco"] = "$code-${m.groupValues[2].uppercase()}"
                break
            }
        }
        val venc = one(segs, "vencimento", date)
        if (venc.isNotEmpty()) d["vencimento"] = venc
        put("localPagamento", valueLines(segs, "localPagamento", 2).joinToString(" "))
        put("beneficiario", valueLines(segs, "beneficiario", 3).joinToString("\n"))
        put("agenciaCodigo", one(segs, "agenciaCodigo", digits))
        put("nossoNumero", one(segs, "nossoNumero", digits))
        put("numeroDocumento", one(segs, "numeroDocumento"))
        put("dataDocumento", one(segs, "dataDocumento", date))
        put("dataProcessamento", one(segs, "dataProcessamento", date))
        put("especieDoc", one(segs, "especieDoc"))
        put("aceite", one(segs, "aceite", Regex("^[A-Za-z]{1,3}$")))
        put("carteira", one(segs, "carteira"))
        put("pagador", valueLines(segs, "pagador", 3).joinToString("\n"))
        val sacador = valueLines(segs, "sacador", 1).joinToString(" ")
        if (!normalize(sacador).contains("nao informado")) put("sacador", sacador)
        put("instrucoes", valueLines(segs, "instrucoes", 10).joinToString("\n"))
    }
}
