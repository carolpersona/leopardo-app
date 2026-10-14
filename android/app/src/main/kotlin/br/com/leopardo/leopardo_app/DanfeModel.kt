package br.com.leopardo.leopardo_app

import java.text.Normalizer
import java.util.Locale
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Lê um DANFE (NF-e modelo 55) em PDF A4 e devolve os dados para o
 * "DANFE Simplificado" em 80 mm.
 *
 * Entrada: as palavras com posição na página (BoletoAnalyzer.analyze → "words",
 * normalizadas para página de 595 pt) e os códigos de barras lidos.
 * Os dados são copiados do DANFE como estão (o DANFE precisa refletir o XML);
 * só a chave de acesso é validada pelo dígito verificador.
 *
 * Código Kotlin puro (sem Android) para poder ser testado no computador.
 */
object DanfeModel {

    /** Para testes: recebe erros de leitura de uma nota. */
    var onError: ((Throwable) -> Unit)? = null

    class Word(val page: Int, val x: Float, val right: Float, val base: Float, val size: Float, val text: String) {
        val norm: String = key(text)
        val cx get() = (x + right) / 2
    }

    private class Line(val page: Int, val base: Float, val words: List<Word>) {
        val text get() = words.joinToString(" ") { it.text }
    }

    private class Label(val page: Int, val x: Float, val right: Float, val base: Float, val size: Float, val line: Line, val first: Int, val last: Int)

    // ------------------------------------------------------------------ texto

    private fun strip(s: String): String =
        Normalizer.normalize(s, Normalizer.Form.NFD).replace(Regex("\\p{M}+"), "")

    /** Maiúsculas sem acento e só letras/números ("Razão Social:" → "RAZAOSOCIAL"). */
    fun key(s: String): String = strip(s).uppercase(Locale.ROOT).replace(Regex("[^A-Z0-9]"), "")

    /** Maiúsculas sem acento, mesmo comprimento do original (para recortar o original). */
    private fun upper(s: String): String = buildString {
        for (ch in s) {
            val n = strip(ch.toString())
            append((if (n.length == 1) n else ch.toString()).uppercase(Locale.ROOT).firstOrNull() ?: ch)
        }
    }

    private val MONEY = Regex("-?\\d{1,3}(?:\\.\\d{3})*,\\d{2,}|-?\\d+,\\d{2,}|-?\\d+\\.\\d{2}(?!\\d)")
    private val NUM = Regex("^-?[\\d.,]*\\d$")
    private val CFOP = Regex("^[1-7]\\.?\\d{3}$")
    private val NCM = Regex("^(\\d{8}|\\d{4}\\.\\d{2}\\.\\d{2}|\\d{2}|\\d{4}\\.\\d{4})$")
    private val DATE = Regex("\\d{2}[/.\\-]\\d{2}[/.\\-]\\d{4}")
    private val TIME = Regex("\\d{2}:\\d{2}(?::\\d{2})?")

    // ------------------------------------------------------------------ chave de acesso

    private val UFS = mapOf(
        "11" to "RO", "12" to "AC", "13" to "AM", "14" to "RR", "15" to "PA", "16" to "AP", "17" to "TO",
        "21" to "MA", "22" to "PI", "23" to "CE", "24" to "RN", "25" to "PB", "26" to "PE", "27" to "AL",
        "28" to "SE", "29" to "BA", "31" to "MG", "32" to "ES", "33" to "RJ", "35" to "SP", "41" to "PR",
        "42" to "SC", "43" to "RS", "50" to "MS", "51" to "MT", "52" to "GO", "53" to "DF"
    )

    /** DV da chave (módulo 11; CNPJ alfanumérico: valor do caractere = código ASCII − 48). */
    fun chaveValida(c: String): Boolean {
        if (c.length != 44) return false
        if (!c.substring(0, 6).all { it.isDigit() } || !c.substring(20).all { it.isDigit() }) return false
        if (!c.substring(6, 20).all { it.isDigit() || it in 'A'..'Z' }) return false
        if (UFS[c.substring(0, 2)] == null) return false
        if (c.substring(20, 22) != "55") return false
        var sum = 0
        var w = 2
        for (i in 42 downTo 0) {
            sum += (c[i].code - 48) * w
            w = if (w == 9) 2 else w + 1
        }
        val r = sum % 11
        val dv = if (r < 2) 0 else 11 - r
        return dv == c[43] - '0'
    }

    /** Chave com a estrutura certa (UF, modelo 55), mesmo sem conferir o DV. */
    private fun chaveFormato(c: String): Boolean =
        c.length == 44 && c.substring(0, 6).all { it.isDigit() } && c.substring(20).all { it.isDigit() } &&
            c.substring(6, 20).all { it.isDigit() || it in 'A'..'Z' } && UFS[c.substring(0, 2)] != null &&
            c.substring(20, 22) == "55"

