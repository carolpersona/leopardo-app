import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:qr/qr.dart';

import 'money.dart';

/// Desenha recibos, cobranças PIX e páginas de teste como imagem na largura
/// exata do papel. A mesma imagem vira prévia na tela e impressão.
class TicketCanvas {
  final int width;
  final double margin;
  final ui.PictureRecorder _rec = ui.PictureRecorder();
  late final ui.Canvas _c;
  double y = 6;

  TicketCanvas(this.width, {this.margin = 6}) {
    _c = ui.Canvas(_rec);
    _c.drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), 20000),
      ui.Paint()..color = const Color(0xFFFFFFFF),
    );
  }

  double get _inner => width - margin * 2;

  /// Fator de escala: textos foram pensados para 384 pontos (58 mm).
  double get _k => width / 384;

  TextPainter _tp(String text, double size, bool bold, TextAlign align, double maxW,
      {bool mono = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: const Color(0xFF000000),
          fontSize: size * _k,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          fontFamily: mono ? 'monospace' : null,
          height: 1.25,
        ),
      ),
      textAlign: align,
      textDirection: TextDirection.ltr,
    );
    tp.layout(minWidth: maxW, maxWidth: maxW);
    return tp;
  }

  void text(String t,
      {double size = 22, bool bold = false, TextAlign align = TextAlign.left, bool mono = false}) {
    if (t.isEmpty) return;
    final tp = _tp(t, size, bold, align, _inner, mono: mono);
    tp.paint(_c, Offset(margin, y));
    y += tp.height + 2;
  }

  void row(String left, String right, {double size = 22, bool bold = false}) {
    final r = _tp(right, size, bold, TextAlign.right, _inner);
    final rw = r.computeLineMetrics().isEmpty ? 0.0 : r.computeLineMetrics().first.width;
    final l = _tp(left, size, bold, TextAlign.left, _inner - rw - 10 * _k);
    l.paint(_c, Offset(margin, y));
    r.paint(_c, Offset(margin, y));
    y += (l.height > r.height ? l.height : r.height) + 2;
  }

  void dashed() {
    y += 4;
    final p = Paint()
      ..color = const Color(0xFF000000)
      ..strokeWidth = 2;
    for (var x = margin; x < width - margin; x += 10 * _k) {
      _c.drawLine(Offset(x, y), Offset(x + 5 * _k, y), p);
    }
    y += 8;
  }

  void space(double px) => y += px * _k;

  void image(ui.Image img, {double maxWidth = 200}) {
    final w = math.min(maxWidth * _k, _inner);
    final h = img.height * w / img.width;
    final dst = Rect.fromLTWH((width - w) / 2, y, w, h);
    _c.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      dst,
      Paint()..filterQuality = FilterQuality.high,
    );
    y += h + 6;
  }

  void qr(String data, {double size = 260}) {
    final code = QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M);
    final q = QrImage(code);
    final n = q.moduleCount;
    final target = math.max(80.0, math.min(size * _k, _inner));
    final cell = (target / (n + 4)).floorToDouble(); // módulo inteiro = QR nítido
    final total = cell * (n + 4);
    final ox = ((width - total) / 2).floorToDouble() + cell * 2;
    final oy = y + cell * 2;
    final p = Paint()..color = const Color(0xFF000000);
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        if (q.isDark(r, c)) {
          _c.drawRect(Rect.fromLTWH(ox + c * cell, oy + r * cell, cell, cell), p);
        }
      }
    }
    y += total + 4;
  }

  Future<ui.Image> finish() {
    y += 10;
    return _rec.endRecording().toImage(width, y.ceil());
  }
}

class ReceiptItem {
  int qty;
  String desc;
  int priceCents;
  ReceiptItem({this.qty = 1, this.desc = '', this.priceCents = 0});
  int get total => qty * priceCents;
}

String _now() {
  final d = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}

