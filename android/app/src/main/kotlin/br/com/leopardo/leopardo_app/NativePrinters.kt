package br.com.leopardo.leopardo_app

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.bluetooth.BluetoothClass
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.os.Build
import java.io.OutputStream
import java.util.UUID

/**
 * Conexões que o Flutter não tem pronto: Bluetooth clássico (SPP/RFCOMM) e USB.
 * Os identificadores usados pelo app são "classic:<MAC>" e "usb:<nome do dispositivo>".
 * Uma única conexão aberta por vez, compartilhada com o serviço de impressão do Android.
 */
@SuppressLint("MissingPermission")
object NativePrinters {
    private val SPP: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    const val USB_PERMISSION = "br.com.leopardo.leopardo_app.USB_PERMISSION"

    private var classicSocket: BluetoothSocket? = null
    private var classicOut: OutputStream? = null
    private var usbConn: UsbDeviceConnection? = null
    private var usbIface: UsbInterface? = null
    private var usbOut: UsbEndpoint? = null

    @Volatile var connectedId: String? = null
        private set

    // ---------- Bluetooth clássico ----------

    /** Dispositivos pareados no Android (Configurações › Bluetooth). */
    fun bondedDevices(context: Context): List<Map<String, Any>> {
        val bm = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        val adapter = bm.adapter ?: return emptyList()
        val out = ArrayList<Map<String, Any>>()
        for (d in adapter.bondedDevices ?: emptySet()) {
            val type = d.type
            if (type == android.bluetooth.BluetoothDevice.DEVICE_TYPE_LE) continue
            val major = d.bluetoothClass?.majorDeviceClass ?: 0
            val name = d.name ?: d.address
            val looksPrinter = major == BluetoothClass.Device.Major.IMAGING ||
                Regex("(?i)leopardo|print|pos|pt-|mpt|thermal|58|80").containsMatchIn(name)
            out.add(mapOf("id" to "classic:${d.address}", "name" to name, "printer" to looksPrinter))
        }
        return out.sortedByDescending { it["printer"] as Boolean }
    }

    @Synchronized
    fun connectClassic(context: Context, address: String) {
        disconnect()
        val bm = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        val adapter = bm.adapter ?: throw IllegalStateException("Bluetooth indisponível")
        if (!adapter.isEnabled) throw IllegalStateException("Ative o Bluetooth do celular")
        try {
            adapter.cancelDiscovery()
        } catch (e: Exception) {
        }
        val device = adapter.getRemoteDevice(address)
        var socket: BluetoothSocket? = null
        try {
            socket = device.createRfcommSocketToServiceRecord(SPP)
            socket.connect()
        } catch (first: Exception) {
            try {
                socket?.close()
            } catch (e: Exception) {
            }
            // Algumas impressoras só aceitam conexão "insegura".
            socket = device.createInsecureRfcommSocketToServiceRecord(SPP)
            try {
                socket.connect()
            } catch (e: Exception) {
                try {
                    socket.close()
                } catch (x: Exception) {
                }
                throw IllegalStateException("Não foi possível conectar. A impressora está ligada e pareada?")
            }
        }
        classicSocket = socket
        classicOut = socket!!.outputStream
        connectedId = "classic:$address"
    }

    // ---------- USB ----------

    private fun bulkOut(device: UsbDevice): Pair<UsbInterface, UsbEndpoint>? {
        var fallback: Pair<UsbInterface, UsbEndpoint>? = null
        for (i in 0 until device.interfaceCount) {
            val iface = device.getInterface(i)
            for (e in 0 until iface.endpointCount) {
                val ep = iface.getEndpoint(e)
                if (ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK && ep.direction == UsbConstants.USB_DIR_OUT) {
                    if (iface.interfaceClass == UsbConstants.USB_CLASS_PRINTER) return Pair(iface, ep)
                    if (fallback == null) fallback = Pair(iface, ep)
                }
            }
        }
        return fallback
    }

    fun usbDevices(context: Context): List<Map<String, Any>> {
        val um = context.getSystemService(Context.USB_SERVICE) as UsbManager
        val out = ArrayList<Map<String, Any>>()
        for (d in um.deviceList.values) {
            val io = bulkOut(d) ?: continue
            val name = (if (Build.VERSION.SDK_INT >= 21) d.productName else null)
                ?: "USB ${d.vendorId}:${d.productId}"
            out.add(
                mapOf(
                    "id" to "usb:${d.deviceName}",
                    "name" to name,
                    "printer" to (io.first.interfaceClass == UsbConstants.USB_CLASS_PRINTER)
                )
            )
        }
        return out
    }

