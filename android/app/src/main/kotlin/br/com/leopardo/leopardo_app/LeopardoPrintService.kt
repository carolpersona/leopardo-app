package br.com.leopardo.leopardo_app

import android.annotation.SuppressLint
import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.print.PrintAttributes
import android.print.PrinterCapabilitiesInfo
import android.print.PrinterId
import android.print.PrinterInfo
import android.printservice.PrintJob
import android.printservice.PrintService
import android.printservice.PrinterDiscoverySession
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.Locale

/**
 * Faz as impressoras Leopardo aparecerem na tela "Imprimir" do Android
 * (PDF, navegador, galeria, documentos...). Precisa ser ativado uma vez em
 * Configurações › Impressão › Leopardo.
 */
@SuppressLint("MissingPermission")
class LeopardoPrintService : PrintService() {

    private val main = Handler(Looper.getMainLooper())
    private val cancelled = HashSet<String>()

    // Preferências gravadas pelo app Flutter (pacote shared_preferences).
    private fun prefs() = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

    private fun paperMm(): Int = try {
        prefs().getLong("flutter.paperMm", 58L).toInt()
    } catch (e: Exception) {
        58
    }

    private fun paperDots(mm: Int) = if (mm == 80) 576 else 384

    /** Comandos configurados no app (Ajustes › Comandos da impressora). */
    private fun jobOptions(): ThermalRaster.JobOptions {
        val p = prefs()
        fun long(k: String, d: Long) = try { p.getLong(k, d) } catch (e: Exception) { d }
        fun bool(k: String) = try { p.getBoolean(k, false) } catch (e: Exception) { false }
        return ThermalRaster.JobOptions(
            feedLines = long("flutter.feedLines", 4L).toInt(),
            cut = bool("flutter.autoCut"),
            drawer = bool("flutter.openDrawer"),
            darkness = long("flutter.darkness", 1L).toInt()
        )
    }

    /** Impressoras pareadas por Bluetooth clássico com "Leopardo" no nome. */
    private fun bondedLeopardo(): Map<String, String> = try {
        NativePrinters.bondedDevices(this)
            .filter { (it["name"] as String).lowercase(Locale.ROOT).contains("leopardo") }
            .associate { (it["id"] as String) to (it["name"] as String) }
    } catch (e: Exception) {
        emptyMap()
    }

    /** Impressoras já conectadas pelo app: endereço -> nome. */
    private fun knownPrinters(): Map<String, String> {
        val out = LinkedHashMap<String, String>()
        try {
            val json = prefs().getString("flutter.knownPrinters", null)
            if (json != null) {
                val o = JSONObject(json)
                for (k in o.keys()) out[k] = o.optString(k, k)
            }
            val last = prefs().getString("flutter.lastPrinterId", "") ?: ""
            if (last.isNotEmpty() && !out.containsKey(last)) {
                out[last] = prefs().getString("flutter.lastPrinterName", "") ?: last
            }
        } catch (e: Exception) {
        }
        return out
    }

    private val roll58 = PrintAttributes.MediaSize("leo_roll_58", "Bobina 58 mm", 2283, 11693)
    private val roll80 = PrintAttributes.MediaSize("leo_roll_80", "Bobina 80 mm", 3150, 11693)

    private fun buildPrinter(address: String, name: String): PrinterInfo {
        val id = generatePrinterId(address)
        val mm = paperMm()
        val caps = PrinterCapabilitiesInfo.Builder(id)
            .addMediaSize(roll58, mm != 80)
            .addMediaSize(roll80, mm == 80)
            .addMediaSize(PrintAttributes.MediaSize.ISO_A4, false)
            .addMediaSize(PrintAttributes.MediaSize.NA_LETTER, false)
            .addResolution(PrintAttributes.Resolution("r203", "203 dpi", 203, 203), true)
            .setColorModes(
                PrintAttributes.COLOR_MODE_MONOCHROME,
                PrintAttributes.COLOR_MODE_MONOCHROME
            )
            .setMinMargins(PrintAttributes.Margins.NO_MARGINS)
            .build()
        return PrinterInfo.Builder(id, name.ifEmpty { "Leopardo" }, PrinterInfo.STATUS_IDLE)
            .setDescription("Impressora térmica Leopardo")
            .setCapabilities(caps)
            .build()
    }

    override fun onCreatePrinterDiscoverySession(): PrinterDiscoverySession = Discovery()

