import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:qr/qr.dart';

import 'boleto.dart';

/// Layout "Grande": boleto em pé, como um cupom, com letras grandes.
///  - Vencimento e valor em destaque
///  - Linha digitável em várias linhas
///  - QR Code: PIX do boleto (quando houver) ou a linha digitável para copiar
///  - Código de barras em pé, no tamanho oficial (cerca de 10 cm)
class BoletoLargeRenderer {
  static const _black = Color(0xFF000000);

  final Canvas c;
  final double w; // largura do papel em pontos
  final double k; // 1 em 80 mm
  final double m; // margem lateral
  double y = 10;

  BoletoLargeRenderer._(this.c, this.w)
      : k = w / 576.0,
        m = 8;

  double get inner => w - m * 2;

  static Future<ui.Image> render(BoletoData d, int paperDots) {
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, paperDots.toDouble(), 6000),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    final r = BoletoLargeRenderer._(canvas, paperDots.toDouble());
    r._draw(d);
    return rec.endRecording().toImage(paperDots, (r.y + 16).ceil());
  }

  // ------------------------------------------------------------------ helpers

  TextPainter _tp(String s, double size, {bool bold = false, TextAlign align = TextAlign.left, double? maxW}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          color: _black,
          fontSize: size * k,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
          height: 1.15,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
    );
    final mw = maxW ?? inner;
    tp.layout(minWidth: mw, maxWidth: mw);
    return tp;
  }

  void text(String s, double size, {bool bold = false, TextAlign align = TextAlign.left, double gap = 4}) {
    if (s.trim().isEmpty) return;
    final tp = _tp(s.trim(), size, bold: bold, align: align);
    tp.paint(c, Offset(m, y));
    y += tp.height + gap * k;
  }

  /// Rótulo pequeno + valor grande.
  void field(String label, String value, {double size = 24, bool bold = true}) {
    if (value.trim().isEmpty) return;
    text(label.toUpperCase(), 17, gap: 1);
    text(value, size, bold: bold, gap: 10);
  }

  /// Dois campos lado a lado.
  void pair(String l1, String v1, String l2, String v2) {
    if (v1.trim().isEmpty && v2.trim().isEmpty) return;
    if (v1.trim().isEmpty) return field(l2, v2, size: 22);
    if (v2.trim().isEmpty) return field(l1, v1, size: 22);
    final half = (inner - 12) / 2;
    final a1 = _tp(l1.toUpperCase(), 17, maxW: half);
    final b1 = _tp(l2.toUpperCase(), 17, maxW: half);
    a1.paint(c, Offset(m, y));
    b1.paint(c, Offset(m + half + 12, y));
    y += math.max(a1.height, b1.height) + 1 * k;
    final a2 = _tp(v1, 22, bold: true, maxW: half);
    final b2 = _tp(v2, 22, bold: true, maxW: half);
    a2.paint(c, Offset(m, y));
    b2.paint(c, Offset(m + half + 12, y));
    y += math.max(a2.height, b2.height) + 10 * k;
  }

  void line({double thick = 2, double gapBefore = 4, double gapAfter = 10}) {
    y += gapBefore * k;
    c.drawRect(Rect.fromLTWH(m, y, inner, math.max(1.0, thick * k)), Paint()..color = _black);
    y += thick * k + gapAfter * k;
  }

  void dashed() {
    y += 6 * k;
    final p = Paint()..color = _black;
    for (var x = m; x < w - m; x += 16) {
      c.drawRect(Rect.fromLTWH(x, y, 8, math.max(1.0, 2 * k)), p);
    }
    y += 14 * k;
  }

  /// Faixa preta com texto branco (destaques).
  void band(String left, String right, {double size = 30}) {
    final pad = 10 * k;
    final r = TextPainter(
      text: TextSpan(
        text: right,
        style: TextStyle(color: const Color(0xFFFFFFFF), fontSize: size * k, fontWeight: FontWeight.w800, height: 1.1),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.right,
    )..layout(minWidth: inner - pad * 2, maxWidth: inner - pad * 2);
    final lw = TextPainter(
      text: TextSpan(
        text: left,
        style: TextStyle(color: const Color(0xFFFFFFFF), fontSize: size * 0.62 * k, fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: inner - pad * 2);
    final hh = math.max(lw.height, r.height) + pad * 2;
    c.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(m, y, inner, hh), Radius.circular(8 * k)),
      Paint()..color = _black,
    );
    lw.paint(c, Offset(m + pad, y + (hh - lw.height) / 2));
    r.paint(c, Offset(m + pad, y + (hh - r.height) / 2));
    y += hh + 10 * k;
  }

  void qr(String data, double size) {
    final code = QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M);
    final q = QrImage(code);
    final n = q.moduleCount;
    final cell = (size / (n + 2)).floorToDouble();
    if (cell < 2) return;
    final total = cell * (n + 2);
    final ox = ((w - total) / 2).floorToDouble() + cell;
    final oy = y.floorToDouble() + cell;
    final p = Paint()
      ..color = _black
      ..isAntiAlias = false;
    for (var r = 0; r < n; r++) {
      for (var col = 0; col < n; col++) {
        if (q.isDark(r, col)) c.drawRect(Rect.fromLTWH(ox + col * cell, oy + r * cell, cell, cell), p);
      }
    }
    y += total + 6 * k;
  }

  /// Código de barras em pé (barras horizontais, lidas ao longo do papel).
  void barcodeVertical(String digits, double barWidth) {
    const pat = ['nnwwn', 'wnnnw', 'nwnnw', 'wwnnn', 'nnwnw', 'wnwnn', 'nwwnn', 'nnnww', 'wnnwn', 'nwnwn'];
    const narrow = 2.0, wide = 6.0;
    final p = Paint()
      ..color = _black
      ..isAntiAlias = false;
    final x = ((w - barWidth) / 2).floorToDouble();
    y = y.floorToDouble() + 24; // zona de silêncio
    void bar(double t) {
      c.drawRect(Rect.fromLTWH(x, y, barWidth, t), p);
      y += t;
    }

    void space(double t) => y += t;
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
    y += 24;
  }

  // ------------------------------------------------------------------ layout

  /// "34191.09008 21994.850028 81223.980004 2 16260000105579" em 3 linhas.
  static String _linhaLines(String linha) {
    final parts = linha.trim().split(RegExp(r'\s+'));
    if (parts.length == 5) {
      return '${parts[0]}  ${parts[1]}\n${parts[2]}  ${parts[3]}\n${parts[4]}';
    }
    return linha;
  }

  void _draw(BoletoData d) {
    // Cabeçalho
    final head = _tp(d['bancoNome'], 30, bold: true, maxW: inner * 0.62);
    final code = _tp(d['banco'], 34, bold: true, align: TextAlign.right, maxW: inner * 0.38);
    head.paint(c, Offset(m, y + (code.height - head.height) / 2));
    code.paint(c, Offset(m + inner * 0.62, y));
    y += math.max(head.height, code.height) + 2 * k;
    text('BOLETO BANCÁRIO', 18, bold: true, gap: 0);
    line(thick: 3);

    // Destaques
    band('VENCIMENTO', d['vencimento'], size: 34);
    band('VALOR', 'R\$ ${d['valor']}', size: 38);

    // Partes
    field('Beneficiário', d['beneficiario'].replaceAll('\n', ' — '), size: 22);
    field('Pagador', d['pagador'].replaceAll('\n', ' — '), size: 22);
    pair('Nosso número', d['nossoNumero'], 'Nº do documento', d['numeroDocumento']);
    pair('Agência / Código', d['agenciaCodigo'], 'Data do documento', d['dataDocumento']);
    if (d['instrucoes'].trim().isNotEmpty) {
      text('INSTRUÇÕES', 17, gap: 1);
      text(d['instrucoes'], 20, gap: 10);
    }
    if (d['sacador'].trim().isNotEmpty) field('Sacador / Avalista', d['sacador'], size: 20, bold: false);

    // Linha digitável
    line();
    text('LINHA DIGITÁVEL', 18, bold: true, align: TextAlign.center, gap: 4);
    text(_linhaLines(d['linha']), 28, bold: true, align: TextAlign.center, gap: 10);

    // QR Code
    final pix = d['pix'].trim();
    final qrSize = math.min(inner * 0.72, 380 * k);
    if (pix.isNotEmpty) {
      line();
      text('PAGUE COM PIX', 26, bold: true, align: TextAlign.center, gap: 2);
      text('Abra o app do seu banco e escaneie o QR Code', 18, align: TextAlign.center, gap: 6);
      qr(pix, qrSize);
    } else if (d.barcode != null) {
      line();
      text('CÓDIGO DO BOLETO', 24, bold: true, align: TextAlign.center, gap: 2);
      text('Escaneie com a câmera, copie o código e cole no app do banco em "Pagar boleto"', 17,
          align: TextAlign.center, gap: 6);
      qr(onlyDigits(d['linha']), qrSize);
    }

    // Código de barras
    final bc = d.barcode;
    line();
    if (bc != null) {
      text('CÓDIGO DE BARRAS', 18, bold: true, align: TextAlign.center, gap: 0);
      barcodeVertical(bc, math.min(inner * 0.62, 340 * k));
    } else {
      text('Linha digitável inválida: confira os dados antes de imprimir.', 22, bold: true);
    }
    text('Autenticação mecânica — Ficha de Compensação', 15, align: TextAlign.center, gap: 0);
  }
}