    /** Pede permissão de USB (se preciso) e conecta. [done] recebe null em caso de sucesso ou a mensagem de erro. */
    fun connectUsb(context: Context, deviceName: String, done: (String?) -> Unit) {
        val um = context.getSystemService(Context.USB_SERVICE) as UsbManager
        val device = um.deviceList[deviceName]
        if (device == null) {
            done("Impressora USB não encontrada. Confira o cabo.")
            return
        }
        if (um.hasPermission(device)) {
            done(openUsb(um, device))
            return
        }
        val app = context.applicationContext
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(c: Context, intent: Intent) {
                try {
                    app.unregisterReceiver(this)
                } catch (e: Exception) {
                }
                val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                done(if (granted) openUsb(um, device) else "Permissão de USB negada")
            }
        }
        val filter = IntentFilter(USB_PERMISSION)
        if (Build.VERSION.SDK_INT >= 33) {
            app.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            app.registerReceiver(receiver, filter)
        }
        val flags = if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0
        val pi = PendingIntent.getBroadcast(app, 0, Intent(USB_PERMISSION).setPackage(app.packageName), flags)
        um.requestPermission(device, pi)
    }

    @Synchronized
    private fun openUsb(um: UsbManager, device: UsbDevice): String? {
        disconnect()
        val io = bulkOut(device) ?: return "Dispositivo USB sem saída de impressão"
        val conn = um.openDevice(device) ?: return "Não foi possível abrir o dispositivo USB"
        if (!conn.claimInterface(io.first, true)) {
            conn.close()
            return "O dispositivo USB está em uso por outro app"
        }
        usbConn = conn
        usbIface = io.first
        usbOut = io.second
        connectedId = "usb:${device.deviceName}"
        return null
    }

    // ---------- Comum ----------

    @Synchronized
    fun write(data: ByteArray) {
        val out = classicOut
        val conn = usbConn
        val ep = usbOut
        when {
            out != null -> {
                try {
                    var i = 0
                    while (i < data.size) {
                        val n = minOf(1024, data.size - i)
                        out.write(data, i, n)
                        out.flush()
                        i += n
                        Thread.sleep(5)
                    }
                } catch (e: Exception) {
                    disconnect()
                    throw IllegalStateException("A impressora desconectou")
                }
            }
            conn != null && ep != null -> {
                var i = 0
                while (i < data.size) {
                    val n = minOf(16384, data.size - i)
                    val chunk = data.copyOfRange(i, i + n)
                    val sent = conn.bulkTransfer(ep, chunk, n, 5000)
                    if (sent < 0) {
                        disconnect()
                        throw IllegalStateException("Falha ao enviar pela USB")
                    }
                    i += n
                }
            }
            else -> throw IllegalStateException("Impressora não conectada")
        }
    }

    @Synchronized
    fun disconnect() {
        try {
            classicOut?.close()
        } catch (e: Exception) {
        }
        try {
            classicSocket?.close()
        } catch (e: Exception) {
        }
        try {
            usbIface?.let { usbConn?.releaseInterface(it) }
            usbConn?.close()
        } catch (e: Exception) {
        }
        classicSocket = null
        classicOut = null
        usbConn = null
        usbIface = null
        usbOut = null
        connectedId = null
    }

    /**
     * Envio avulso usado pelo serviço de impressão do Android: reaproveita a conexão
     * do app se for a mesma impressora; senão abre, envia e fecha.
     */
    fun sendOnce(context: Context, id: String, data: ByteArray) {
        if (connectedId == id) {
            write(data)
            return
        }
        when {
            id.startsWith("classic:") -> {
                connectClassic(context, id.removePrefix("classic:"))
                try {
                    write(data)
                    Thread.sleep(800)
                } finally {
                    disconnect()
                }
            }
            id.startsWith("usb:") -> {
                val um = context.getSystemService(Context.USB_SERVICE) as UsbManager
                val device = um.deviceList[id.removePrefix("usb:")]
                    ?: throw IllegalStateException("Impressora USB não encontrada")
                if (!um.hasPermission(device)) {
                    throw IllegalStateException("Abra o app Leopardo e conecte a impressora USB uma vez")
                }
                val err = openUsb(um, device)
                if (err != null) throw IllegalStateException(err)
                try {
                    write(data)
                } finally {
                    disconnect()
                }
            }
            else -> throw IllegalStateException("Tipo de impressora desconhecido")
        }
    }
}