    inner class Discovery : PrinterDiscoverySession() {
        private val found = HashMap<String, String>()
        private var scanning = false

        private val scanCallback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                val name = try {
                    result.scanRecord?.deviceName ?: result.device.name
                } catch (e: SecurityException) {
                    null
                } ?: return
                if (!name.lowercase(Locale.ROOT).contains("leopardo")) return
                val address = result.device.address
                if (found.containsKey(address)) return
                found[address] = name
                main.post { publish(address, name) }
            }
        }

        private fun publish(address: String, name: String) {
            if (isDestroyed) return
            try {
                addPrinters(listOf(buildPrinter(address, name)))
            } catch (e: Exception) {
            }
        }

        override fun onStartPrinterDiscovery(priorityList: List<PrinterId>) {
            val list = (bondedLeopardo() + knownPrinters()).map { (addr, name) ->
                found[addr] = name
                buildPrinter(addr, name)
            }
            if (list.isNotEmpty()) addPrinters(list)
            startScan()
        }

        private fun startScan() {
            if (scanning) return
            try {
                val bm = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
                val scanner = bm.adapter?.bluetoothLeScanner ?: return
                scanner.startScan(scanCallback)
                scanning = true
                main.postDelayed({ stopScan() }, 12000)
            } catch (e: Exception) {
                // Sem permissão de Bluetooth: só as impressoras já salvas aparecem.
            }
        }

        private fun stopScan() {
            if (!scanning) return
            scanning = false
            try {
                val bm = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
                bm.adapter?.bluetoothLeScanner?.stopScan(scanCallback)
            } catch (e: Exception) {
            }
        }

        override fun onStopPrinterDiscovery() = stopScan()

        override fun onValidatePrinters(printerIds: List<PrinterId>) {
            val known = bondedLeopardo() + knownPrinters()
            val list = printerIds.mapNotNull { id ->
                val name = found[id.localId] ?: known[id.localId]
                if (name != null) buildPrinter(id.localId, name) else null
            }
            if (list.isNotEmpty()) addPrinters(list)
        }

        override fun onStartPrinterStateTracking(printerId: PrinterId) {
            val name = found[printerId.localId] ?: knownPrinters()[printerId.localId] ?: "Leopardo"
            addPrinters(listOf(buildPrinter(printerId.localId, name)))
        }

        override fun onStopPrinterStateTracking(printerId: PrinterId) {}

        override fun onDestroy() = stopScan()
    }

    override fun onRequestCancelPrintJob(printJob: PrintJob) {
        printJob.id?.let { synchronized(cancelled) { cancelled.add(it.toString()) } }
        printJob.cancel()
    }

    override fun onPrintJobQueued(printJob: PrintJob) {
        val address = printJob.info.printerId?.localId
        val data = printJob.document.data
        if (address == null || data == null) {
            printJob.fail("Documento ou impressora inválidos")
            return
        }
        printJob.start()
        val jobKey = printJob.id?.toString() ?: ""
        val isCancelled = { synchronized(cancelled) { cancelled.contains(jobKey) } }
        val tmp = File(cacheDir, "print_${System.currentTimeMillis()}.pdf")
        val dots = paperDots(paperMm())
        val options = jobOptions()

        // A leitura do documento é feita logo, enquanto o descritor está válido.
        try {
            FileInputStream(data.fileDescriptor).use { input ->
                FileOutputStream(tmp).use { output -> input.copyTo(output) }
            }
            data.close()
        } catch (e: Exception) {
            printJob.fail("Não foi possível ler o documento")
            return
        }

        Thread {
            var error: String? = null
            try {
                val bytes = ThermalRaster.pdfToEscPos(tmp, dots, options, isCancelled)
                if (address.startsWith("classic:") || address.startsWith("usb:")) {
                    NativePrinters.sendOnce(this, address, bytes)
                } else {
                    BlePrinter(this, address).send(bytes, isCancelled)
                }
            } catch (e: InterruptedException) {
                error = null
            } catch (e: Exception) {
                error = e.message ?: "Falha ao imprimir"
            } finally {
                tmp.delete()
            }
            val err = error
            main.post {
                when {
                    isCancelled() -> if (!printJob.isCancelled) printJob.cancel()
                    err != null -> printJob.fail(err)
                    else -> printJob.complete()
                }
                synchronized(cancelled) { cancelled.remove(jobKey) }
            }
        }.start()
    }
}
