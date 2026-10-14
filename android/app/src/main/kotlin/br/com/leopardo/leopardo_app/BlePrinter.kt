package br.com.leopardo.leopardo_app

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.os.Build
import java.util.Locale
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Envio de bytes ESC/POS para a impressora por Bluetooth Low Energy.
 * Usado pelo serviço de impressão do Android (fora do Flutter).
 * Chamar sempre fora da thread principal.
 */
@SuppressLint("MissingPermission")
class BlePrinter(private val context: Context, private val address: String) {

    companion object {
        // Mesmos serviços preferidos do app (lib/services/printer_service.dart).
        private val PREFERRED = listOf(
            "000018f0", "0000ff00", "0000ffe0",
            "e7810a71-73ae-499d-8c15-faa9aef0c3f2",
            "49535343-fe7d-4ae5-8fa9-9fafd205e455"
        )
        private val GENERIC = listOf("00001800", "00001801", "0000180a", "0000180f")
    }

    private var gatt: BluetoothGatt? = null
    private var writer: BluetoothGattCharacteristic? = null
    private var notifier: BluetoothGattCharacteristic? = null
    private var statusLatch = CountDownLatch(1)
    private var descriptorLatch = CountDownLatch(1)
    private var mtu = 23

    @Volatile private var connected = false
    private var connectLatch = CountDownLatch(1)
    private var servicesLatch = CountDownLatch(1)
    private var mtuLatch = CountDownLatch(1)
    private var writeLatch = CountDownLatch(1)

