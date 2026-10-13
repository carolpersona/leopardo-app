import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Impressora encontrada por Bluetooth clássico (pareada) ou USB.
class NativePrinterInfo {
  final String id; // "classic:<MAC>" ou "usb:<dispositivo>"
  final String name;
  final bool looksLikePrinter;
  NativePrinterInfo(this.id, this.name, this.looksLikePrinter);

  bool get isUsb => id.startsWith('usb:');
}

/// Ponte com o código Android (NativePrinters.kt) para Bluetooth clássico e USB.
class NativePrinters {
  static const _ch = MethodChannel('leopardo/printer');

  static Future<List<NativePrinterInfo>> _list(String method) async {
    if (!Platform.isAndroid) return [];
    try {
      final raw = await _ch.invokeListMethod<dynamic>(method) ?? [];
      return raw.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return NativePrinterInfo(
          m['id'] as String,
          (m['name'] as String?) ?? '',
          (m['printer'] as bool?) ?? false,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<NativePrinterInfo>> bonded() => _list('bondedDevices');
  static Future<List<NativePrinterInfo>> usb() => _list('usbDevices');

  /// Lança [PlatformException] com a mensagem de erro em português.
  static Future<void> connect(String id) => _ch.invokeMethod('connect', {'id': id});

  static Future<void> write(Uint8List bytes) => _ch.invokeMethod('write', {'bytes': bytes});

  static Future<void> disconnect() => _ch.invokeMethod('disconnect');
}