    private fun chaves(s: String, strict: Boolean = true): List<String> {
        val k = upper(s).replace(Regex("[^0-9A-Z]"), "")
        val out = ArrayList<String>()
        var i = 0
        while (i + 44 <= k.length) {
            val c = k.substring(i, i + 44)
            if (if (strict) chaveValida(c) else chaveFormato(c)) {
                out.add(c); i += 44
            } else i++
        }
        return out
    }

    fun formatChave(c: String) = c.chunked(4).joinToString(" ")

    private fun fmtCnpj(c: String): String =
        if (c.length == 14) "${c.substring(0, 2)}.${c.substring(2, 5)}.${c.substring(5, 8)}/${c.substring(8, 12)}-${c.substring(12)}"
        else c

    // ------------------------------------------------------------------ linhas e rótulos

    private fun lines(words: List<Word>): List<Line> {
        val out = ArrayList<Line>()
        for ((page, list) in words.groupBy { it.page }) {
            val sorted = list.sortedWith(compareBy<Word>({ it.base }, { it.x }))
            var cur = ArrayList<Word>()
            var base = 0f
            for (w in sorted) {
                if (cur.isNotEmpty() && abs(w.base - base) <= max(1.5f, cur[0].size * 0.3f)) {
                    cur.add(w)
                } else {
                    if (cur.isNotEmpty()) out.add(Line(page, base, cur.sortedBy { it.x }))
                    cur = arrayListOf(w)
                    base = w.base
                }
            }
            if (cur.isNotEmpty()) out.add(Line(page, base, cur.sortedBy { it.x }))
        }
        return out.sortedWith(compareBy<Line>({ it.page }, { it.base }))
    }

    private class Page(val index: Int, val lines: List<Line>, val width: Float, val height: Float)

    /** Procura um rótulo (sequência de palavras) entre [minBase, maxBase]. */
    private fun Page.find(
        keys: List<String>, minBase: Float = -1f, maxBase: Float = 1e9f,
        notFollowedBy: List<String> = emptyList(), minX: Float = -1f, maxX: Float = 1e9f
    ): Label? {
        for (key in keys) {
            for (line in lines) {
                if (line.base < minBase || line.base > maxBase) continue
                val ws = line.words
                for (i in ws.indices) {
                    if (ws[i].x < minX || ws[i].x > maxX) continue
                    var acc = ""
                    var j = i
                    while (j < ws.size && acc.length < key.length) {
                        // palavras de um rótulo ficam próximas
                        if (j > i && ws[j].x - ws[j - 1].right > max(ws[j].size, ws[j - 1].size) * 1.6f) break
                        acc += ws[j].norm
                        j++
                    }
                    if (acc != key) continue
                    val next = ws.getOrNull(j)
                    if (next != null && notFollowedBy.isNotEmpty() &&
                        next.x - ws[j - 1].right < next.size * 1.6f &&
                        notFollowedBy.any { next.norm.startsWith(it) }
                    ) continue
                    // o rótulo pode continuar ("BAIRRO / DESTRITO"): junta palavras coladas
                    var e = j - 1
                    while (e + 1 < ws.size && ws[e + 1].x - ws[e].right < ws[e].size * 0.6f &&
                        ws[e + 1].size <= ws[i].size + 0.3f
                    ) e++
                    return Label(index, ws[i].x, ws[e].right, line.base, ws.subList(i, e + 1).maxOf { it.size }, line, i, e)
                }
            }
        }
        return null
    }

    /** O rótulo mais alto da página entre várias alternativas (para achar seções). */
    private fun Page.top(keys: List<String>, minBase: Float = -1f, maxBase: Float = 1e9f): Label? =
        keys.mapNotNull { find(listOf(it), minBase, maxBase) }.minByOrNull { it.base }

    private val LABEL_KEYS = listOf(
        "INSCRICAO", "INSCESTADUAL", "MUNICIPIO", "ENDERECO", "BAIRRO", "VALORDO", "VALORTOTAL", "BASEDECALC",
        "QUANTIDADE", "DATADA", "DATADE", "DATAEMISSAO", "CNPJ", "RAZAOSOCIAL", "FONE", "TELEFONE", "HORADE", "HORADA",
        "PESOBRUTO", "PESOLIQUIDO", "NATUREZA", "PROTOCOLO", "CALCULODO", "TRANSPORTADOR", "DESTINATARIO",
        "FATURA", "DADOSDO", "DADOSADICIONAIS", "ESPECIE", "MARCA", "NUMERACAO", "CODIGOANTT", "PLACA",
        "FRETEPORCONTA", "OUTRASDESPESAS", "DESCONTO", "VALORAPROX", "HORASAIDA"
    )

    private fun countKeys(k: String) = LABEL_KEYS.count { k.contains(it) }

