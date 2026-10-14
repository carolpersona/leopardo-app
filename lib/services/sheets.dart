import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'leopardo_contact.dart';

/// Envio dos cadastros de garantia e pedidos da loja para a planilha Google
/// da Leopardo (Apps Script publicado como "App da Web").
///
/// Para ativar: cole em [sheetsUrl] o endereço gerado na publicação do script
/// (docs/planilha-google/Code.gs). Vazio = não envia.
const sheetsUrl =
    'https://script.google.com/a/macros/inputservice.com.br/s/AKfycbwCHORUQHWGyYYgXH1uYPDpzWR0sXNwt0uLEf3XDj8n9VG_q6NN_6NxExPuHgWZufr_/exec';

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

  static Future<bool> _post(String body) async => (await _postJson(body))?['ok'] == true;

  /// Envia e lê a resposta do script (o Apps Script grava e redireciona para a resposta).
  /// null = sem resposta (sem internet); {'ok': false, 'erro': 'login'} = acesso restrito.
  static Future<Map<String, dynamic>?> _postJson(String body) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.postUrl(Uri.parse(sheetsUrl));
      req.followRedirects = false;
      req.headers.contentType = ContentType('text', 'plain', charset: 'utf-8');
      req.add(utf8.encode(body));
      final res = await req.close().timeout(const Duration(seconds: 40));
      if (res.statusCode == 302 || res.statusCode == 303) {
        await res.drain<void>();
        final loc = res.headers.value('location') ?? '';
        if (loc.contains('accounts.google.com') || loc.contains('ServiceLogin')) {
          return {'ok': false, 'erro': 'login'};
        }
        try {
          final r2 = await (await client.getUrl(Uri.parse(loc))).close().timeout(const Duration(seconds: 30));
          final txt = await r2.transform(utf8.decoder).join();
          return _json(txt) ?? {'ok': true}; // gravou; resposta ilegível
        } catch (_) {
          return {'ok': true}; // o script já gravou antes de redirecionar
        }
      }
      final txt = await res.transform(utf8.decoder).join();
      return _json(txt) ?? {'ok': res.statusCode == 200, 'erro': 'http ${res.statusCode}'};
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Map<String, dynamic>? _json(String txt) {
    try {
      final j = jsonDecode(txt);
      return j is Map<String, dynamic> ? j : null;
    } catch (_) {
      return null;
    }
  }

  /// Quantos envios estão esperando internet/planilha.
  static Future<int> pending() async {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList(_queueKey) ?? const []).length;
  }

  /// Testa a ligação com a planilha (leitura e gravação). Devolve uma mensagem para mostrar.
  static Future<String> test() async {
    if (!enabled) return 'A planilha não está configurada no app.';
    // 1) leitura (avisos, tutoriais, indicação)
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    String leitura;
    try {
      final res = await (await client.getUrl(Uri.parse('$sheetsUrl?action=conteudo')))
          .close()
          .timeout(const Duration(seconds: 30));
      final txt = await res.transform(utf8.decoder).join();
      final j = _json(txt);
      if (j == null) {
        leitura = txt.contains('accounts.google') || txt.toLowerCase().contains('<html')
            ? 'BLOQUEADA: a planilha pede login. Em Implantar › Gerenciar implantações, '
                'mude "Quem pode acessar" para "Qualquer pessoa".'
            : 'resposta inesperada da planilha.';
      } else {
        final av = (j['avisos'] as List?)?.length ?? 0;
        final tu = (j['tutoriais'] as List?)?.length ?? 0;
        leitura = 'OK ($av aviso(s) e $tu vídeo(s) cadastrados).';
      }
    } catch (_) {
      return 'Sem conexão com a internet (ou o endereço da planilha está errado).';
    } finally {
      client.close(force: true);
    }
    // 2) gravação: o tipo "teste" não grava nada, só confere a senha
    final r = await _postJson(jsonEncode({'token': sheetsToken, 'type': 'teste', 'fields': {}}));
    String gravacao;
    if (r == null) {
      gravacao = 'sem resposta.';
    } else if (r['erro'] == 'login') {
      gravacao = 'BLOQUEADA: a planilha pede login ("Quem pode acessar" deve ser "Qualquer pessoa").';
    } else if (r['erro'] == 'token') {
      gravacao = 'senha diferente (TOKEN do script ≠ app).';
    } else {
      gravacao = 'OK.';
    }
    final pend = await pending();
    return 'Leitura: $leitura\nGravação: $gravacao'
        '${pend > 0 ? '\n$pend envio(s) pendente(s) serão reenviados.' : ''}';
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
    await _flush();
  }

  static Future<void> _flush() async {
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