void _header(TicketCanvas t,
    {required String storeName, required String storePhone, required String storeCity, ui.Image? logo}) {
  if (logo != null) t.image(logo, maxWidth: 170);
  if (storeName.isNotEmpty) t.text(storeName, size: 26, bold: true, align: TextAlign.center);
  final contact = [storePhone, storeCity].where((s) => s.trim().isNotEmpty).join(' · ');
  if (contact.isNotEmpty) t.text(contact, size: 19, align: TextAlign.center);
}

Future<ui.Image> renderReceipt({
  required int width,
  required String storeName,
  required String storePhone,
  required String storeCity,
  ui.Image? logo,
  required String client,
  required List<ReceiptItem> items,
  String? payment,
  required String footer,
}) {
  final t = TicketCanvas(width);
  _header(t, storeName: storeName, storePhone: storePhone, storeCity: storeCity, logo: logo);
  t.dashed();
  t.text('RECIBO · ${_now()}', size: 19);
  if (client.trim().isNotEmpty) t.text('Cliente: ${client.trim()}', size: 19);
  t.dashed();
  var total = 0;
  for (final it in items) {
    if (it.desc.trim().isEmpty && it.priceCents == 0) continue;
    total += it.total;
    t.row('${it.qty}x ${it.desc.trim()}', formatCents(it.total), size: 21);
  }
  t.dashed();
  t.row('TOTAL', formatBRL(total), size: 28, bold: true);
  if (payment != null && payment.isNotEmpty) t.text('Pagamento: $payment', size: 19);
  if (footer.trim().isNotEmpty) {
    t.dashed();
    t.text(footer.trim(), size: 20, align: TextAlign.center);
  }
  return t.finish();
}

Future<ui.Image> renderFreeText({
  required int width,
  required String text,
  required bool large,
  required bool bold,
  required bool center,
}) {
  final t = TicketCanvas(width);
  t.text(text.isEmpty ? ' ' : text,
      size: large ? 32 : 22, bold: bold, align: center ? TextAlign.center : TextAlign.left);
  return t.finish();
}

Future<ui.Image> renderPix({
  required int width,
  required String storeName,
  required String payload,
  required int amountCents,
  required String description,
  required bool showCopyPaste,
}) {
  final t = TicketCanvas(width);
  if (storeName.isNotEmpty) t.text(storeName, size: 24, bold: true, align: TextAlign.center);
  t.text('PAGUE COM PIX', size: 26, bold: true, align: TextAlign.center);
  t.space(4);
  t.qr(payload);
  t.text(amountCents > 0 ? formatBRL(amountCents) : 'Valor livre',
      size: 34, bold: true, align: TextAlign.center);
  if (description.trim().isNotEmpty) {
    t.text(description.trim(), size: 20, align: TextAlign.center);
  }
  t.text(_now(), size: 18, align: TextAlign.center);
  if (showCopyPaste) {
    t.dashed();
    t.text('PIX Copia e Cola:', size: 18, bold: true);
    t.text(payload, size: 15, mono: true);
  }
  return t.finish();
}

Future<ui.Image> renderTestPage({required int width, required String printerName, required int paperMm}) {
  final t = TicketCanvas(width);
  t.text('LEOPARDO', size: 40, bold: true, align: TextAlign.center);
  t.text('Teste de impressão', size: 24, align: TextAlign.center);
  t.dashed();
  t.text('Impressora: $printerName', size: 20);
  t.text('Papel: $paperMm mm · $width pontos', size: 20);
  t.text('Data: ${_now()}', size: 20);
  t.dashed();
  t.text('Acentuação: ÁÉÍÓÚ ÂÊÔ ÃÕ Ç àéíóú', size: 20);
  t.text('0123456789 R\$ % @ # & * ( )', size: 20);
  t.space(6);
  t.qr('LEOPARDO - TESTE OK', size: 180);
  t.text('Se você consegue ler isto, está tudo certo!', size: 19, align: TextAlign.center);
  return t.finish();
}
