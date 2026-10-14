import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

/// DANFE A4 (NF-e) → DANFE Simplificado. Leitura e desenho são feitos no Android
/// (DanfeModel.kt / DanfeDraw.kt), o mesmo código usado pela impressão do sistema.
class DanfeService {
  static const _ch = MethodChannel('leopardo/system');

  /// Uma nota por chave de acesso encontrada no PDF.
  static Future<List<Map<String, dynamic>>> read(String path) async {
    final r = await _ch.invokeMethod<List<dynamic>>('danfeRead', {'path': path});
    return [
      for (final e in r ?? const [])
        _deep(Map<String, dynamic>.from(e as Map)),
    ];
  }

  static Map<String, dynamic> _deep(Map<String, dynamic> m) {
    final itens = m['itens'];
    if (itens is List) {
      m['itens'] = [for (final i in itens) Map<String, dynamic>.from(i as Map)];
    }
    return m;
  }

  static Future<ui.Image> render(Map<String, dynamic> nota, int dots,
      {required bool etiqueta, bool valorTotal = true}) async {
    final bytes = await _ch.invokeMethod<Uint8List>('danfeRender', {
      'data': nota,
      'dots': dots,
      'etiqueta': etiqueta,
      'valorTotal': valorTotal,
    });
    final codec = await ui.instantiateImageCodec(bytes!);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  /// Campos que podem ser conferidos/corrigidos na tela.
  static const fields = <List<String>>[
    ['numero', 'Número da NF-e'],
    ['serie', 'Série'],
    ['emissao', 'Data de emissão'],
    ['tipo', 'Tipo de operação (0 = entrada, 1 = saída)'],
    ['protocolo', 'Protocolo de autorização de uso'],
    ['natureza', 'Natureza da operação'],
    ['emitNome', 'Emitente: nome / razão social'],
    ['emitCnpj', 'Emitente: CNPJ'],
    ['emitIe', 'Emitente: inscrição estadual'],
    ['emitUf', 'Emitente: UF'],
    ['emitEnd', 'Emitente: endereço'],
    ['destNome', 'Destinatário: nome / razão social'],
    ['destDoc', 'Destinatário: CNPJ / CPF'],
    ['destIe', 'Destinatário: inscrição estadual'],
    ['destUf', 'Destinatário: UF'],
    ['destEnd', 'Destinatário: endereço'],
    ['destBairro', 'Destinatário: bairro'],
    ['destMun', 'Destinatário: município'],
    ['destCep', 'Destinatário: CEP'],
    ['vProd', 'Valor total dos produtos'],
    ['vNF', 'Valor total da nota'],
    ['info', 'Informações complementares'],
  ];

  static const multiline = {'emitEnd', 'info', 'natureza'};

  /// Campos obrigatórios do DANFE Simplificado que não foram encontrados.
  static List<String> missing(Map<String, dynamic> n) {
    const req = {
      'emitNome': 'nome do emitente',
      'emitIe': 'IE do emitente',
      'destNome': 'destinatário',
      'destDoc': 'CNPJ/CPF do destinatário',
      'emissao': 'data de emissão',
      'protocolo': 'protocolo de autorização',
      'tipo': 'tipo de operação',
    };
    return [
      for (final e in req.entries)
        if ('${n[e.key] ?? ''}'.trim().isEmpty) e.value
    ];
  }
}
