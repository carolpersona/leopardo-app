import 'dart:math' as math;

import 'package:flutter/services.dart';

/// Regras do boleto bancário (padrão FEBRABAN) e leitura dos dados do PDF.

// ---------------------------------------------------------------------------
// Código de barras e linha digitável
// ---------------------------------------------------------------------------

String onlyDigits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

int _mod10(String digits) {
  var sum = 0;
  var weight = 2;
  for (var i = digits.length - 1; i >= 0; i--) {
    var p = (digits.codeUnitAt(i) - 48) * weight;
    if (p > 9) p = p ~/ 10 + p % 10;
    sum += p;
    weight = weight == 2 ? 1 : 2;
  }
  return (10 - sum % 10) % 10;
}

/// Dígito verificador geral do código de barras (posição 5).
int barcodeDv(String bc44) {
  final base = bc44.substring(0, 4) + bc44.substring(5);
  var sum = 0;
  var weight = 2;
  for (var i = base.length - 1; i >= 0; i--) {
    sum += (base.codeUnitAt(i) - 48) * weight;
    weight = weight == 9 ? 2 : weight + 1;
  }
  final dv = 11 - sum % 11;
  return (dv == 0 || dv == 10 || dv == 11) ? 1 : dv;
}

bool isValidBarcode(String bc) =>
    bc.length == 44 && RegExp(r'^\d{44}$').hasMatch(bc) && bc[0] != '8' && barcodeDv(bc) == bc.codeUnitAt(4) - 48;

/// Linha digitável (47 dígitos) → código de barras (44 dígitos).
String? barcodeFromLinha(String linha) {
  final d = onlyDigits(linha);
  if (d.length != 47) return null;
  final bc = d.substring(0, 4) +
      d.substring(32, 33) +
      d.substring(33, 47) +
      d.substring(4, 9) +
      d.substring(10, 20) +
      d.substring(21, 31);
  return isValidBarcode(bc) ? bc : null;
}

/// Código de barras → linha digitável formatada.
String linhaFromBarcode(String bc) {
  final f1 = bc.substring(0, 4) + bc.substring(19, 24);
  final f2 = bc.substring(24, 34);
  final f3 = bc.substring(34, 44);
  final c1 = '$f1${_mod10(f1)}';
  final c2 = '$f2${_mod10(f2)}';
  final c3 = '$f3${_mod10(f3)}';
  return '${c1.substring(0, 5)}.${c1.substring(5)} '
      '${c2.substring(0, 5)}.${c2.substring(5)} '
      '${c3.substring(0, 5)}.${c3.substring(5)} '
      '${bc[4]} ${bc.substring(5, 19)}';
}

/// Vencimento pelo "fator de vencimento" (com a reinicialização de 22/02/2025).
DateTime? dueDateFromBarcode(String bc) {
  final fator = int.parse(bc.substring(5, 9));
  if (fator == 0) return null;
  final a = DateTime.utc(1997, 10, 7).add(Duration(days: fator));
  if (fator < 1000) return a;
  final b = DateTime.utc(2025, 2, 22).add(Duration(days: fator - 1000));
  final now = DateTime.now().toUtc();
  return (b.difference(now).inDays.abs() < a.difference(now).inDays.abs()) ? b : a;
}

int valueCentsFromBarcode(String bc) => int.parse(bc.substring(9, 19));

String formatDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String formatCentsBR(int cents) {
  final reais = (cents ~/ 100).toString();
  final buf = StringBuffer();
  for (var i = 0; i < reais.length; i++) {
    final fromEnd = reais.length - i;
    buf.write(reais[i]);
    if (fromEnd > 1 && fromEnd % 3 == 1) buf.write('.');
  }
  return '$buf,${(cents % 100).toString().padLeft(2, '0')}';
}

