import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'printer_service.dart';
import 'raster.dart';
import 'receipt_renderer.dart';
import 'settings.dart';

/// Pedido de impressão vindo de outro app ou site.
///  - [text]: texto comum (impresso com acentos, como imagem)
///  - [raw]: bytes ESC/POS prontos (enviados sem alteração)
class PrintRequest {
  final String? text;
  final Uint8List? raw;
  final String source;
  PrintRequest({this.text, this.raw, this.source = 'app'});

  bool get isEmpty => (text == null || text!.isEmpty) && (raw == null || raw!.isEmpty);

  static PrintRequest? fromMap(Map<dynamic, dynamic>? m) {
    if (m == null) return null;
    Uint8List? raw;
    final bytes = m['bytes'];
    if (bytes is Uint8List && bytes.isNotEmpty) raw = bytes;
    final b64 = m['base64'];
    if (raw == null && b64 is String && b64.isNotEmpty) {
      try {
        raw = base64Decode(base64.normalize(b64.trim().replaceAll(' ', '+')));
      } catch (_) {}
    }
    final r = PrintRequest(
      text: m['text'] as String?,
      raw: raw,
      source: (m['source'] as String?) ?? 'app',
    );
    return r.isEmpty ? null : r;
  }
}

/// Recebe pedidos do Android (MainActivity.kt) e imprime.
class Integration {
  static const _ch = MethodChannel('leopardo/system');

  /// Chamado quando chega um pedido; a interface decide como mostrar o resultado.
  static void Function(PrintRequest request)? onRequest;

  static Future<void> init() async {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'onPrintRequest') {
        final r = PrintRequest.fromMap(call.arguments as Map?);
        if (r != null) onRequest?.call(r);
      }
      return null;
    });
    try {
      final first = await _ch.invokeMethod<Map<dynamic, dynamic>>('takePrintRequest');
      final r = PrintRequest.fromMap(first);
      if (r != null) onRequest?.call(r);
    } catch (_) {}
  }

  /// Imprime o pedido na impressora atual (tenta reconectar se preciso).
  static Future<void> print(PrintRequest r) async {
    final ps = PrinterService.instance;
    if (!ps.isConnected) await ps.reconnectLast();
    if (!ps.isConnected) throw 'Nenhuma impressora conectada.';
    if (r.raw != null) {
      await ps.sendRaw(r.raw!);
      return;
    }
    final s = AppSettings.instance;
    final img = await renderFreeText(
      width: s.paperDots,
      text: r.text ?? '',
      large: false,
      bold: false,
      center: false,
    );
    final mono = await toMono(img, s.paperDots);
    await ps.printPages([mono]);
  }
}