    /** A linha abaixo é de rótulos (célula vazia) e não de valores? */
    private fun looksLikeLabel(ws: List<Word>, line: Line, label: Label): Boolean {
        val k = ws.joinToString("") { it.norm }
        if (countKeys(k) == 0) return false
        if (countKeys(line.words.joinToString("") { it.norm }) >= 2) return true
        val txt = ws.joinToString(" ") { it.text }
        return txt == upper(txt) && ws.all { it.size <= label.size + 0.5f }
    }

    /**
     * Valor de um rótulo: as palavras da primeira linha logo abaixo dele,
     * dentro da largura da célula (até o próximo rótulo da mesma linha).
     */
    private fun Page.value(l: Label, limit: Float = 1e9f, maxDy: Float = 20f): String {
        val ws = l.line.words
        val prev = ws.getOrNull(l.first - 1)
        // próximo rótulo à direita (na mesma linha ou em linha vizinha, desalinhada por poucos pontos)
        val nextX = lines.filter { abs(it.base - l.base) <= max(4f, l.size * 0.8f) }
            .flatMap { it.words }.filter { it.x > l.right + 0.5f }.minOfOrNull { it.x }
        val left = max(if (prev != null) prev.right + 1f else 0f, l.x - 2.5f)
        val right = if (nextX != null) nextX - 1f else width
        for (line in lines) {
            if (line.base <= l.base + l.size * 0.5f) continue
            if (line.base > l.base + maxDy || line.base >= limit - 0.5f) break
            val inCell = line.words.filter { it.x >= left - 1f && it.cx <= right }
            if (inCell.isEmpty()) continue
            if (looksLikeLabel(inCell, line, l)) return ""
            return inCell.joinToString(" ") { it.text }.trim()
        }
        return ""
    }

    private fun Page.field(
        keys: List<String>, minBase: Float = -1f, maxBase: Float = 1e9f,
        notFollowedBy: List<String> = emptyList()
    ): String {
        val l = find(keys, minBase, maxBase, notFollowedBy) ?: return ""
        return value(l, limit = maxBase)
    }

    private fun money(s: String): String = MONEY.findAll(s).lastOrNull()?.value ?: ""

    // ------------------------------------------------------------------ leitura

    @Suppress("UNCHECKED_CAST")
    fun read(analysis: Map<String, Any?>): List<Map<String, Any?>> {
        val words = (analysis["words"] as? List<Map<String, Any?>> ?: emptyList()).map {
            Word(
                (it["page"] as Number).toInt(), (it["x"] as Number).toFloat(), (it["right"] as Number).toFloat(),
                (it["base"] as Number).toFloat(), (it["size"] as Number).toFloat(), it["text"] as String
            )
        }
        val pages = (analysis["pages"] as? List<Map<String, Any?>> ?: emptyList()).map {
            val w = (it["width"] as Number).toFloat()
            val h = (it["height"] as Number).toFloat()
            // coordenadas normalizadas para 595 pt de largura
            Pair(595f, h * 595f / max(w, 10f))
        }
        val barcodes = (analysis["barcodes"] as? List<Map<String, Any?>> ?: emptyList())
            .map { Pair((it["page"] as Number).toInt(), (it["text"] as? String ?: "")) }
        val raw = (analysis["rawText"] as? List<*> ?: emptyList<Any>()).map { it?.toString() ?: "" }
        return parse(words, pages, barcodes, raw)
    }

    fun parse(
        words: List<Word>, pageSizes: List<Pair<Float, Float>>, barcodes: List<Pair<Int, String>>,
        rawText: List<String> = emptyList()
    ): List<Map<String, Any?>> {
        val all = lines(words)
        val pages = all.groupBy { it.page }.map { (i, ls) ->
            val s = pageSizes.getOrNull(i) ?: Pair(595f, 842f)
            Page(i, ls, s.first, s.second)
        }.sortedBy { it.index }

        // Chave de cada página: a primeira válida do alto da página (ou do código de barras).
        val dvInvalido = HashSet<String>()
        val pageChave = LinkedHashMap<Int, String>()
        for (p in pages) {
            val fromBar = barcodes.filter { it.first == p.index }.map { it.second.trim().uppercase(Locale.ROOT) }
                .firstOrNull { chaveValida(it) }
            var found: String? = null
            for (line in p.lines) {
                if (key(line.text).contains("REFERENCIAD")) continue
                val c = chaves(line.text).firstOrNull()
                if (c != null) {
                    found = c; break
                }
            }
            // Texto na ordem do arquivo (alguns PDFs sobrepõem os dígitos e a ordem por posição embaralha)
            if (found == null) {
                for (rl in rawText.getOrElse(p.index) { "" }.split('\n')) {
                    if (key(rl).contains("REFERENCIAD")) continue
                    val c = chaves(rl).firstOrNull()
                    if (c != null) {
                        found = c; break
                    }
                }
            }
            // Sem DV válido: aceita a sequência logo abaixo do rótulo "CHAVE DE ACESSO"
            if (found == null) {
                val l = p.find(listOf("CHAVEDEACESSO", "CHAVEDEACESSODANFE", "CHAVEDEACESSODANFE"))
                if (l != null) {
                    val near = p.lines.filter { it.base >= l.base - 1 && it.base <= l.base + 25 }
                        .map { line -> line.words.filter { it.x >= l.x - 30 }.joinToString(" ") { it.text } }
                    found = near.firstNotNullOfOrNull { chaves(it, strict = false).firstOrNull() }
                    if (found != null) dvInvalido.add(found)
                }
            }
            val ch = fromBar ?: found
            if (ch != null && (!pageChave.containsValue(ch) || pageChave[p.index - 1] == ch)) pageChave[p.index] = ch
            else if (ch == null && pageChave.containsKey(p.index - 1)) pageChave[p.index] = pageChave[p.index - 1]!!
        }
        if (pageChave.isEmpty()) return emptyList()

        val out = ArrayList<Map<String, Any?>>()
        val groups = LinkedHashMap<String, MutableList<Page>>()
        for (p in pages) {
            val c = pageChave[p.index] ?: continue
            groups.getOrPut(c) { ArrayList() }.add(p)
        }
        for ((chave, ps) in groups) {
            val n = try {
                nota(chave, ps, rawText)
            } catch (e: Exception) {
                onError?.invoke(e)
                fromChave(chave)
            }
            if (chave in dvInvalido) n["chaveAviso"] = true
            // QR Code da NF-e (leiautes novos), quando o DANFE A4 tiver
            val idx = ps.map { it.index }.toSet()
            barcodes.firstOrNull { (pg, t) ->
                pg in idx && t.startsWith("http", ignoreCase = true) &&
                    (t.contains(chave) || t.contains("chNFe", ignoreCase = true) || t.contains("qrcode", ignoreCase = true))
            }?.let { n["qrcode"] = it.second }
            out.add(n)
        }
        return out
    }