const bankNames = <String, String>{
  '001': 'Banco do Brasil',
  '004': 'Banco do Nordeste',
  '021': 'Banestes',
  '033': 'Santander',
  '037': 'Banpará',
  '041': 'Banrisul',
  '047': 'Banese',
  '070': 'BRB',
  '077': 'Banco Inter',
  '085': 'Ailos',
  '104': 'Caixa',
  '136': 'Unicred',
  '197': 'Stone',
  '208': 'BTG Pactual',
  '212': 'Banco Original',
  '237': 'Bradesco',
  '260': 'Nubank',
  '290': 'PagBank',
  '323': 'Mercado Pago',
  '336': 'C6 Bank',
  '341': 'Itaú',
  '380': 'PicPay',
  '389': 'Mercantil',
  '422': 'Safra',
  '633': 'Rendimento',
  '655': 'Votorantim',
  '707': 'Daycoval',
  '748': 'Sicredi',
  '756': 'Sicoob',
};

String bankDvGuess(String code) {
  if (code == '104') return '0';
  const w = [4, 3, 2];
  var sum = 0;
  for (var i = 0; i < 3; i++) {
    sum += (code.codeUnitAt(i) - 48) * w[i];
  }
  final dv = 11 - sum % 11;
  if (dv == 11) return '0';
  if (dv == 10) return 'X';
  return '$dv';
}

// ---------------------------------------------------------------------------
// Dados do boleto
// ---------------------------------------------------------------------------

class BoletoData {
  final Map<String, String> f;
  BoletoData([Map<String, String>? f]) : f = f ?? {};

  String operator [](String k) => f[k] ?? '';
  void operator []=(String k, String v) => f[k] = v;

  /// Campos que aparecem na tela de conferência, na ordem.
  static const fields = <List<String>>[
    ['linha', 'Linha digitável'],
    ['vencimento', 'Vencimento'],
    ['valor', 'Valor do documento (R\$)'],
    ['banco', 'Banco (código-dígito)'],
    ['bancoNome', 'Nome do banco'],
    ['beneficiario', 'Beneficiário'],
    ['agenciaCodigo', 'Agência / Código do beneficiário'],
    ['nossoNumero', 'Nosso número'],
    ['numeroDocumento', 'Nº do documento'],
    ['pagador', 'Pagador'],
    ['dataDocumento', 'Data do documento'],
    ['dataProcessamento', 'Data de processamento'],
    ['especieDoc', 'Espécie doc.'],
    ['aceite', 'Aceite'],
    ['carteira', 'Carteira'],
    ['localPagamento', 'Local de pagamento'],
    ['instrucoes', 'Instruções'],
    ['sacador', 'Sacador / Avalista'],
    ['pix', 'PIX copia e cola (QR Code)'],
  ];

  static const multiline = {'beneficiario', 'pagador', 'instrucoes', 'localPagamento', 'pix'};

  String? get barcode => barcodeFromLinha(this['linha']);

  /// Preenche linha, vencimento, valor e banco a partir do código de barras.
  void applyBarcode(String bc, {bool overwrite = true}) {
    void put(String k, String v) {
      if (overwrite || this[k].isEmpty) this[k] = v;
    }

    put('linha', linhaFromBarcode(bc));
    final due = dueDateFromBarcode(bc);
    if (due != null) put('vencimento', formatDate(due));
    final cents = valueCentsFromBarcode(bc);
    if (cents > 0) put('valor', formatCentsBR(cents));
    final code = bc.substring(0, 3);
    put('banco', '$code-${bankDvGuess(code)}');
    put('bancoNome', bankNames[code] ?? 'Banco $code');
  }
}

// ---------------------------------------------------------------------------
// Leitura do PDF
// ---------------------------------------------------------------------------

class _Seg {
  final int page;
  final double x, y, w, h;
  final String text;
  final String norm;
  _Seg(this.page, this.x, this.y, this.w, this.h, this.text) : norm = normalize(text);
  double get right => x + w;
}

