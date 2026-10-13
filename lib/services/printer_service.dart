import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'escpos.dart';
import 'native_printers.dart';
import 'raster.dart';
import 'settings.dart';

/// Conexão com a impressora (BLE pelo Flutter; Bluetooth clássico e USB pelo
/// código Android) e envio dos comandos ESC/POS.
class PrinterService extends ChangeNotifier {
  PrinterService._();
  static final PrinterService instance = PrinterService._();

  // Serviços BLE mais comuns em impressoras térmicas portáteis.
  static const _preferredServices = [
    '18f0',
    'ff00',
    'ffe0',
    'e7810a71-73ae-499d-8c15-faa9aef0c3f2',
    '49535343-fe7d-4ae5-8fa9-9fafd205e455',
  ];
  static const _genericServices = ['1800', '1801', '180a', '180f'];

  BluetoothDevice? device;
  BluetoothCharacteristic? _writer;
  int? battery;
  bool connecting = false;
  bool scanning = false;
  bool printing = false;
  List<ScanResult> results = [];
  String? lastError;

  // Bluetooth clássico / USB
  String? nativeId;
  String nativeName = '';
  List<NativePrinterInfo> bonded = [];
  List<NativePrinterInfo> usbDevices = [];

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<bool>? _scanningSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;

  bool get isConnected => nativeId != null || (device != null && _writer != null);

  /// "BLE", "Bluetooth" (clássico) ou "USB".
  String get kindLabel {
    final id = nativeId;
    if (id == null) return 'BLE';
    return id.startsWith('usb:') ? 'USB' : 'Bluetooth';
  }

  String get deviceName {
    if (nativeId != null) return nativeName;
    final d = device;
    if (d == null) return '';
    final n = d.platformName;
    return n.isNotEmpty ? n : d.remoteId.str;
  }

  static String _short(Guid g) {
    final s = g.toString().toLowerCase();
    if (s.length == 36 && s.startsWith('0000') && s.endsWith('-0000-1000-8000-00805f9b34fb')) {
      return s.substring(4, 8);
    }
    return s;
  }