    private fun fromChave(c: String): MutableMap<String, Any?> {
        val m = LinkedHashMap<String, Any?>()
        m["chave"] = c
        m["emitUf"] = UFS[c.substring(0, 2)] ?: ""
        m["emitCnpj"] = fmtCnpj(c.substring(6, 20))
        m["modelo"] = c.substring(20, 22)
        m["serie"] = c.substring(22, 25).trimStart('0').ifEmpty { "0" }
        val n = c.substring(25, 34)
        m["numero"] = "${n.substring(0, 3)}.${n.substring(3, 6)}.${n.substring(6)}"
        m["tpEmis"] = c.substring(34, 35)
        m["itens"] = emptyList<Map<String, String>>()
        return m
    }

    private fun nota(chave: String, ps: List<Page>, rawText: List<String>): MutableMap<String, Any?> {
        val m = fromChave(chave)
        val p = ps.first()

        fun y(minBase: Float, vararg keys: String) = p.top(keys.toList(), minBase)?.base
        val nat0 = p.find(listOf("NATUREZADAOPERACAO"))?.base ?: 0f
        val destY = y(nat0, "DESTINATARIOREMETENTE", "DESTINATARIO") ?: (p.height * 0.3f)
        val calcY = y(destY, "CALCULODOIMPOSTO", "CALCULODOICMS", "TOTALDOSPRODUTOSETOTALDANOTA", "TOTALDOSPRODUTOS", "TOTALDOICMSIPI", "TOTAISDANOTA") ?: (destY + 90f)
        val faturaY = p.find(listOf("FATURADUPLICATA", "FATURADUPLICATAS", "FATURA", "DUPLICATAS"), destY + 2, calcY)?.base ?: calcY
        val transpY = y(calcY, "TRANSPORTADORVOLUMESTRANSPORTADOS", "TRANSPORTADORVOLUMES", "TRANSPORTADORVOLUME", "TRANSPORTADOR")
            ?: (calcY + 50f)
        val prodY = y(transpY, "DADOSDOPRODUTOSERVICO", "DADOSDOSPRODUTOSSERVICOS", "DADOSDOSPRODUTOS", "DADOSDOPRODUTO", "DADOSDOSPRODUTOSSERVICO")
            ?: (transpY + 60f)
        val natY = p.find(listOf("NATUREZADAOPERACAO"), maxBase = destY)?.base ?: (destY - 50f)

        // ---------- cabeçalho / emitente
        val recebY = p.find(listOf("DATADERECEBIMENTO", "DATADORECEBIMENTO"), maxBase = destY)?.base ?: 0f
        val canhoto = p.lines.filter { it.base < recebY - 1 && it.base < natY }.joinToString(" ") { it.text }
        m["emitNome"] = emitenteDoCanhoto(rawText.getOrElse(p.index) { "" }).ifEmpty { emitenteDoCanhoto(canhoto) }

        val danfeWord = p.lines.filter { it.base < natY }.flatMap { it.words }.firstOrNull { it.norm == "DANFE" }
        if ((m["emitNome"] as String).isEmpty()) m["emitNome"] = emitenteDoQuadro(p, danfeWord, natY, recebY)

        m["natureza"] = p.field(listOf("NATUREZADAOPERACAO"), maxBase = destY)
        val prot = p.field(listOf("PROTOCOLODEAUTORIZACAODEUSO", "PROTOCOLODEAUTORIZACAO", "NUMEROPROTOCOLO", "PROTOCOLO"), maxBase = destY)
        m["protocolo"] = protocolo(prot).ifEmpty { protocolo(p.lines.filter { it.base < destY }.joinToString(" ") { it.text }) }
        m["emitIe"] = p.field(
            listOf("INSCRICAOESTADUAL", "INSCESTADUAL", "IE"), natY - 2, destY,
            notFollowedBy = listOf("DO", "DE", "SUBST", "ST")
        )
        val cnpjLabel = p.field(listOf("CNPJCPF", "CNPJ", "CPFCNPJ"), natY - 2, destY)
        val cnpjDigits = key(cnpjLabel)
        if (cnpjDigits.length == 11 && chave.substring(6, 20).endsWith(cnpjDigits)) m["emitCnpj"] = cnpjLabel
        m["emitEnd"] = enderecoEmitente(p, danfeWord, natY, recebY, m["emitNome"] as String)
        m["tipo"] = tipoOperacao(p, natY)
        if (m["tpEmis"] == "4" || p.lines.any { it.base < destY && key(it.text).contains("EPEC") }) m["epec"] = true

        // ---------- destinatário
        val dMax = faturaY
        m["destNome"] = p.field(listOf("NOMERAZAOSOCIAL", "RAZAOSOCIALNOME", "RAZAOSOCIAL", "NOME"), destY, dMax)
        m["destDoc"] = p.field(listOf("CNPJCPF", "CPFCNPJ", "CNPJ", "CPF"), destY, dMax)
        m["destIe"] = p.field(listOf("INSCRICAOESTADUAL", "INSCESTADUAL", "IE"), destY, dMax, notFollowedBy = listOf("DO", "SUBST"))
        m["destEnd"] = p.field(listOf("ENDERECO"), destY, dMax)
        m["destBairro"] = p.field(listOf("BAIRRODISTRITO", "BAIRRO"), destY, dMax)
        m["destCep"] = p.field(listOf("CEP"), destY, dMax)
        m["destMun"] = p.field(listOf("MUNICIPIO"), destY, dMax)
        m["destUf"] = p.field(listOf("UF"), destY, dMax).take(2)
        m["destFone"] = p.field(listOf("FONEFAX", "TELEFONEFAX", "FONE", "TELEFONE"), destY, dMax)
        val em = p.field(listOf("DATADAEMISSAO", "DATAEMISSAO", "DATADEEMISSAO", "EMISSAO"), destY, dMax)
        m["emissao"] = DATE.find(em)?.value?.replace('.', '/')?.replace('-', '/') ?: em

        // ---------- totais
        val tMin = calcY - 1
        val tMax = transpY
        fun tot(vararg keys: String) = money(p.field(keys.toList(), tMin, tMax, notFollowedBy = listOf("ST", "SUBST")))
        m["vProd"] = tot("VALORTOTALDOSPRODUTOS", "VTOTALPRODUTOS", "VALORTOTALPRODUTOS", "VTOTALDOSPRODUTOS", "VTOTALPROD", "TOTALDOSPRODUTOS")
        m["vFrete"] = tot("VALORDOFRETE", "VFRETE", "FRETE")
        m["vSeguro"] = tot("VALORDOSEGURO", "VSEGURO", "SEGURO")
        m["vDesc"] = tot("DESCONTO", "VALORDODESCONTO", "VDESCONTO", "DESCONTOS")
        m["vOutro"] = tot("OUTRASDESPESASACESSORIAS", "OUTRASDESPESASACES", "OUTRASDESPESAS", "OUTRASDESP", "DESPESASACESSORIAS")
        m["vIpi"] = tot("VALORDOIPI", "VALORTOTALIPI", "VALORTOTALDOIPI", "VIPI", "VALORIPI")
        m["vSt"] = money(p.field(listOf("VALORDOICMSST", "VALORDOICMSSUBST", "VALORDOICMSSUBSTITUICAO", "VICMSST", "VALORICMSST", "VALORDOICMSSUBSTITUTO"), tMin, tMax))
        m["vNF"] = tot("VALORTOTALDANOTA", "VTOTALDANOTA", "VALORTOTALDANF", "VALORTOTALNOTA", "VTOTALNOTA", "VALORTOTALDANFE", "VTOTALDANF")
        m["vTrib"] = tot(
            "VALORAPROXTRIBUTOS", "VTOTTRIB", "VALORTOTALDOSTRIBUTOS", "VALORAPROXIMADODOSTRIBUTOS", "VALORAPROXDOSTRIBUTOS",
            "VALORTOTALTRIBUTOS", "VTOTALTRIBUTOS", "VALORAPROXIMADOTRIBUTOS", "VTOTTRIBUTOS"
        )

        // ---------- transporte
        val trMax = prodY
        m["frete"] = p.field(listOf("FRETEPORCONTA", "MODALIDADEDOFRETE", "FRETE"), transpY - 1, trMax)
        m["transpNome"] = p.field(listOf("NOMERAZAOSOCIAL", "RAZAOSOCIAL", "NOME"), transpY - 1, trMax)
        m["volQtd"] = p.field(listOf("QUANTIDADE", "QTDE", "QTD"), transpY - 1, trMax)
        m["volEspecie"] = p.field(listOf("ESPECIE"), transpY - 1, trMax)
        m["pesoBruto"] = p.field(listOf("PESOBRUTO"), transpY - 1, trMax)
        m["pesoLiquido"] = p.field(listOf("PESOLIQUIDO"), transpY - 1, trMax)

        // ---------- itens e informações complementares (todas as páginas da nota)
        val itens = ArrayList<Map<String, String>>()
        val info = StringBuilder()
        for (pg in ps) {
            itens.addAll(itensDaPagina(pg))
            val inf = informacoes(pg)
            if (inf.isNotEmpty()) {
                if (info.isNotEmpty()) info.append(' ')
                info.append(inf)
            }
        }
        m["itens"] = itens
        m["info"] = info.toString()
        return m
    }

