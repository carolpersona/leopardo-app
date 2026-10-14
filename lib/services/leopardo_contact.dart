import 'package:flutter/services.dart';

/// Contato oficial da Leopardo (WhatsApp).
class LeopardoContact {
  static const phone = '5511963044242';
  static const phoneLabel = '(11) 96304-4242';
  static const _ch = MethodChannel('leopardo/system');

  static Future<bool> openUrl(String url) async {
    try {
      return await _ch.invokeMethod<bool>('openUrl', {'url': url}) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Abre o WhatsApp da Leopardo com a mensagem já escrita.
  static Future<bool> whatsapp([String message = 'Olá! Vim pelo app Leopardo.']) =>
      openUrl('https://wa.me/$phone?text=${Uri.encodeComponent(message)}');

  /// Envia texto e, opcionalmente, uma foto direto para a conversa da Leopardo.
  static Future<bool> sendWhatsApp(String text, {String? imagePath}) async {
    try {
      return await _ch.invokeMethod<bool>('shareWhatsApp', {
            'phone': phone,
            'text': text,
            'image': imagePath,
          }) ??
          false;
    } catch (_) {
      return whatsapp(text);
    }
  }

  static Future<Map<String, dynamic>> deviceInfo() async {
    try {
      return await _ch.invokeMapMethod<String, dynamic>('deviceInfo') ?? {};
    } catch (_) {
      return {};
    }
  }
}
