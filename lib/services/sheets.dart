import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'leopardo_contact.dart';

/// Envio dos cadastros de garantia e pedidos da loja para a planilha Google
/// da Leopardo (Apps Script publicado como "App da Web").
///
/// Para ativar: cole em [sheetsUrl] o endereço gerado na publicação do script
/// (docs/planilha-google/Code.gs). Vazio = não envia.
const sheetsUrl = '';

/// Senha simples combinada com o script (constante TOKEN no Code.gs).
const sheetsToken = 'leopardo-app-2026';

class SheetsSync {
  static const _queueKey = 'sheetsQueue';

  static bool get enabled => sheetsUrl.isNotEmpty;

  /// Registra uma linha na aba do [type] ("garantia" ou "pedido").
  /// Se não houver internet, guarda e tenta de novo depois.
  static Future<bool> send(String type, Map<String, String> fields, {String? imagePath}) async {
    if (!enabled) return false;
    final device = await LeopardoContact.deviceInfo();
    final payload = <String, dynamic>{
      'token': sheetsToken,
      'type': type,
      'fields': {
        ...fields,
        'App/celular': '${device['manufacturer'] ?? ''} ${device['model'] ?? ''} · Android ${device['android'] ?? ''}'
            ' · App ${device['appVersion'] ?? ''}',
      },
    };
    if (imagePath != null) {
      try {
        final f = File(imagePath);
        if (await f.exists() && await f.length() < 8 * 1024 * 1024) {
          final name = imagePath.split(Platform.pathSeparator).last;
          payload['image'] = {
            'name': name,
            'mime': name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg',
            'data': base64Encode(await f.readAsBytes()),
          };
        }
      } catch (_) {}
    }
    final body = jsonEncode(payload);
    final ok = await _post(body);
    if (!ok) await _enqueue(body);
    return ok;
  }

  static Future<bool> _post(String body) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.postUrl(Uri.parse(sheetsUrl));
      req.followRedirects = false;
      req.headers.contentType = ContentType('text', 'plain', charset: 'utf-8');
      req.add(utf8.encode(body));
      final res = await req.close().timeout(const Duration(seconds: 40));
      await res.drain<void>();
      // O Apps Script grava a linha e responde 302 (redirecionamento) ou 200.
      return res.statusCode == 200 || res.statusCode == 302;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> _enqueue(String body) async {
    final p = await SharedPreferences.getInstance();
    final q = p.getStringList(_queueKey) ?? [];
    q.add(body);
    while (q.length > 30) {
      q.removeAt(0);
    }
    await p.setStringList(_queueKey, q);
  }

  /// Reenvia o que ficou pendente (chamado ao abrir o app).
  static Future<void> flush() async {
    if (!enabled) return;
    final p = await SharedPreferences.getInstance();
    final q = p.getStringList(_queueKey) ?? [];
    if (q.isEmpty) return;
    final left = <String>[];
    for (final body in q) {
      if (!await _post(body)) left.add(body);
    }
    await p.setStringList(_queueKey, left);
  }
}