    // ------------------------------------------------------------------ partes

    private fun emitenteDoCanhoto(text: String): String {
        val u = upper(text)
        val patterns = listOf(
            Regex("RECEBEMOS DE\\s+(.+?)\\s+(?:OS|AS|O\\(S\\)|A\\(S\\))\\s+(?:PRODUTOS|MERCADORIAS|SERVICOS|PRODUTO)"),
            Regex("RECEBEMOS DE\\s+(.+?)\\s+(?:OS|AS|O\\(S\\))\\s"),
            Regex("AO LADO DE\\s+(.+?)(?:\\s+EMISSAO|\\s+VALOR TOTAL|\\s+DATA DE RECEBIMENTO|\\s+DESTINATARIO|$)"),
            Regex("INDICADA (?:AO LADO|ABAIXO)\\s*[-:]?\\s*EMITENTE\\s*:?\\s*(.+?)(?:\\s+EMISSAO|$)")
        )
        for (r in patterns) {
            val mm = r.find(u) ?: continue
            val g = mm.groups[1] ?: continue
            val s = text.substring(g.range.first, g.range.last + 1).trim().trimEnd('.', ',', '-')
            if (s.length in 3..120) return s
        }
        return ""
    }

    private fun emitenteDoQuadro(p: Page, danfe: Word?, natY: Float, recebY: Float): String {
        val maxX = quadroDanfeX(p, danfe, natY) - 3f
        val cand = p.lines.filter { it.base > recebY + 4 && it.base < natY - 2 }
            .flatMap { it.words }
            .filter { it.right < maxX && it.norm.length > 1 && !it.norm.startsWith("IDENTIFICACAO") }
        val big = cand.maxOfOrNull { it.size } ?: return ""
        val sel = cand.filter { it.size >= big - 0.3f }
        return lines(sel).joinToString(" ") { it.text }.trim()
    }