String normalize(String s) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ';
  const to = 'aaaaaeeeeiiiiooooouuuucaaaaaeeeeiiiiooooouuuuc';
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch.toLowerCase());
  }
  return b.toString();
}

class _Code {
  final String bc;
  final int page;
  final double? y; // posição do código de barras na página (pt), quando lido da imagem
  _Code(this.bc, this.page, this.y);
}

class BoletoReader {
  static const _ch = MethodChannel('leopardo/system');

  static final _labels = <String, RegExp>{
    'localPagamento': RegExp(r'^local d[eo] pagamento'),
    'beneficiario': RegExp(r'^(beneficiario|cedente)(?!\s*final)'),
    'vencimento': RegExp(r'^(data d[eo] )?vencimento'),
    'agenciaCodigo': RegExp(
        r'^(agencia|ag\.?)\s*/?\s*(codigo|cod\.?|conta)|^codigo d[oa] (beneficiario|cedente)|^agencia'),
    'dataDocumento': RegExp(r'^data d[oa]? ?doc'),
    'numeroDocumento': RegExp(r'^(n[o°º.]*|num\.?|numero)\s*(d[oa])?\s*doc'),
    'especieDoc': RegExp(r'^especie\s*d(oc|o documento)'),
    'aceite': RegExp(r'^aceite'),
    'dataProcessamento': RegExp(r'^data (d[eo] )?proc'),
    'nossoNumero': RegExp(r'^nosso\s*n'),
    'usoBanco': RegExp(r'^uso do banco'),
    'carteira': RegExp(r'^carteira'),
    'especie': RegExp(r'^(especie(?!\s*d)|moeda)'),
    'quantidade': RegExp(r'^(quantidade|qtd|qtde)'),
    'valor': RegExp(r'^(\(\s*=\s*\)\s*)?valor'),
    'instrucoes': RegExp(r'^instru'),
    'pagador': RegExp(r'^(pagador|sacado)(?!r)'),
    'sacador': RegExp(r'^(sacador|beneficiario final)'),
    'desconto': RegExp(r'^\(\s*-\s*\)'),
    'acrescimo': RegExp(r'^\(\s*\+\s*\)'),
    'cobrado': RegExp(r'^\(\s*=\s*\)'),
    'autenticacao': RegExp(r'^autentica'),
    'recibo': RegExp(r'^(recibo do pagador|ficha de compensacao)'),
    'baixa': RegExp(r'^codigo de baixa'),
  };

  static bool _isLabel(_Seg s) => _labels.values.any((r) => r.hasMatch(s.norm));