    private val callback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                connected = true
                connectLatch.countDown()
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                connected = false
                connectLatch.countDown()
                servicesLatch.countDown()
                mtuLatch.countDown()
                writeLatch.countDown()
            }
        }

        override fun onMtuChanged(g: BluetoothGatt, newMtu: Int, status: Int) {
            if (status == BluetoothGatt.GATT_SUCCESS) mtu = newMtu
            mtuLatch.countDown()
        }

        override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
            servicesLatch.countDown()
        }

        @Deprecated("API antiga mantida para Android < 13")
        override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic) {
            statusLatch.countDown()
        }

        override fun onDescriptorWrite(g: BluetoothGatt, d: BluetoothGattDescriptor, status: Int) {
            descriptorLatch.countDown()
        }

        @Deprecated("API antiga mantida para Android < 13")
        override fun onCharacteristicWrite(
            g: BluetoothGatt, c: BluetoothGattCharacteristic, status: Int
        ) {
            writeLatch.countDown()
        }
    }

    /** Conecta, descobre o canal de escrita e envia os dados. Lança exceção com mensagem em português. */
    fun send(data: ByteArray, flow: FlowControl, isCancelled: () -> Boolean) {
        val manager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        val adapter = manager.adapter ?: throw IllegalStateException("Bluetooth indisponível neste aparelho")
        if (!adapter.isEnabled) throw IllegalStateException("Ative o Bluetooth do celular")
        val device = adapter.getRemoteDevice(address)
        try {
            connect(device)
            if (flow.statusCheck) enableNotifications()
            transmit(data, flow.packetDelayMs, isCancelled, FlowControl.Pacer(flow))
            if (flow.statusCheck) waitStatus(flow.packetDelayMs)
            // Dá tempo para a impressora receber o fim do buffer antes de desconectar.
            if (flow.disconnectWaitSec > 0) Thread.sleep(flow.disconnectWaitSec * 1000L)
        } finally {
            close()
        }
    }

    private fun connect(device: BluetoothDevice) {
        connectLatch = CountDownLatch(1)
        gatt = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            device.connectGatt(context, false, callback, BluetoothDevice.TRANSPORT_LE)
        } else {
            device.connectGatt(context, false, callback)
        }
        val g = gatt ?: throw IllegalStateException("Não foi possível conectar à impressora")
        if (!connectLatch.await(15, TimeUnit.SECONDS) || !connected) {
            throw IllegalStateException("A impressora não respondeu. Verifique se está ligada e por perto.")
        }
        mtuLatch = CountDownLatch(1)
        if (g.requestMtu(247)) mtuLatch.await(4, TimeUnit.SECONDS)
        servicesLatch = CountDownLatch(1)
        g.discoverServices()
        servicesLatch.await(10, TimeUnit.SECONDS)
        writer = pickWriter(g) ?: throw IllegalStateException("Impressora sem canal de impressão compatível")
        // Canal de resposta (status) no mesmo serviço do canal de escrita.
        val notifyMask = BluetoothGattCharacteristic.PROPERTY_NOTIFY or BluetoothGattCharacteristic.PROPERTY_INDICATE
        notifier = writer?.service?.characteristics?.firstOrNull { (it.properties and notifyMask) != 0 }
    }

    @Suppress("DEPRECATION")
    private fun enableNotifications() {
        val g = gatt ?: return
        val n = notifier ?: return
        try {
            g.setCharacteristicNotification(n, true)
            val cccd = n.getDescriptor(java.util.UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")) ?: return
            cccd.value = if ((n.properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY) != 0)
                BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
            else BluetoothGattDescriptor.ENABLE_INDICATION_VALUE
            descriptorLatch = CountDownLatch(1)
            if (g.writeDescriptor(cccd)) descriptorLatch.await(3, TimeUnit.SECONDS)
        } catch (e: Exception) {
        }
    }

    /** Envia DLE EOT 1 e espera a impressora responder (até 5 s). */
    private fun waitStatus(delayMs: Int) {
        statusLatch = CountDownLatch(1)
        transmit(FlowControl.STATUS_REQUEST, delayMs) { false }
        if (notifier != null) statusLatch.await(5, TimeUnit.SECONDS)
    }

    private fun writable(c: BluetoothGattCharacteristic): Boolean {
        val p = c.properties
        return (p and BluetoothGattCharacteristic.PROPERTY_WRITE) != 0 ||
            (p and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE) != 0
    }

    private fun pickWriter(g: BluetoothGatt): BluetoothGattCharacteristic? {
        val services = g.services ?: return null
        for (pref in PREFERRED) {
            for (s in services) {
                if (s.uuid.toString().lowercase(Locale.ROOT).startsWith(pref)) {
                    s.characteristics.firstOrNull { writable(it) }?.let { return it }
                }
            }
        }
        for (s in services) {
            val id = s.uuid.toString().lowercase(Locale.ROOT)
            if (GENERIC.any { id.startsWith(it) }) continue
            s.characteristics.firstOrNull { writable(it) }?.let { return it }
        }
        return null
    }

    @Suppress("DEPRECATION")
    private fun transmit(data: ByteArray, delayMs: Int, isCancelled: () -> Boolean, pacer: FlowControl.Pacer? = null) {
        val g = gatt ?: return
        val c = writer ?: return
        val noResponse = (c.properties and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE) != 0
        c.writeType = if (noResponse) BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
        else BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        val chunk = maxOf(20, minOf(mtu - 3, if (noResponse) 180 else 240))
        var i = 0
        while (i < data.size) {
            if (isCancelled()) throw InterruptedException("Impressão cancelada")
            if (!connected) throw IllegalStateException("A impressora desconectou durante a impressão")
            val end = minOf(i + chunk, data.size)
            val part = data.copyOfRange(i, end)
            pacer?.before(part.size)
            var ok = false
            for (attempt in 0 until 20) {
                writeLatch = CountDownLatch(1)
                c.value = part
                if (g.writeCharacteristic(c)) {
                    ok = true
                    break
                }
                Thread.sleep(20) // pilha Bluetooth ocupada: tenta de novo
            }
            if (!ok) throw IllegalStateException("Falha ao enviar dados para a impressora")
            writeLatch.await(3, TimeUnit.SECONDS)
            if (delayMs > 0) Thread.sleep(delayMs.toLong())
            i = end
        }
    }

    private fun close() {
        try {
            gatt?.disconnect()
        } catch (e: Exception) {
        }
        try {
            gatt?.close()
        } catch (e: Exception) {
        }
        gatt = null
    }
}