    /** Borda esquerda do quadro "DANFE" (o endereço do emitente fica à esquerda dele). */
    private fun quadroDanfeX(p: Page, danfe: Word?, natY: Float): Float {
        if (danfe == null) return 300f
        val keys = listOf("DOCUMENTO", "0ENTRADA", "ENTRADA", "SERIE", "FOLHA", "N", "NO", "0", "1SAIDA", "SAIDA")
        val col = p.lines.filter { it.base >= danfe.base - 5 && it.base < natY }.flatMap { it.words }
            .filter { abs(it.x - danfe.x) < 70 && keys.any { k -> it.norm == k || it.norm.startsWith("DOCUMENTO") } }
        return min(danfe.x, col.minOfOrNull { it.x } ?: danfe.x)
    }

    private fun enderecoEmitente(p: Page, danfe: Word?, natY: Float, recebY: Float, nome: String): String {
        val maxX = quadroDanfeX(p, danfe, natY) - 3f
        val top = max(recebY + 4f, (danfe?.base ?: recebY) - 20f)
        val nomeKey = key(nome)
        val ws = p.lines.filter { it.base > top && it.base < natY - 2 }
            .flatMap { it.words }.filter { it.x < maxX - 4f }
        val out = ArrayList<String>()
        for (line in lines(ws)) {
            val k = key(line.text)
            if (k.isEmpty() || k.startsWith("IDENTIFICACAODOEMITENTE") || k == "EMITENTE") continue
            if (nomeKey.isNotEmpty() && (nomeKey.contains(k) || k.contains(nomeKey))) continue
            if (Regex("\\d{2}\\.\\d{3}\\.\\d{3}/\\d{4}-\\d{2}").containsMatchIn(line.text) && k.contains("CNPJ")) continue
            out.add(line.text.trim())
        }
        return out.take(5).joinToString("\n")
    }

