package br.com.leopardo.leopardo_app

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private var systemChannel: MethodChannel? = null
    private var pendingRequest: Map<String, Any>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingRequest = parsePrintRequest(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val req = parsePrintRequest(intent) ?: return
        val ch = systemChannel
        if (ch != null) ch.invokeMethod("onPrintRequest", req) else pendingRequest = req
    }

    /**
     * Pedidos de impressão de outros apps e sites:
     *  - Intent com action "br.com.leopardo.PRINT" e extras "text", "base64" ou "bytes" (ByteArray)
     *  - Link leopardo://print?text=...  ou  leopardo://print?base64=...
     */
    private fun parsePrintRequest(intent: Intent?): Map<String, Any>? {
        if (intent == null) return null
        val out = HashMap<String, Any>()
        if (intent.action == "br.com.leopardo.PRINT") {
            intent.getStringExtra("text")?.let { out["text"] = it }
            intent.getStringExtra("base64")?.let { out["base64"] = it }
            intent.getByteArrayExtra("bytes")?.let { out["bytes"] = it }
            intent.getStringExtra("source")?.let { out["source"] = it }
        } else if (intent.action == Intent.ACTION_VIEW && intent.data?.scheme == "leopardo") {
            val uri: Uri = intent.data!!
            try {
                uri.getQueryParameter("text")?.let { out["text"] = it }
                uri.getQueryParameter("base64")?.let { out["base64"] = it }
            } catch (e: Exception) {
            }
            // Formato curto: leopardo:base64,AAAA...
            val ssp = uri.schemeSpecificPart ?: ""
            if (out.isEmpty() && ssp.startsWith("base64,")) out["base64"] = ssp.removePrefix("base64,")
            out["source"] = "link"
        }
        return if (out.isEmpty()) null else out
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        systemChannel = MethodChannel(messenger, "leopardo/system").also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    // Abre Configurações › Impressão para ativar o serviço "Leopardo".
                    "openPrintSettings" -> {
                        try {
                            startActivity(
                                Intent(Settings.ACTION_PRINT_SETTINGS)
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "takePrintRequest" -> {
                        result.success(pendingRequest)
                        pendingRequest = null
                    }
                    else -> result.notImplemented()
                }
            }
        }

        MethodChannel(messenger, "leopardo/printer").setMethodCallHandler { call, result ->
            fun ok(v: Any?) = main.post { result.success(v) }
            fun fail(e: Exception) = main.post { result.error("PRINTER", e.message ?: "Erro", null) }
            when (call.method) {
                "bondedDevices" -> worker.execute {
                    try {
                        ok(NativePrinters.bondedDevices(this))
                    } catch (e: Exception) {
                        fail(e)
                    }
                }
                "usbDevices" -> worker.execute {
                    try {
                        ok(NativePrinters.usbDevices(this))
                    } catch (e: Exception) {
                        fail(e)
                    }
                }
                "connect" -> {
                    val id = call.argument<String>("id") ?: ""
                    if (id.startsWith("usb:")) {
                        NativePrinters.connectUsb(this, id.removePrefix("usb:")) { err ->
                            main.post {
                                if (err == null) result.success(true)
                                else result.error("PRINTER", err, null)
                            }
                        }
                    } else {
                        worker.execute {
                            try {
                                NativePrinters.connectClassic(this, id.removePrefix("classic:"))
                                ok(true)
                            } catch (e: Exception) {
                                fail(e)
                            }
                        }
                    }
                }
                "write" -> {
                    val bytes = call.argument<ByteArray>("bytes") ?: ByteArray(0)
                    val flow = FlowControl(
                        statusCheck = call.argument<Boolean>("statusCheck") ?: false,
                        packetDelayMs = call.argument<Int>("packetDelay") ?: 10,
                        disconnectWaitSec = 0
                    )
                    worker.execute {
                        try {
                            NativePrinters.write(bytes, flow)
                            ok(true)
                        } catch (e: Exception) {
                            fail(e)
                        }
                    }
                }
                "disconnect" -> worker.execute {
                    NativePrinters.disconnect()
                    ok(true)
                }
                "connectedId" -> result.success(NativePrinters.connectedId)
                else -> result.notImplemented()
            }
        }
    }
}
