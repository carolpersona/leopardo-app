package br.com.leopardo.leopardo_app

import android.content.Context

/**
 * Controle de fluxo configurado no app (Ajustes › Controle de fluxo).
 *  - statusCheck: envia o comando de status (DLE EOT 1) ao final e espera a resposta,
 *    garantindo que a impressora processou tudo antes de seguir.
 *  - packetDelayMs: pausa entre pacotes para não estourar o buffer da impressora.
 *  - disconnectWaitSec: espera antes de desconectar (quando o fim do documento não sai).
 *  - speedMmS: velocidade de impressão (mm/s). O envio não passa da velocidade com que a
 *    impressora consegue imprimir; assim o buffer não enche e o fim do documento não se perde.
 *    0 = sem limite.
 */
data class FlowControl(
    val statusCheck: Boolean = false,
    val packetDelayMs: Int = 10,
    val disconnectWaitSec: Int = 1,
    val speedMmS: Int = 50,
    val paperMm: Int = 58
) {
    /** Bytes por segundo que a impressora consome (imagem: 8 linhas por mm). */
    fun bytesPerSecond(): Double {
        if (speedMmS <= 0) return 0.0
        val bytesPerLine = if (paperMm == 80) 72 else 48
        return speedMmS * 8.0 * bytesPerLine
    }

    /** Ritmo do envio: libera um "adiantamento" inicial e depois segue a velocidade da impressora. */
    class Pacer(flow: FlowControl) {
        private val rate = flow.bytesPerSecond()
        private val start = System.nanoTime()
        private var sent = 0L

        fun before(n: Int) {
            if (rate <= 0) return
            val allowed = BURST + rate * (System.nanoTime() - start) / 1e9
            val over = sent + n - allowed
            if (over > 0) Thread.sleep(maxOf(1L, (over / rate * 1000).toLong()))
            sent += n
        }

        companion object {
            const val BURST = 4096
        }
    }

    companion object {
        val STATUS_REQUEST = byteArrayOf(0x10, 0x04, 0x01) // DLE EOT 1

        fun fromPrefs(context: Context): FlowControl {
            val p = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            fun long(k: String, d: Long) = try { p.getLong(k, d) } catch (e: Exception) { d }
            val status = try { p.getBoolean("flutter.statusCheck", false) } catch (e: Exception) { false }
            return FlowControl(
                statusCheck = status,
                packetDelayMs = long("flutter.packetDelay", 10L).toInt().coerceIn(0, 1000),
                disconnectWaitSec = long("flutter.disconnectWait", 1L).toInt().coerceIn(0, 30),
                speedMmS = long("flutter.printSpeed", 50L).toInt().coerceIn(0, 300),
                paperMm = long("flutter.paperMm", 58L).toInt()
            )
        }
    }
}