    private fun tipoOperacao(p: Page, natY: Float): String {
        val ls = p.lines.filter { it.base < natY }
        val saida = ls.flatMap { it.words }.firstOrNull { it.norm.endsWith("SAIDA") } ?: return ""
        val cands = ls.flatMap { it.words }.filter {
            (it.text == "0" || it.text == "1") && it.x > saida.right - 1 && it.x < saida.right + 110 &&
                abs(it.base - saida.base) < 22
        }
        return cands.minByOrNull { abs(it.base - saida.base) + (it.x - saida.right) * 0.1f }?.text ?: ""
    }

    private fun protocolo(s: String): String {
        val n = Regex("(?<!\\d)([1-9]\\d{14})(?!\\d)").find(s) ?: return ""
        val rest = s.substring(n.range.last + 1)
        val d = DATE.find(rest)
        val t = if (d != null) TIME.find(rest.substring(d.range.last + 1)) else null
        val near = d != null && d.range.first < 12
        return buildString {
            append(n.groupValues[1])
            if (d != null && near) {
                append(" - ").append(d.value.replace('.', '/').replace('-', '/'))
                if (t != null && t.range.first < 4) append(" ").append(t.value)
            }
        }
    }

    private fun informacoes(p: Page): String {
        val l = p.find(listOf("INFORMACOESCOMPLEMENTARES", "INFORMACOESADICIONAIS", "INFCOMPLEMENTARES")) ?: return ""
        val fisco = p.find(listOf("RESERVADOAOFISCO"), l.base - 12, l.base + 12)
        val maxX = if (fisco != null && fisco.x > l.right) fisco.x - 2f else p.width
        val sel = ArrayList<Line>()
        var lastBase = l.base
        for (line in p.lines) {
            if (line.base <= l.base + 1) continue
            val ws = line.words.filter { it.x < maxX && it.x >= l.x - 8 }
            if (ws.isEmpty()) continue
            val k = key(ws.joinToString(" ") { it.text })
            if (k.startsWith("GERADOPOR") || k.startsWith("POWEREDBY") || k.startsWith("IMPRESSOEM") ||
                k.startsWith("DATAEHORADAIMPRESSAO") || k.startsWith("PAGINA")
            ) break
            if (line.base - lastBase > 45f) break
            lastBase = line.base
            sel.add(Line(line.page, line.base, ws))
        }
        return sel.joinToString(" ") { it.text }.replace(Regex("\\s+"), " ").trim()
    }

    private fun isNum(s: String) = NUM.matches(s.removePrefix("R$").trim()) && s.any { it.isDigit() }

    private fun itensDaPagina(p: Page): List<Map<String, String>> {
        // cabeçalho da tabela: linha com DESCRIÇÃO e NCM
        val header = p.lines.firstOrNull { l ->
            l.words.any { it.norm.startsWith("DESCRICAO") || it.norm == "DESCR" || it.norm.startsWith("DISCRIMINACAO") } &&
                l.words.any { it.norm.startsWith("NCM") || it.norm == "CFOP" || it.norm.startsWith("QTD") || it.norm.startsWith("QUANT") }
        } ?: return emptyList()
        val endY = p.top(listOf("CALCULODOISSQN", "DADOSADICIONAIS", "INFORMACOESCOMPLEMENTARES"), header.base + 5)?.base
            ?: p.height
        val rows = p.lines.filter { it.base > header.base + 1.5f && it.base < endY - 1 }
        val out = ArrayList<MutableMap<String, String>>()
        var ncmX = 0f
        var descX = 0f
        var current: MutableMap<String, String>? = null
        for (line in rows) {
            val ws = line.words
            // ignora as palavras do cabeçalho em 2 linhas (ex.: "VALOR / UNIT")
            if (current == null && line.base - header.base < 12f && looksLikeHeader(ws)) continue
            val item = itemRow(ws) ?: itemRowEmpilhado(ws)
            if (item != null) {
                current = item.first
                ncmX = item.second
                descX = item.third
                out.add(current)
                continue
            }
            val cur = current ?: continue
            // leiaute com colunas empilhadas (NT 2026.010): "CFOP 6102 UN" na linha de baixo
            if (cur["un"].isNullOrEmpty()) {
                val ci = ws.indexOfFirst { it.norm == "CFOP" && it.x >= ncmX - 4f }
                val u = ws.getOrNull(ci + 2)
                if (ci >= 0 && u != null && u.text.any { it.isLetter() }) cur["un"] = u.text
            }
            // continuação da descrição (ou do código) do item atual
            var bracket = false
            for (w in ws) {
                if (w.x >= ncmX - 2f) continue
                if (w.norm.isEmpty()) continue
                if (w.text.startsWith("[")) bracket = true
                if (bracket) {
                    if (w.text.endsWith("]")) bracket = false
                    continue
                }
                if (w.right < descX - 2f) {
                    cur["cod"] = (cur["cod"] ?: "") + w.text
                } else {
                    cur["desc"] = ((cur["desc"] ?: "") + " " + w.text).trim()
                }
            }
        }
        return out
    }

