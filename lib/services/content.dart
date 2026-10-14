import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sheets.dart';

/// Aviso/promoção exibido na tela inicial (aba "Avisos" da planilha).
class Aviso {
  final String titulo;
  final String texto;
  final String imagem; // URL (opcional)
  final String botao; // texto do botão (opcional)
  final String acao; // loja | tutoriais | garantia | indique | whatsapp:mensagem | https://...
  Aviso(this.titulo, this.texto, this.imagem, this.botao, this.acao);

  static Aviso fromJson(Map<String, dynamic> m) => Aviso(
        '${m['Título'] ?? m['Titulo'] ?? ''}',
        '${m['Texto'] ?? ''}',
        '${m['Imagem'] ?? ''}',
        '${m['Botão'] ?? m['Botao'] ?? ''}',
        '${m['Ação'] ?? m['Acao'] ?? ''}',
      );
}

/// Vídeo de tutorial (aba "Tutoriais" da planilha).
class Video {
  final String titulo;
  final String descricao;
  final String link;
  Video(this.titulo, this.descricao, this.link);

  /// Miniatura do YouTube, quando o link é de lá.
  String? get thumbnail {
    final m = RegExp(r'(?:youtu\.be/|v=|shorts/|embed/)([A-Za-z0-9_-]{11})').firstMatch(link);
    return m == null ? null : 'https://img.youtube.com/vi/${m.group(1)}/hqdefault.jpg';
  }
}

/// Textos do programa de indicação (aba "Indicação" da planilha).
class IndicacaoConfig {
  final String titulo;
  final String regras;
  const IndicacaoConfig(this.titulo, this.regras);

  static const padrao = IndicacaoConfig(
    'Indique a Leopardo',
    'Compartilhe seu código com amigos e clientes. Quando alguém comprar com o seu código, '
        'vocês dois podem ganhar benefícios. Consulte as condições com a Leopardo pelo WhatsApp.',
  );
}

/// Conteúdo que a Leopardo atualiza pela planilha, sem lançar versão nova do app.
class ContentService extends ChangeNotifier {
  ContentService._();
  static final ContentService instance = ContentService._();
  static const _cacheKey = 'conteudoCache';
  static const _codeKey = 'referralCode';

