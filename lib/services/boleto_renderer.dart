import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:qr/qr.dart';

import 'boleto.dart';

/// Desenha o boleto "deitado" ao longo da bobina (como no modelo aprovado):
/// recibo do pagador + ficha de compensação, girados 90°, com o código de
/// barras Interleaved 2 of 5 no tamanho oficial (cerca de 10 cm).
///
/// Coordenadas do desenho: x = ao longo da bobina (pontos absolutos),
/// y = largura da bobina (0 = lado direito do papel).
class BoletoRenderer {
  static const _black = Color(0xFF000000);
  static const _recLen = 430.0;
  static const _gap = 36.0;
  static const _fichaLen = 1160.0;
  static const _margin = 10.0;

  final Canvas c;
  final double h; // largura do papel em pontos (576 = 80 mm)
  final double k; // escala da altura (1 em 80 mm)
  BoletoRenderer._(this.c, this.h) : k = h / 576.0;

  static double totalLength() => _margin + _recLen + _gap + _fichaLen + _margin;

  /// Imagem já na orientação da impressão: largura = papel, altura = comprimento.
  static Future<ui.Image> render(BoletoData d, int paperDots) {
    final len = totalLength();
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, paperDots.toDouble(), len),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    canvas.translate(paperDots.toDouble(), 0);
    canvas.rotate(math.pi / 2);
    final r = BoletoRenderer._(canvas, paperDots.toDouble());
    r._recibo(d, _margin);
    r._cutLine(_margin + _recLen + _gap / 2);
    r._ficha(d, _margin + _recLen + _gap);
    return rec.endRecording().toImage(paperDots, len.ceil());
  }

  // ------------------------------------------------------------------ helpers

  Paint get _line => Paint()
    ..color = _black
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(1.0, 1.5 * k)
    ..isAntiAlias = false;

  void _rect(double x, double y, double w, double hh) => c.drawRect(Rect.fromLTWH(x, y, w, hh), _line);

  void _hline(double x1, double x2, double y, {double width = 1.5}) {
    c.drawLine(Offset(x1, y), Offset(x2, y), _line..strokeWidth = math.max(1.0, width * k));
  }

  void _vline(double x, double y1, double y2, {double width = 1.5}) {
    c.drawLine(Offset(x, y1), Offset(x, y2), _line..strokeWidth = math.max(1.0, width * k));
  }

  /// Escreve texto; retorna a altura usada.
  double _text(
    String s,
    double x,
    double y,
    double maxW, {
    double size = 16,
    bool bold = false,
    TextAlign align = TextAlign.left,
    int maxLines = 1,
  }) {
    if (s.isEmpty || maxW <= 4) return 0;
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          color: _black,
          fontSize: size * k,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          height: 1.12,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: maxLines,
      ellipsis: '…',
    );
    tp.layout(minWidth: maxW, maxWidth: maxW);
    tp.paint(c, Offset(x, y));
    return tp.height;
  }

  /// Célula com rótulo pequeno em cima e valor embaixo.
  void _cell(
    String label,
    String value,
    double x,
    double y,
    double w,
    double hh, {
    TextAlign align = TextAlign.left,
    bool bold = false,
    double size = 17,
    int maxLines = 1,
    bool border = true,
  }) {
    if (border) _rect(x, y, w, hh);
    _text(label, x + 4, y + 2 * k, w - 8, size: 11.5);
    _text(value, x + 4, y + 14 * k, w - 8, size: size, bold: bold, align: align, maxLines: maxLines);
  }

  void _header(BoletoData d, double ox, double len, double top, double hh, {required String right, double rightSize = 20}) {
    final name = d['bancoNome'];
    final code = d['banco'];
    const nameW = 200.0;
    _text(name, ox + 2, top + (hh - 30 * k) / 2, nameW - 6, size: 25, bold: true);
    _vline(ox + nameW, top + 6 * k, top + hh, width: 3);
    _text(code, ox + nameW, top + (hh - 34 * k) / 2, 96, size: 29, bold: true, align: TextAlign.center);
    _vline(ox + nameW + 96, top + 6 * k, top + hh, width: 3);
    _text(right, ox + nameW + 104, top + (hh - rightSize * 1.15 * k) / 2, len - nameW - 108,
        size: rightSize, bold: true, align: TextAlign.right);
    _hline(ox, ox + len, top + hh, width: 3);
  }

  void _cutLine(double x) {
    final p = Paint()
      ..color = _black
      ..strokeWidth = 2
      ..isAntiAlias = false;
    for (var y = 0.0; y < h; y += 14) {
      c.drawLine(Offset(x, y), Offset(x, math.min(y + 7, h)), p);
    }
  }

  void _qr(String data, double x, double y, double size) {
    final code = QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M);
    final q = QrImage(code);
    final n = q.moduleCount;
    final cell = (size / (n + 2)).floorToDouble();
    if (cell < 2) return;
    final p = Paint()
      ..color = _black
      ..isAntiAlias = false;
    final ox = x.floorToDouble() + cell;
    final oy = y.floorToDouble() + cell;
    for (var r = 0; r < n; r++) {
      for (var col = 0; col < n; col++) {
        if (q.isDark(r, col)) c.drawRect(Rect.fromLTWH(ox + col * cell, oy + r * cell, cell, cell), p);
      }
    }
  }

  /// Interleaved 2 of 5 (padrão FEBRABAN): barra fina 2 pontos, larga 6 pontos.
  void _i25(String digits, double x, double y, double hh) {
    const pat = ['nnwwn', 'wnnnw', 'nwnnw', 'wwnnn', 'nnwnw', 'wnwnn', 'nwwnn', 'nnnww', 'wnnwn', 'nwnwn'];
    const narrow = 2.0, wide = 6.0;
    final p = Paint()
      ..color = _black
      ..isAntiAlias = false;
    var cx = x.floorToDouble();
    final top = y.floorToDouble();
    final height = hh.floorToDouble();
    void bar(double w) {
      c.drawRect(Rect.fromLTWH(cx, top, w, height), p);
      cx += w;
    }

    void space(double w) => cx += w;
    bar(narrow);
    space(narrow);
    bar(narrow);
    space(narrow);
    for (var i = 0; i + 1 < digits.length; i += 2) {
      final a = pat[digits.codeUnitAt(i) - 48];
      final b = pat[digits.codeUnitAt(i + 1) - 48];
      for (var j = 0; j < 5; j++) {
        bar(a[j] == 'w' ? wide : narrow);
        space(b[j] == 'w' ? wide : narrow);
      }
    }
    bar(wide);
    space(narrow);
    bar(narrow);
  }

  // ------------------------------------------------------------------ partes

  void _recibo(BoletoData d, double ox) {
    const len = _recLen;
    final top = 6 * k;
    final hh = 46 * k;
    _header(d, ox, len, top, hh, right: 'Recibo do Pagador', rightSize: 14);
    final gy = top + hh;
    final rh = 30 * k;
    const leftW = 250.0;
    const rightW = len - leftW;

    _cell('Beneficiário', d['beneficiario'], ox, gy, leftW, rh * 2, size: 13.5, maxLines: 3);
    _cell('Nº do Documento', d['numeroDocumento'], ox, gy + rh * 2, leftW, rh);
    _cell('Agência / Código do Beneficiário', d['agenciaCodigo'], ox, gy + rh * 3, leftW, rh);
    _cell('Nosso Número', d['nossoNumero'], ox, gy + rh * 4, leftW, rh);

    final rx = ox + leftW;
    _cell('Vencimento', d['vencimento'], rx, gy, rightW, rh, align: TextAlign.right, bold: true);
    _cell('(=) Valor do Documento', d['valor'], rx, gy + rh, rightW, rh, align: TextAlign.right, bold: true);
    _cell('(-) Desconto / Abatimento', '', rx, gy + rh * 2, rightW, rh);
    _cell('(+) Mora / Multa / Juros', '', rx, gy + rh * 3, rightW, rh);
    _cell('(=) Valor Cobrado', '', rx, gy + rh * 4, rightW, rh);

    final py = gy + rh * 5;
    _cell('Pagador', d['pagador'], ox, py, len, rh * 2, size: 14, maxLines: 3);

    var y = py + rh * 2 + 6 * k;
    final bottom = h - 22 * k;
    final pix = d['pix'];
    if (pix.isNotEmpty) {
      final q = math.min(bottom - y, 210 * k);
      _qr(pix, ox, y, q);
      final tx = ox + q + 10;
      _text('Pague com PIX', tx, y + 14 * k, len - q - 14, size: 20, bold: true);
      _text('Abra o app do seu banco e aponte a câmera para o QR Code.', tx, y + 44 * k, len - q - 14,
          size: 13, maxLines: 4);
    } else {
      _text('Linha digitável', ox + 2, y, len - 4, size: 11.5);
      _text(d['linha'], ox + 2, y + 14 * k, len - 4, size: 15, bold: true, maxLines: 2);
    }
    _text('Autenticação mecânica - Recibo do Pagador', ox, h - 18 * k, len, size: 11, align: TextAlign.right);
  }

  void _ficha(BoletoData d, double ox) {
    const len = _fichaLen;
    final top = 6 * k;
    final hh = 50 * k;
    _header(d, ox, len, top, hh, right: d['linha'], rightSize: 21);

    final gy = top + hh;
    final rh = 30 * k;
    const rightW = 270.0;
    const leftW = len - rightW;
    final rx = ox + leftW;

    // Coluna da direita
    final right = <List<String>>[
      ['Vencimento', d['vencimento']],
      ['Agência / Código do Beneficiário', d['agenciaCodigo']],
      ['Nosso Número', d['nossoNumero']],
      ['(=) Valor do Documento', d['valor']],
      ['(-) Desconto / Abatimento', ''],
      ['(-) Outras Deduções', ''],
      ['(+) Mora / Multa / Juros', ''],
      ['(+) Outros Acréscimos', ''],
      ['(=) Valor Cobrado', ''],
    ];
    for (var i = 0; i < right.length; i++) {
      final strong = i == 0 || i == 3;
      _cell(right[i][0], right[i][1], rx, gy + rh * i, rightW, rh, align: TextAlign.right, bold: strong);
    }

    // Coluna da esquerda
    _cell('Local de Pagamento',
        d['localPagamento'].isEmpty ? 'Pagável em qualquer banco até o vencimento' : d['localPagamento'],
        ox, gy, leftW, rh, size: 15);
    _cell('Beneficiário', d['beneficiario'].replaceAll('\n', '  ·  '), ox, gy + rh, leftW, rh * 2,
        size: 14.5, maxLines: 2);

    void row(double y, List<List<String>> cells, List<double> frac) {
      var x = ox;
      for (var i = 0; i < cells.length; i++) {
        final w = leftW * frac[i];
        _cell(cells[i][0], cells[i][1], x, y, w, rh, size: 15.5);
        x += w;
      }
    }

    const frac = [0.2, 0.26, 0.16, 0.1, 0.28];
    row(gy + rh * 3, [
      ['Data do Documento', d['dataDocumento']],
      ['Nº do Documento', d['numeroDocumento']],
      ['Espécie Doc.', d['especieDoc']],
      ['Aceite', d['aceite']],
      ['Data Processamento', d['dataProcessamento']],
    ], frac);
    row(gy + rh * 4, [
      ['Uso do Banco', ''],
      ['Carteira', d['carteira']],
      ['Espécie', 'R\$'],
      ['Quantidade', ''],
      ['(x) Valor', ''],
    ], frac);

    final iy = gy + rh * 5;
    final ih = rh * 4;
    _rect(ox, iy, leftW, ih);
    _text('Instruções (texto de responsabilidade do beneficiário)', ox + 4, iy + 2 * k, leftW - 8, size: 11.5);
    _text(d['instrucoes'], ox + 4, iy + 15 * k, leftW - 8, size: 13, maxLines: 7);

    // Pagador
    final py = gy + rh * 9;
    final ph = 58 * k;
    _rect(ox, py, len, ph);
    _text('Pagador', ox + 4, py + 2 * k, 120, size: 11.5);
    _text(d['pagador'].replaceAll('\n', '  ·  '), ox + 4, py + 14 * k, len - 8, size: 14.5, maxLines: 2);
    if (d['sacador'].isNotEmpty) {
      _text('Sacador/Avalista: ${d['sacador']}', ox + 4, py + 41 * k, len - 8, size: 12);
    }
    _text('Autenticação mecânica - Ficha de Compensação', ox, py + ph + 2 * k, len, size: 11, align: TextAlign.right);

    // Código de barras
    final bc = d.barcode;
    final by = py + ph + 18 * k;
    final bh = math.min(104 * k, h - by - 6 * k);
    if (bc != null && bh > 20) {
      _i25(bc, ox + 40, by, bh);
    } else {
      _text('Linha digitável inválida: confira os dados antes de imprimir.', ox + 30, by + 10 * k, len - 60,
          size: 18, bold: true);
    }
  }
}
