package br.com.leopardo.leopardo_app

import android.content.Context

/**
 * Controle de fluxo configurado no app (Ajustes › Controle de fluxo).
 *  - statusCheck: envia o comando de status (DLE EOT 1) ao final e espera a resposta,
 *    garantindo que a impressora processou tudo antes de seguir.
 *  - packetDelayMs: pausa entre pacotes para não estourar o buffer da impressora.
 *  - disconnectWaitSec: espera antes de desconectar (quando o fim do documento não sai).
 */
data class FlowControl(
    val statusCheck: Boolean = false,
    val packetDelayMs: Int = 10,
    val disconnectWaitSec: Int = 1
) {
    companion object {
        val STATUS_REQUEST = byteArrayOf(0x10, 0x04, 0x01) // DLE EOT 1

        fun fromPrefs(context: Context): FlowControl {
            val p = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            fun long(k: String, d: Long) = try { p.getLong(k, d) } catch (e: Exception) { d }
            val status = try { p.getBoolean("flutter.statusCheck", false) } catch (e: Exception) { false }
            return FlowControl(
                statusCheck = status,
                packetDelayMs = long("flutter.packetDelay", 10L).toInt().coerceIn(0, 1000),
                disconnectWaitSec = long("flutter.disconnectWait", 1L).toInt().coerceIn(0, 30)
            )
        }
    }
}