    private fun looksLikeHeader(ws: List<Word>): Boolean {
        val k = ws.joinToString("") { it.norm }
        return listOf("UNIT", "TOTAL", "ICMS", "IPI", "ALIQ", "PROD", "SERV").count { k.contains(it) } >= 2
    }

    /** Linha que começa um item: código, descrição, NCM, CST, CFOP, UN, QTD, V. UNIT, V. TOTAL... */
    private fun itemRow(ws: List<Word>): Triple<MutableMap<String, String>, Float, Float>? {
        if (ws.size < 6) return null
        for (k in 1 until ws.size) {
            if (!NCM.matches(ws[k].text)) continue
            // depois do NCM: números (CST/CSOSN, CFOP...) até a unidade
            var j = k + 1
            var cfop = -1
            while (j < ws.size && j <= k + 4 && !ws[j].text.any { it.isLetter() }) {
                if (CFOP.matches(ws[j].text)) cfop = j
                j++
            }
            if (cfop < 0) continue
            var unIdx = cfop + 1
            if (unIdx >= ws.size) continue
            val un: String
            if (ws[unIdx].text.any { it.isLetter() }) {
                un = ws[unIdx].text
                unIdx++
            } else {
                un = ""
            }
            val nums = ws.subList(unIdx, ws.size).map { it.text }.filter { isNum(it) }
            if (nums.size < 3) continue
            val code = if (k >= 2) ws[0].text else ""
            val descStart = if (k >= 2) 1 else 0
            val desc = ws.subList(descStart, k).joinToString(" ") { it.text }
            val m = linkedMapOf(
                "cod" to code,
                "desc" to desc,
                "un" to un,
                "qtd" to fmtQtd(nums[0]),
                "vun" to fmtUnit(nums[1]),
                "vtot" to fmtMoney(nums[2])
            )
            return Triple(m, ws[k].x, ws[descStart].x)
        }
        return null
    }

    /** Leiaute empilhado: código, descrição, "CST" 000, QTD, V. UNIT, V. TOTAL (CFOP/UN na linha de baixo). */
    private fun itemRowEmpilhado(ws: List<Word>): Triple<MutableMap<String, String>, Float, Float>? {
        val k = ws.indexOfFirst { it.norm == "CST" || it.norm == "CSOSN" || it.norm == "CFOP" }
        if (k < 2) return null
        val nums = ArrayList<String>()
        var j = k + 2
        while (j < ws.size && nums.size < 3 && isNum(ws[j].text)) {
            nums.add(ws[j].text); j++
        }
        if (nums.size < 3) return null
        val m = linkedMapOf(
            "cod" to ws[0].text,
            "desc" to ws.subList(1, k).joinToString(" ") { it.text },
            "un" to "",
            "qtd" to fmtQtd(nums[0]),
            "vun" to fmtUnit(nums[1]),
            "vtot" to fmtMoney(nums[2])
        )
        return Triple(m, ws[k].x, ws[1].x)
    }

    // ------------------------------------------------------------------ números

    /** "1.234,5600" / "24.8500" / "15,0000" → valor. */
    fun parseNum(s0: String): Double? {
        val s = s0.replace("R$", "").trim()
        return try {
            if (s.contains(',')) s.replace(".", "").replace(',', '.').toDouble()
            else if (s.contains('.')) {
                val dec = s.substringAfterLast('.')
                if (dec.length == 3 && s.count { it == '.' } >= 1 && !s.startsWith("0.")) s.replace(".", "").toDouble()
                else s.toDouble()
            } else s.toDouble()
        } catch (e: Exception) {
            null
        }
    }

    private fun br(v: Double, minDec: Int, maxDec: Int): String {
        var s = String.format(Locale.forLanguageTag("pt-BR"), "%,.${maxDec}f", v)
        if (maxDec > minDec) {
            while (s.length > 1 && s.endsWith("0") && s.substringAfter(',').length > minDec) s = s.dropLast(1)
            if (s.endsWith(",")) s = s.dropLast(1)
        }
        return s
    }

    fun fmtQtd(s: String) = parseNum(s)?.let { br(it, 0, 4) } ?: s
    fun fmtUnit(s: String) = parseNum(s)?.let { br(it, 2, 4) } ?: s
    fun fmtMoney(s: String) = parseNum(s)?.let { br(it, 2, 2) } ?: s

    /** Valor monetário (texto do DANFE) como número, para saber se é zero. */
    fun isZero(s: String?): Boolean {
        if (s.isNullOrBlank()) return true
        val v = parseNum(s) ?: return false
        return abs(v) < 0.005
    }

    @Suppress("unused")
    private fun clamp(v: Float, a: Float, b: Float) = min(max(v, a), b)
}