  Future<bool> ensurePermissions() async {
    if (Platform.isAndroid) {
      final r = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ].request();
      // Android 11 ou anterior exige localização para buscar dispositivos BLE.
      await Permission.locationWhenInUse.request();
      final ok = r.values.every((s) => s.isGranted || s.isLimited);
      if (!ok) lastError = 'Permita o acesso a "Dispositivos próximos" para encontrar a impressora.';
      return ok;
    }
    return true;
  }

  Future<bool> ensureBluetoothOn() async {
    if (await FlutterBluePlus.isSupported == false) {
      lastError = 'Este aparelho não tem Bluetooth Low Energy.';
      return false;
    }
    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      if (Platform.isAndroid) {
        try {
          await FlutterBluePlus.turnOn();
        } catch (_) {}
      }
      try {
        await FlutterBluePlus.adapterState
            .where((s) => s == BluetoothAdapterState.on)
            .first
            .timeout(const Duration(seconds: 6));
      } catch (_) {
        lastError = 'Ative o Bluetooth do celular.';
        return false;
      }
    }
    return true;
  }

  Future<void> startScan() async {
    lastError = null;
    if (!await ensurePermissions() || !await ensureBluetoothOn()) {
      notifyListeners();
      return;
    }
    results = [];
    loadNativeDevices();
    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((list) {
      final named = list.where((r) => _nameOf(r).isNotEmpty).toList();
      named.sort((a, b) {
        final la = _nameOf(a).toLowerCase().contains('leopardo') ? 0 : 1;
        final lb = _nameOf(b).toLowerCase().contains('leopardo') ? 0 : 1;
        if (la != lb) return la - lb;
        return b.rssi - a.rssi;
      });
      results = named;
      notifyListeners();
    });
    _scanningSub?.cancel();
    _scanningSub = FlutterBluePlus.isScanning.listen((s) {
      scanning = s;
      notifyListeners();
    });
    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 12));
    } catch (e) {
      lastError = 'Não foi possível buscar impressoras: $e';
      notifyListeners();
    }
  }

  /// Impressoras pareadas (Bluetooth clássico) e conectadas por cabo USB.
  Future<void> loadNativeDevices() async {
    bonded = await NativePrinters.bonded();
    usbDevices = await NativePrinters.usb();
    notifyListeners();
  }

  Future<bool> connectNative(NativePrinterInfo p) async {
    lastError = null;
    connecting = true;
    notifyListeners();
    await stopScan();
    try {
      await disconnect();
      await NativePrinters.connect(p.id);
      nativeId = p.id;
      nativeName = p.name;
      final s = AppSettings.instance;
      s.lastPrinterId = p.id;
      s.lastPrinterName = p.name;
      s.knownPrinters[p.id] = p.name;
      await s.save();
      return true;
    } on PlatformException catch (e) {
      lastError = e.message ?? 'Falha ao conectar';
      return false;
    } catch (e) {
      lastError = 'Falha ao conectar: $e';
      return false;
    } finally {
      connecting = false;
      notifyListeners();
    }
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
  }

  static String _nameOf(ScanResult r) {
    final a = r.advertisementData.advName;
    return a.isNotEmpty ? a : r.device.platformName;
  }

  static String nameOf(ScanResult r) => _nameOf(r);

  static String signalLabel(int rssi) {
    if (rssi >= -60) return 'Sinal forte';
    if (rssi >= -80) return 'Sinal médio';
    return 'Sinal fraco';
  }

  Future<bool> connect(BluetoothDevice d, {String? name}) async {
    lastError = null;
    connecting = true;
    notifyListeners();
    await stopScan();
    try {
      if (nativeId != null || (device != null && device!.remoteId != d.remoteId)) {
        await disconnect();
      }
      await d.connect(timeout: const Duration(seconds: 12), autoConnect: false);
      final services = await d.discoverServices();
      _writer = _pickWriter(services);
      if (_writer == null) {
        await d.disconnect();
        throw 'nenhuma característica de escrita encontrada';
      }
      device = d;
      battery = await _readBattery(services);
      _connSub?.cancel();
      _connSub = d.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) {
          _writer = null;
          battery = null;
          notifyListeners();
        }
      });
      final s = AppSettings.instance;
      s.lastPrinterId = d.remoteId.str;
      final n = name ?? d.platformName;
      if (n.isNotEmpty) s.lastPrinterName = n;
      s.knownPrinters[d.remoteId.str] = n.isNotEmpty ? n : d.remoteId.str;
      await s.save();
      return true;
    } catch (e) {
      lastError = 'Falha ao conectar: $e';
      return false;
    } finally {
      connecting = false;
      notifyListeners();
    }
  }

  /// Reconecta à última impressora usada, sem interação.
  Future<void> reconnectLast() async {
    final s = AppSettings.instance;
    if (!s.autoReconnect || s.lastPrinterId.isEmpty || isConnected) return;
    if (!await ensurePermissions()) return;
    if (s.lastPrinterId.startsWith('classic:') || s.lastPrinterId.startsWith('usb:')) {
      if (s.lastPrinterId.startsWith('usb:')) {
        final list = await NativePrinters.usb();
        if (!list.any((p) => p.id == s.lastPrinterId)) return; // cabo desconectado
      }
      await connectNative(NativePrinterInfo(s.lastPrinterId, s.lastPrinterName, true));
      if (!isConnected) lastError = null;
      notifyListeners();
      return;
    }
    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
      try {
        await FlutterBluePlus.adapterState
            .where((st) => st == BluetoothAdapterState.on)
            .first
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        return;
      }
    }
    await connect(BluetoothDevice.fromId(s.lastPrinterId), name: s.lastPrinterName);
    if (!isConnected) lastError = null; // silencioso: a impressora pode estar desligada
    notifyListeners();
  }

  Future<void> disconnect() async {
    if (nativeId != null) {
      try {
        await NativePrinters.disconnect();
      } catch (_) {}
      nativeId = null;
      nativeName = '';
    }
    try {
      await device?.disconnect();
    } catch (_) {}
    _connSub?.cancel();
    device = null;
    _writer = null;
    battery = null;
    notifyListeners();
  }

  BluetoothCharacteristic? _pickWriter(List<BluetoothService> services) {
    bool writable(BluetoothCharacteristic c) =>
        c.properties.write || c.properties.writeWithoutResponse;
    for (final pref in _preferredServices) {
      for (final s in services) {
        if (_short(s.uuid) == pref) {
          for (final c in s.characteristics) {
            if (writable(c)) return c;
          }
        }
      }
    }
    for (final s in services) {
      if (_genericServices.contains(_short(s.uuid))) continue;
      for (final c in s.characteristics) {
        if (writable(c)) return c;
      }
    }
    return null;
  }

  Future<int?> _readBattery(List<BluetoothService> services) async {
    for (final s in services) {
      if (_short(s.uuid) != '180f') continue;
      for (final c in s.characteristics) {
        if (_short(c.uuid) == '2a19' && c.properties.read) {
          try {
            final v = await c.read();
            if (v.isNotEmpty) return v.first;
          } catch (_) {}
        }
      }
    }
    return null;
  }

  Future<void> _send(Uint8List data) async {
    if (nativeId != null) {
      try {
        await NativePrinters.write(data);
      } on PlatformException catch (e) {
        nativeId = null;
        notifyListeners();
        throw e.message ?? 'Falha ao enviar';
      }
      return;
    }
    final w = _writer;
    final d = device;
    if (w == null || d == null) throw 'Impressora não conectada';
    final noResp = w.properties.writeWithoutResponse;
    final chunk = math.max(20, math.min(d.mtuNow - 3, noResp ? 180 : 240));
    for (var i = 0; i < data.length; i += chunk) {
      final end = math.min(i + chunk, data.length);
      await w.write(data.sublist(i, end), withoutResponse: noResp);
      if (noResp) {
        // Pausa curta para a impressora esvaziar o buffer.
        await Future.delayed(const Duration(milliseconds: 12));
      }
    }
  }

  Future<void> printPages(List<MonoBitmap> pages, {int copies = 1}) async {
    if (!isConnected) throw 'Conecte uma impressora primeiro.';
    printing = true;
    notifyListeners();
    try {
      final s = AppSettings.instance;
      await _send(EscPos.job(
        pages,
        copies: copies,
        feedLines: s.feedLines,
        cut: s.autoCut,
        openDrawer: s.openDrawer,
      ));
    } finally {
      printing = false;
      notifyListeners();
    }
  }

  /// Envia bytes ESC/POS prontos (integração com outros sistemas).
  Future<void> sendRaw(Uint8List bytes) async {
    if (!isConnected) throw 'Conecte uma impressora primeiro.';
    printing = true;
    notifyListeners();
    try {
      await _send(bytes);
    } finally {
      printing = false;
      notifyListeners();
    }
  }

  /// Comando avulso (abrir gaveta, cortar papel) usado nos Ajustes.
  Future<void> sendCommand(List<int> cmd) => sendRaw(Uint8List.fromList(cmd));
}
