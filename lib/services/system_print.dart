import 'dart:io';

import 'package:flutter/services.dart';

/// Ponte com o Android para o serviço "Imprimir" do sistema.
class SystemPrint {
  static const _ch = MethodChannel('leopardo/system');

  /// Abre Configurações › Impressão, onde o usuário ativa o serviço Leopardo.
  static Future<bool> openSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _ch.invokeMethod<bool>('openPrintSettings') ?? false;
    } catch (_) {
      return false;
    }
  }
}