  List<Aviso> avisos = [];
  List<Video> videos = [];
  IndicacaoConfig indicacao = IndicacaoConfig.padrao;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final cached = p.getString(_cacheKey);
    if (cached != null) _apply(cached);
    refresh();
  }

  /// Busca o conteúdo atualizado na planilha (se configurada).
  Future<void> refresh() async {
    if (!SheetsSync.enabled) return;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse('$sheetsUrl?action=conteudo'));
      final res = await req.close().timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return;
      final body = await res.transform(utf8.decoder).join();
      if (_apply(body)) {
        final p = await SharedPreferences.getInstance();
        await p.setString(_cacheKey, body);
      }
    } catch (_) {
      // sem internet: fica o conteúdo guardado
    } finally {
      client.close(force: true);
    }
  }

  bool _apply(String body) {
    try {
      final j = jsonDecode(body) as Map<String, dynamic>;
      if (j['ok'] != true) return false;
      final hoje = DateTime.now();
      bool ativo(Map<String, dynamic> m) {
        final a = '${m['Ativo'] ?? 'Sim'}'.trim().toLowerCase();
        if (a == 'não' || a == 'nao' || a == 'n' || a == 'false') return false;
        final ini = DateTime.tryParse('${m['Início'] ?? m['Inicio'] ?? ''}');
        final fim = DateTime.tryParse('${m['Fim'] ?? ''}');
        if (ini != null && hoje.isBefore(ini)) return false;
        if (fim != null && hoje.isAfter(fim.add(const Duration(days: 1)))) return false;
        return true;
      }

      avisos = [
        for (final e in (j['avisos'] as List? ?? []))
          if (ativo(Map<String, dynamic>.from(e as Map))) Aviso.fromJson(Map<String, dynamic>.from(e)),
      ].where((a) => a.titulo.isNotEmpty || a.texto.isNotEmpty || a.imagem.isNotEmpty).toList();
      videos = [
        for (final e in (j['tutoriais'] as List? ?? []))
          if (ativo(Map<String, dynamic>.from(e as Map)))
            Video('${e['Título'] ?? e['Titulo'] ?? ''}', '${e['Descrição'] ?? e['Descricao'] ?? ''}',
                '${e['Link do vídeo'] ?? e['Link'] ?? ''}'),
      ].where((v) => v.link.startsWith('http')).toList();
      final ind = Map<String, dynamic>.from(j['indicacao'] as Map? ?? {});
      indicacao = IndicacaoConfig(
        '${ind['Título'] ?? ind['Titulo'] ?? IndicacaoConfig.padrao.titulo}',
        '${ind['Regras'] ?? IndicacaoConfig.padrao.regras}',
      );
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Código de indicação deste cliente (gerado uma vez e guardado).
  Future<String> referralCode() async {
    final p = await SharedPreferences.getInstance();
    var code = p.getString(_codeKey);
    if (code == null) {
      const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
      final r = math.Random.secure();
      code = 'LEO-${List.generate(5, (_) => chars[r.nextInt(chars.length)]).join()}';
      await p.setString(_codeKey, code);
    }
    return code;
  }

  static const _ch = MethodChannel('leopardo/system');

  static Future<bool> shareText(String text) async {
    try {
      return await _ch.invokeMethod<bool>('shareText', {'text': text}) ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// Guias rápidos embutidos no app (funcionam sem internet).
class Guide {
  final String titulo;
  final String resumo;
  final List<String> passos;
  const Guide(this.titulo, this.resumo, this.passos);
}

const guides = <Guide>[
  Guide('Primeira conexão da impressora', 'Ligar e conectar pelo Bluetooth', [
    'Carregue e ligue a impressora Leopardo.',
    'No app, abra a aba Impressoras e permita o acesso a "Dispositivos próximos".',
    'Toque em Conectar na impressora encontrada (as Leopardo aparecem primeiro).',
    'Impressora Bluetooth comum? Pareie antes em Configurações › Bluetooth do celular; ela aparece em "Bluetooth pareado".',
    'Na tela Início, toque em "Imprimir teste" para conferir.',
  ]),
  Guide('Trocar a bobina', 'Colocar o papel do jeito certo', [
    'Abra a tampa do compartimento de papel.',
    'Coloque a bobina com o lado térmico (o mais liso e brilhante) virado para a cabeça de impressão.',
    'Puxe um pedaço do papel para fora, passando pela saída.',
    'Feche a tampa até travar, deixando o papel sair pela abertura.',
    'Se sair em branco, a bobina está invertida: vire o rolo.',
  ]),
  Guide('Imprimir pedido do WhatsApp', 'Texto ou PDF recebido no WhatsApp', [
    'No WhatsApp, segure a mensagem do pedido (ou abra o PDF).',
    'Toque em Compartilhar e escolha "Leopardo".',
    'Confira a prévia e toque em Imprimir.',
  ]),
  Guide('Imprimir de qualquer app', 'Leopardo na tela "Imprimir" do Android', [
    'No app, abra a aba Impressoras e conecte sua impressora pelo menos uma vez.',
    'Toque em "Ativar no Android" e ligue a chave "Leopardo".',
    'Em qualquer app (PDF, navegador, galeria), toque em Imprimir e escolha a sua Leopardo.',
  ]),
  Guide('Boleto em 80 mm', 'Boleto A4 refeito para a bobina', [
    'Na tela Início, toque em "Boleto em 80 mm" e escolha o PDF.',
    'Confira os dados em "Conferir e editar dados".',
    'Toque em Imprimir boleto. O código de barras sai no tamanho oficial.',
  ]),
  Guide('DANFE Simplificado', 'Nota fiscal A4 refeita para a bobina', [
    'Na tela Início, toque em "DANFE Simplificado" e escolha o PDF da nota (ou compartilhe o PDF com o app Leopardo).',
    'Escolha "Completo" (com produtos e totais) ou "Etiqueta" (para colar na embalagem).',
    'Confira os dados e toque em Imprimir DANFE.',
    'Pela tela "Imprimir" do Android, o DANFE em PDF já sai simplificado (dá para desligar em Impressoras).',
  ]),
  Guide('Problemas comuns', 'O que fazer quando algo não sai certo', [
    'Não encontra a impressora: ligue o Bluetooth e a localização e deixe a impressora a até 5 metros.',
    'Impressão clara: em Ajustes, mude o "Tom da impressão" para Escuro.',
    'Documento cortado no final: em Ajustes › Controle de fluxo, diminua a "Velocidade de impressão" (ex.: 40 ou 30 mm/s).',
    'Letra pequena em PDF: ligue "Reorganizar texto para 80 mm".',
    'Ainda com problema? Use o Diagnóstico e envie o relatório à Leopardo.',
  ]),
];
