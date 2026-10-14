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

    /**
     * Abre a conversa com [phone] no WhatsApp (ou WhatsApp Business) já com o texto
     * e a imagem anexada. Sem WhatsApp instalado, usa o link wa.me (só texto).
     */
    private fun shareWhatsApp(phone: String, text: String, imagePath: String?): Boolean {
        var uri: Uri? = null
        if (!imagePath.isNullOrEmpty()) {
            try {
                val src = java.io.File(imagePath)
                val dir = java.io.File(cacheDir, "compartilhar").apply { mkdirs() }
                val dst = java.io.File(dir, "anexo_${System.currentTimeMillis()}.${src.extension.ifEmpty { "jpg" }}")
                src.copyTo(dst, overwrite = true)
                uri = androidx.core.content.FileProvider.getUriForFile(this, "$packageName.leopardo.files", dst)
            } catch (e: Exception) {
                uri = null
            }
        }
        for (pkg in listOf("com.whatsapp", "com.whatsapp.w4b")) {
            try {
                val i = Intent(Intent.ACTION_SEND).apply {
                    setPackage(pkg)
                    putExtra("jid", "$phone@s.whatsapp.net")
                    putExtra(Intent.EXTRA_TEXT, text)
                    if (uri != null) {
                        type = "image/*"
                        putExtra(Intent.EXTRA_STREAM, uri)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    } else {
                        type = "text/plain"
                    }
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(i)
                return true
            } catch (e: Exception) {
                // tenta o próximo
            }
        }
        return try {
            startActivity(
                Intent(Intent.ACTION_VIEW, Uri.parse("https://wa.me/$phone?text=" + Uri.encode(text)))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            true
        } catch (e: Exception) {
            false
        }
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
                    "analyzeBoleto" -> {
                        val path = call.argument<String>("path") ?: ""
                        worker.execute {
                            try {
                                val r = BoletoAnalyzer.analyze(this, path)
                                main.post { result.success(r) }
                            } catch (e: Exception) {
                                main.post { result.error("BOLETO", e.message ?: "Erro ao ler o PDF", null) }
                            }
                        }
                    }
                    // Abre link externo (WhatsApp da Leopardo, loja etc.)
                    "openUrl" -> {
                        try {
                            val url = call.argument<String>("url") ?: ""
                            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    // Envia texto (e foto, se houver) direto para o WhatsApp da Leopardo
                    "shareWhatsApp" -> {
                        val phone = call.argument<String>("phone") ?: ""
                        val text = call.argument<String>("text") ?: ""
                        val image = call.argument<String>("image")
                        result.success(shareWhatsApp(phone, text, image))
                    }
                    // Pasta interna do app (histórico de impressões)
                    "filesDir" -> result.success(filesDir.absolutePath)
                    // Dados do aparelho para o relatório de diagnóstico
                    "deviceInfo" -> {
                        val versionName = try {
                            packageManager.getPackageInfo(packageName, 0).versionName ?: ""
                        } catch (e: Exception) {
                            ""
                        }
                        result.success(
                            mapOf(
                                "manufacturer" to android.os.Build.MANUFACTURER,
                                "model" to android.os.Build.MODEL,
                                "android" to android.os.Build.VERSION.RELEASE,
                                "sdk" to android.os.Build.VERSION.SDK_INT,
                                "appVersion" to versionName
                            )
                        )
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