  /// Analisa o PDF e devolve um boleto por código encontrado.
  static Future<List<BoletoData>> read(String path) async {
    final raw = await _ch.invokeMapMethod<String, dynamic>('analyzeBoleto', {'path': path}) ?? {};
    final segs = <_Seg>[
      for (final m in (raw['segments'] as List? ?? []))
        _Seg(
          (m['page'] as num).toInt(),
          (m['x'] as num).toDouble(),
          (m['y'] as num).toDouble(),
          (m['w'] as num).toDouble(),
          (m['h'] as num).toDouble(),
          m['text'] as String,
        ),
    ];
    final barcodes = (raw['barcodes'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

    // 1) Códigos de barras lidos da imagem
    final codes = <_Code>[];
    final seen = <String>{};
    for (final b in barcodes) {
      if (b['format'] != 'ITF') continue;
      final bc = onlyDigits(b['text'] as String);
      if (!isValidBarcode(bc) || seen.contains(bc)) continue;
      seen.add(bc);
      codes.add(_Code(bc, (b['page'] as num).toInt(), (b['y'] as num).toDouble()));
    }
    // 2) Linha digitável no texto
    final linhaRe = RegExp(r'(\d{5})\D?(\d{5})\s*(\d{5})\D?(\d{6})\s*(\d{5})\D?(\d{6})\s*(\d)\s*(\d{14})');
    for (final s in segs) {
      for (final m in linhaRe.allMatches(s.text)) {
        final bc = barcodeFromLinha(m.group(0)!);
        if (bc == null || seen.contains(bc)) continue;
        seen.add(bc);
        codes.add(_Code(bc, s.page, null));
      }
    }
    codes.sort((a, b) {
      if (a.page != b.page) return a.page - b.page;
      return (a.y ?? 0).compareTo(b.y ?? 0);
    });

    final pix = <Map<String, dynamic>>[
      for (final b in barcodes)
        if (b['format'] == 'QR_CODE' && (b['text'] as String).startsWith('000201')) b,
    ];

    final out = <BoletoData>[];
    for (var i = 0; i < codes.length; i++) {
      final c = codes[i];
      final samePage = codes.where((o) => o.page == c.page).toList();
      double minY = -1, maxY = 1e9;
      if (samePage.length > 1 && samePage.every((o) => o.y != null)) {
        final idx = samePage.indexOf(c);
        if (idx > 0) minY = samePage[idx - 1].y!;
        maxY = c.y!;
      }
      final region = segs.where((s) => s.page == c.page && s.y > minY && s.y < maxY).toList();
      final d = BoletoData();
      d.applyBarcode(c.bc);
      _fill(d, region, c.bc);
      final q = pix.where((p) {
        final y = (p['y'] as num).toDouble();
        return (p['page'] as num).toInt() == c.page && y > minY && y < maxY + 400;
      }).toList();
      if (q.isNotEmpty) d['pix'] = q.first['text'] as String;
      out.add(d);
    }
    return out;
  }

  /// Ocorrência do rótulo mais próxima da ficha de compensação (a mais baixa).
  static _Seg? _findLabel(List<_Seg> segs, String key) {
    final re = _labels[key]!;
    _Seg? best;
    for (final s in segs) {
      if (!re.hasMatch(s.norm)) continue;
      if (best == null || s.y > best.y + 1 || ((s.y - best.y).abs() <= 1 && s.x < best.x)) best = s;
    }
    return best;
  }

  static List<String> _valueLines(List<_Seg> segs, String key, {int lines = 1}) {
    final label = _findLabel(segs, key);
    if (label == null) return [];
    final re = _labels[key]!;
    final out = <String>[];

    // Valor na mesma célula, depois do rótulo ("Pagador: Fulano").
    final m = re.firstMatch(label.norm)!;
    var rest = label.text.length >= m.end ? label.text.substring(m.end) : '';
    // O que vem depois de ":" é o valor; sem ":", descarta o resto da palavra do rótulo.
    final colon = rest.indexOf(':');
    if (colon >= 0) {
      rest = rest.substring(colon + 1).trim();
    } else {
      rest = rest.replaceFirst(RegExp(r'^[^\s\-–/]*'), '').replaceFirst(RegExp(r'^[\s\-–/]+'), '').trim();
    }
    // Continuação do rótulo ("... do Beneficiário") não é valor.
    final restIsLabel = !RegExp(r'\d').hasMatch(rest) && RegExp(r'^(d[oae]s?|e)\b', caseSensitive: false).hasMatch(rest);
    if (rest.length >= 2 && !rest.startsWith('(') && !restIsLabel) out.add(rest);

    bool sameLine(_Seg s) => (s.y - label.y).abs() <= math.max(label.h, s.h) * 0.6;

    // Fim da coluna: próximo rótulo à direita na mesma linha.
    var colEnd = 1e9;
    for (final s in segs) {
      if (s == label || !sameLine(s)) continue;
      if (s.x > label.right + 2 && _isLabel(s) && s.x < colEnd) colEnd = s.x;
    }

    // Valor à direita na mesma linha ("Pagador:   EMPRESA LTDA   CNPJ: ...").
    double? lastY;
    var valueX = label.x;
    if (out.isEmpty) {
      final same = segs
          .where((s) => s != label && sameLine(s) && s.x > label.right && s.x < colEnd && !_isLabel(s))
          .toList()
        ..sort((a, b) => a.x.compareTo(b.x));
      if (same.isNotEmpty) {
        out.add(same.map((s) => s.text).join('  '));
        lastY = same.first.y;
        valueX = same.first.x;
      }
    }

    // Valores logo abaixo do rótulo, na mesma coluna.
    final below = segs
        .where((s) =>
            !sameLine(s) &&
            s.y > label.y &&
            s.x >= math.min(label.x, valueX) - 8 &&
            s.x < colEnd - 2 &&
            s.y < label.y + 400)
        .toList()
      ..sort((a, b) => a.y != b.y ? a.y.compareTo(b.y) : a.x.compareTo(b.x));
    final maxFirstGap = label.h * 3.2 < 24 ? 24.0 : label.h * 3.2;
    for (final s in below) {
      if (_isLabel(s)) break;
      if (lastY != null && (s.y - lastY).abs() <= 2 && out.isNotEmpty) {
        out[out.length - 1] = '${out.last} ${s.text}';
        continue;
      }
      if (out.length >= lines) break;
      if (lastY == null) {
        if (s.y - label.y > maxFirstGap) break;
      } else if (s.y - lastY > s.h * 2.2) {
        break;
      }
      out.add(s.text);
      lastY = s.y;
    }
    return out.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  static String _one(List<_Seg> segs, String key, {RegExp? mustMatch}) {
    for (final v in _valueLines(segs, key, lines: 2)) {
      if (mustMatch == null) return v;
      final m = mustMatch.firstMatch(v);
      if (m != null) return m.group(0)!;
    }
    return '';
  }

  static void _fill(BoletoData d, List<_Seg> segs, String bc) {
    final date = RegExp(r'\d{2}/\d{2}/\d{4}');
    void put(String k, String v) {
      if (v.trim().isNotEmpty) d[k] = v.trim();
    }

    // Banco: "041-8" impresso no cabeçalho
    final code = bc.substring(0, 3);
    final bankRe = RegExp('(^|\\D)$code\\s*-\\s*([0-9xX])(\\D|\$)');
    for (final s in segs) {
      final m = bankRe.firstMatch(s.text);
      if (m != null) {
        d['banco'] = '$code-${m.group(2)!.toUpperCase()}';
        break;
      }
    }

    final venc = _one(segs, 'vencimento', mustMatch: date);
    if (venc.isNotEmpty) d['vencimento'] = venc;
    put('localPagamento', _valueLines(segs, 'localPagamento', lines: 2).join(' '));
    put('beneficiario', _valueLines(segs, 'beneficiario', lines: 3).join('\n'));
    put('agenciaCodigo', _one(segs, 'agenciaCodigo', mustMatch: RegExp(r'[\d][\d\s./\-xX]*[\dxX]')));
    put('nossoNumero', _one(segs, 'nossoNumero', mustMatch: RegExp(r'[\d][\d\s./\-xX]*[\dxX]')));
    put('numeroDocumento', _one(segs, 'numeroDocumento'));
    put('dataDocumento', _one(segs, 'dataDocumento', mustMatch: date));
    put('dataProcessamento', _one(segs, 'dataProcessamento', mustMatch: date));
    put('especieDoc', _one(segs, 'especieDoc'));
    put('aceite', _one(segs, 'aceite', mustMatch: RegExp(r'^[A-Za-z]{1,3}$')));
    put('carteira', _one(segs, 'carteira'));
    put('pagador', _valueLines(segs, 'pagador', lines: 3).join('\n'));
    final sacador = _valueLines(segs, 'sacador', lines: 1).join(' ');
    if (!normalize(sacador).contains('nao informado')) put('sacador', sacador);
    put('instrucoes', _valueLines(segs, 'instrucoes', lines: 10).join('\n'));
  }
}
