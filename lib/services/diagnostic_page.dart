import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:qr/qr.dart';

import 'code128.dart';

/// Página de diagnóstico: alinhamento, densidade, cabeça de impressão, textos e códigos.
class DiagnosticPage {
  static const _black = Color(0xFF000000);

  final Canvas c;
  final double w;
  final double k;
  double y = 10;

  DiagnosticPage._(this.c, this.w) : k = w / 576.0;

  static Future<ui.Image> render({required int width, required List<String> info}) {
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawRect(Rect.fromLTWH(0, 0, width.toDouble(), 5000), Paint()..color = const Color(0xFFFFFFFF));
    final p = DiagnosticPage._(canvas, width.toDouble());
    p._draw(info);
    return rec.endRecording().toImage(width, (p.y + 20).ceil());
  }

  Paint get _fill => Paint()
    ..color = _black
    ..isAntiAlias = false;

  void _text(String s, double size, {bool bold = false, TextAlign align = TextAlign.left, double gap = 4}) {
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
    )..layout(minWidth: w - 16, maxWidth: w - 16);
    tp.paint(c, Offset(8, y));
    y += tp.height + gap * k;
  }

  void _section(String title) {
    y += 10 * k;
    c.drawRect(Rect.fromLTWH(0, y, w, 3 * k), _fill);
    y += 8 * k;
    _text(title, 22, bold: true, gap: 6);
  }

  // 1) Alinhamento: moldura em toda a largura + régua em milímetros (8 pontos = 1 mm)
  void _alignment() {
    final top = y.floorToDouble();
    final hh = (70 * k).floorToDouble();
    final p = _fill;
    c.drawRect(Rect.fromLTWH(0, top, w, 3), p);
    c.drawRect(Rect.fromLTWH(0, top + hh - 3, w, 3), p);
    c.drawRect(Rect.fromLTWH(0, top, 3, hh), p);
    c.drawRect(Rect.fromLTWH(w - 3, top, 3, hh), p);
    c.drawRect(Rect.fromLTWH((w / 2).floorToDouble() - 1, top, 2, hh), p);
    y = top + hh + 4;
    final ruler = y;
    for (var x = 0; x < w; x += 8) {
      final mm = x ~/ 8;
      final len = mm % 10 == 0 ? 26.0 : (mm % 5 == 0 ? 18.0 : 10.0);
      c.drawRect(Rect.fromLTWH(x.toDouble(), ruler, 1, len * k), p);
      if (mm % 10 == 0 && mm > 0) {
        final tp = TextPainter(
          text: TextSpan(text: '$mm', style: TextStyle(color: _black, fontSize: 14 * k, fontWeight: FontWeight.w700)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(c, Offset(x + 3, ruler + 12 * k));
      }
    }
    y = ruler + 32 * k;
    _text('Moldura completa dos dois lados = papel alinhado. Régua em mm.', 16);
  }

  // 2) Densidade: blocos de 0% a 100% com pontilhado ordenado
  void _density() {
    const bayer = [
      [0, 8, 2, 10],
      [12, 4, 14, 6],
      [3, 11, 1, 9],
      [15, 7, 13, 5],
    ];
    const levels = [0, 20, 40, 60, 80, 100];
    final top = y.floorToDouble();
    final hh = (60 * k).floorToDouble();
    final bw = (w / levels.length).floorToDouble();
    final p = _fill;
    for (var i = 0; i < levels.length; i++) {
      final x0 = (i * bw).floorToDouble();
      final t = levels[i] / 100 * 16;
      for (var yy = 0; yy < hh; yy++) {
        for (var xx = 0; xx < bw - 4; xx++) {
          if (bayer[yy % 4][xx % 4] < t) c.drawRect(Rect.fromLTWH(x0 + xx, top + yy, 1, 1), p);
        }
      }
      final tp = TextPainter(
        text: TextSpan(text: '${levels[i]}%', style: TextStyle(color: _black, fontSize: 15 * k, fontWeight: FontWeight.w700)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(c, Offset(x0 + (bw - tp.width) / 2, top + hh + 2));
    }
    y = top + hh + 22 * k;
    _text('Os blocos devem ir do branco ao preto, sem manchas. Se tudo sair claro, use o tom "Escuro".', 16);
  }

  // 3) Cabeça de impressão: preto sólido + linhas de 1 ponto + xadrez
  void _head() {
    final p = _fill;
    var top = y.floorToDouble();
    c.drawRect(Rect.fromLTWH(0, top, w, (56 * k).floorToDouble()), p);
    y = top + (56 * k).floorToDouble() + 6;
    _text('Preto sólido: riscos brancos verticais indicam pontos da cabeça com defeito ou sujeira.', 16);
    top = y.floorToDouble();
    final lh = (36 * k).floorToDouble();
    for (var x = 0; x < w; x += 2) {
      c.drawRect(Rect.fromLTWH(x.toDouble(), top, 1, lh), p);
    }
    top += lh + 6;
    for (var yy = 0; yy < lh; yy += 2) {
      for (var x = 0; x < w; x += 2) {
        if (((x ~/ 2) + (yy ~/ 2)) % 2 == 0) c.drawRect(Rect.fromLTWH(x.toDouble(), top + yy, 2, 2), p);
      }
    }
    top += lh + 6;
    for (var i = 0; i < lh; i++) {
      for (var x = -lh.toInt(); x < w; x += 12) {
        c.drawRect(Rect.fromLTWH(x + i.toDouble(), top + i, 2, 1), p);
      }
    }
    y = top + lh + 6;
    _text('Linhas finas e xadrez uniformes = cabeça em bom estado.', 16);
  }

  void _codes() {
    // Code 128
    final modules = Code128.encode('LEOPARDO-TESTE');
    final cell = math.max(2.0, ((w - 40) / (modules.length + 20)).floorToDouble());
    final total = cell * modules.length;
    final ox = ((w - total) / 2).floorToDouble();
    final hh = (70 * k).floorToDouble();
    final p = _fill;
    for (var i = 0; i < modules.length; i++) {
      if (modules[i]) c.drawRect(Rect.fromLTWH(ox + i * cell, y, cell, hh), p);
    }
    y += hh + 4;
    _text('LEOPARDO-TESTE', 16, align: TextAlign.center, gap: 10);
    // QR Code
    final q = QrImage(QrCode.fromData(data: 'LEOPARDO TESTE OK', errorCorrectLevel: QrErrorCorrectLevel.M));
    final n = q.moduleCount;
    final qc = ((180 * k) / n).floorToDouble();
    final qx = ((w - qc * n) / 2).floorToDouble();
    for (var r = 0; r < n; r++) {
      for (var col = 0; col < n; col++) {
        if (q.isDark(r, col)) c.drawRect(Rect.fromLTWH(qx + col * qc, y + r * qc, qc, qc), p);
      }
    }
    y += qc * n + 6;
    _text('Leia os dois códigos com a câmera do celular.', 16, align: TextAlign.center);
  }

  void _draw(List<String> info) {
    _text('DIAGNÓSTICO', 34, bold: true, align: TextAlign.center, gap: 0);
    _text('Impressoras Leopardo', 20, align: TextAlign.center, gap: 8);
    for (final line in info) {
      _text(line, 17, gap: 1);
    }
    _section('1. Alinhamento');
    _alignment();
    _section('2. Densidade');
    _density();
    _section('3. Cabeça de impressão');
    _head();
    _section('4. Textos');
    _text('Texto pequeno: ÁÉÍÓÚ ÂÊÔ ÃÕ Ç 0123456789', 16, gap: 2);
    _text('Texto médio: ÁÉÍÓÚ ÂÊÔ ÃÕ Ç 0123456789', 22, gap: 2);
    _text('Texto grande: ÁÉÍÓÚ Ç 0123', 30, bold: true, gap: 4);
    _section('5. Códigos');
    _codes();
    _section('Fim do teste');
    _text('Se esta linha saiu completa, a impressão chegou até o fim. '
        'Se ela não saiu, aumente "Aguardar antes de desconectar" em Ajustes.', 16);
  }
}
