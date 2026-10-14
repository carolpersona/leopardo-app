import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:xml/xml.dart';

/// Documento reorganizado para a bobina: lista de blocos de texto.
enum BlockType { title, heading, paragraph, bullet, table }

class DocBlock {
  final BlockType type;
  final String text;
  final List<List<String>> rows; // tabela
  DocBlock(this.type, this.text, {this.rows = const []});
}

// ---------------------------------------------------------------------------
// Leitura: Word (.docx)
// ---------------------------------------------------------------------------

class DocxReader {
  static List<DocBlock> read(Uint8List bytes) {
    final zip = ZipDecoder().decodeBytes(bytes);
    final file = zip.findFile('word/document.xml');
    if (file == null) throw 'arquivo Word inválido';
    final doc = XmlDocument.parse(utf8.decode(file.content as List<int>, allowMalformed: true));
    final body = doc.findAllElements('w:body').first;
    final out = <DocBlock>[];
    _walk(body, out);
    return out;
  }

  static void _walk(XmlElement parent, List<DocBlock> out) {
    for (final el in parent.childElements) {
      switch (el.name.qualified) {
        case 'w:p':
          final b = _paragraph(el);
          if (b != null) out.add(b);
          break;
        case 'w:tbl':
          final rows = <List<String>>[];
          for (final tr in el.findElements('w:tr')) {
            final cells = <String>[];
            for (final tc in tr.findElements('w:tc')) {
              cells.add(tc.findAllElements('w:p').map(_text).where((t) => t.trim().isNotEmpty).join(' ').trim());
            }
            if (cells.any((c) => c.isNotEmpty)) rows.add(cells);
          }
          if (rows.isNotEmpty) out.add(DocBlock(BlockType.table, '', rows: rows));
          break;
        case 'w:sdt':
          for (final c in el.findElements('w:sdtContent')) {
            _walk(c, out);
          }
          break;
        default:
          break;
      }
    }
  }

  static String _text(XmlElement p) {
    final b = StringBuffer();
    for (final n in p.descendants.whereType<XmlElement>()) {
      switch (n.name.qualified) {
        case 'w:t':
          b.write(n.innerText);
          break;
        case 'w:tab':
          b.write(' ');
          break;
        case 'w:br':
        case 'w:cr':
          b.write('\n');
          break;
      }
    }
    return b.toString();
  }

  static DocBlock? _paragraph(XmlElement p) {
    final text = _text(p).trim();
    if (text.isEmpty) return null;
    final ppr = p.getElement('w:pPr');
    final style = (ppr?.getElement('w:pStyle')?.getAttribute('w:val') ?? '').toLowerCase();
    final isList = ppr?.getElement('w:numPr') != null || style.contains('list') || style.contains('lista');
    if (style == 'title' || style.startsWith('titulo') && !style.contains(RegExp(r'\d')) || style == 'título') {
      return DocBlock(BlockType.title, text);
    }
    if (style.contains('heading') || style.contains('titulo') || style.contains('título')) {
      return DocBlock(BlockType.heading, text);
    }
    if (isList) return DocBlock(BlockType.bullet, text);
    // Parágrafo curto todo em negrito = subtítulo
    final runs = p.findAllElements('w:r').where((r) => r.getElement('w:t') != null).toList();
    final allBold = runs.isNotEmpty &&
        runs.every((r) {
          final bEl = r.getElement('w:rPr')?.getElement('w:b');
          if (bEl == null) return false;
          final v = bEl.getAttribute('w:val');
          return v == null || (v != '0' && v != 'false');
        });
    if (allBold && text.length <= 80) return DocBlock(BlockType.heading, text);
    return DocBlock(BlockType.paragraph, text);
  }
}

// ---------------------------------------------------------------------------
// Leitura: texto simples (.txt)
// ---------------------------------------------------------------------------

class PlainTextReader {
  static List<DocBlock> read(Uint8List bytes) {
    String s;
    try {
      s = utf8.decode(bytes);
    } catch (_) {
      s = latin1.decode(bytes);
    }
    s = s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final out = <DocBlock>[];
    final buf = <String>[];
    void flush() {
      if (buf.isNotEmpty) out.add(DocBlock(BlockType.paragraph, buf.join('\n')));
      buf.clear();
    }

    for (final raw in s.split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        flush();
        continue;
      }
      final m = RegExp(r'^\s*([-*•])\s+(.*)$').firstMatch(line);
      if (m != null) {
        flush();
        out.add(DocBlock(BlockType.bullet, m.group(2)!));
        continue;
      }
      buf.add(line);
    }
    flush();
    return out;
  }
}

// ---------------------------------------------------------------------------
// Leitura: PDF com texto (posições extraídas no Android)
// ---------------------------------------------------------------------------

class _Line {
  final int page;
  final double x, y, h, right;
  final String text;
  _Line(this.page, this.x, this.y, this.h, this.right, this.text);
}

class PdfTextReader {
  static const _ch = MethodChannel('leopardo/system');

  static Future<List<DocBlock>> read(String path) async {
    final raw = await _ch.invokeMapMethod<String, dynamic>('pdfText', {'path': path}) ?? {};
    final segs = (raw['segments'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    if (segs.isEmpty) return [];

    // 1) Linhas: trechos com a mesma altura na página
    segs.sort((a, b) {
      final pa = (a['page'] as num).toInt(), pb = (b['page'] as num).toInt();
      if (pa != pb) return pa - pb;
      final ya = (a['y'] as num).toDouble(), yb = (b['y'] as num).toDouble();
      if ((ya - yb).abs() > 1) return ya.compareTo(yb);
      return (a['x'] as num).compareTo(b['x'] as num);
    });
    final lines = <_Line>[];
    var cur = <Map<String, dynamic>>[];
    void flush() {
      if (cur.isEmpty) return;
      cur.sort((a, b) => (a['x'] as num).compareTo(b['x'] as num));
      final h = cur.map((s) => (s['h'] as num).toDouble()).reduce(math.max);
      final x = (cur.first['x'] as num).toDouble();
      final right = cur.map((s) => (s['x'] as num).toDouble() + (s['w'] as num).toDouble()).reduce(math.max);
      lines.add(_Line((cur.first['page'] as num).toInt(), x, (cur.first['y'] as num).toDouble(), h, right,
          cur.map((s) => s['text'] as String).join('   ')));
      cur = [];
    }

    for (final s in segs) {
      if (cur.isNotEmpty) {
        final f = cur.first;
        final samePage = (f['page'] as num).toInt() == (s['page'] as num).toInt();
        final dy = ((s['y'] as num).toDouble() - (f['y'] as num).toDouble()).abs();
        final h = math.max((f['h'] as num).toDouble(), (s['h'] as num).toDouble());
        if (!samePage || dy > h * 0.5) flush();
      }
      cur.add(s);
    }
    flush();

    // Remove números de página soltos
    lines.removeWhere((l) => RegExp(r'^\s*(p[aá]gina\s*)?\d+(\s*(de|/)\s*\d+)?\s*$', caseSensitive: false).hasMatch(l.text));
    if (lines.isEmpty) return [];

    // Tamanho do corpo do texto (mais frequente)
    final counts = <int, int>{};
    for (final l in lines) {
      final k = l.h.round();
      counts[k] = (counts[k] ?? 0) + l.text.length;
    }
    final body = counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key.toDouble();
    final textRight = lines.map((l) => l.right).reduce(math.max);
    final textLeft = lines.map((l) => l.x).reduce(math.min);
    final width = math.max(1.0, textRight - textLeft);

    // 2) Parágrafos
    final out = <DocBlock>[];
    final para = StringBuffer();
    BlockType type = BlockType.paragraph;
    void push() {
      final t = para.toString().trim();
      if (t.isNotEmpty) out.add(DocBlock(type, t));
      para.clear();
      type = BlockType.paragraph;
    }

    final bulletRe = RegExp(r'^\s*([•●▪◦\-–*]|\d{1,2}[.)])\s+');
    _Line? prev;
    for (final l in lines) {
      final isHeading = l.h >= body * 1.25 ||
          (l.text.length <= 60 && l.text == l.text.toUpperCase() && RegExp(r'[A-ZÁÉÍÓÚÇ]{3}').hasMatch(l.text));
      final isBullet = bulletRe.hasMatch(l.text);
      var newPara = prev == null || prev.page != l.page || isHeading || isBullet || type == BlockType.heading;
      if (!newPara && prev != null) {
        final gap = l.y - prev.y;
        final prevShort = (prev.right - textLeft) < width * 0.7 && RegExp(r'[.:;!?]$').hasMatch(prev.text.trim());
        if (gap > prev.h * 1.9 || (l.h - prev.h).abs() > body * 0.2 || prevShort) newPara = true;
      }
      if (newPara) {
        push();
        if (isHeading) type = l.h >= body * 1.6 && out.isEmpty ? BlockType.title : BlockType.heading;
        if (isBullet) type = BlockType.bullet;
        para.write(isBullet ? l.text.replaceFirst(bulletRe, '') : l.text);
      } else {
        final s = para.toString();
        if (s.endsWith('-') && RegExp(r'^[a-zà-ú]').hasMatch(l.text)) {
          para
            ..clear()
            ..write(s.substring(0, s.length - 1))
            ..write(l.text);
        } else {
          para
            ..write(' ')
            ..write(l.text);
        }
      }
      prev = l;
    }
    push();
    return out;
  }
}

// ---------------------------------------------------------------------------
// Desenho na largura da bobina
// ---------------------------------------------------------------------------

class DocRenderer {
  static const _black = Color(0xFF000000);

  /// Tamanhos de letra (em pontos da impressora, para 80 mm): Pequena, Média, Grande.
  static const sizes = [20.0, 25.0, 31.0];

  static Future<List<ui.Image>> render(List<DocBlock> blocks, int width, int sizeLevel) async {
    final k = width / 576.0;
    final base = sizes[sizeLevel.clamp(0, 2)] * k;
    final margin = 6.0;
    final inner = width - margin * 2;
    final pages = <ui.Image>[];

    late ui.PictureRecorder rec;
    late Canvas c;
    var y = 0.0;
    void start() {
      rec = ui.PictureRecorder();
      c = Canvas(rec);
      c.drawRect(Rect.fromLTWH(0, 0, width.toDouble(), 30000), Paint()..color = const Color(0xFFFFFFFF));
      y = 8;
    }

    Future<void> finish() async {
      pages.add(await rec.endRecording().toImage(width, (y + 8).ceil()));
    }

    TextPainter tp(String s, double size, {bool bold = false, TextAlign align = TextAlign.left, double? maxW}) {
      final p = TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(
            color: _black,
            fontSize: size,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
            height: 1.25,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: align,
      );
      final w = maxW ?? inner;
      p.layout(minWidth: w, maxWidth: w);
      return p;
    }

    final line = Paint()..color = _black;
    start();
    for (final b in blocks) {
      switch (b.type) {
        case BlockType.title:
          final p = tp(b.text, base * 1.45, bold: true, align: TextAlign.center);
          p.paint(c, Offset(margin, y));
          y += p.height + base * 0.3;
          c.drawRect(Rect.fromLTWH(margin, y, inner, math.max(2, 3 * k)), line);
          y += base * 0.8;
          break;
        case BlockType.heading:
          y += base * 0.35;
          final p = tp(b.text, base * 1.18, bold: true);
          p.paint(c, Offset(margin, y));
          y += p.height + base * 0.35;
          break;
        case BlockType.paragraph:
          final p = tp(b.text, base);
          p.paint(c, Offset(margin, y));
          y += p.height + base * 0.6;
          break;
        case BlockType.bullet:
          final indent = base * 1.1;
          final dot = tp('•', base, bold: true, maxW: indent);
          dot.paint(c, Offset(margin, y));
          final p = tp(b.text, base, maxW: inner - indent);
          p.paint(c, Offset(margin + indent, y));
          y += p.height + base * 0.35;
          break;
        case BlockType.table:
          final cols = b.rows.map((r) => r.length).reduce(math.max);
          final stroke = Paint()
            ..color = _black
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1, 1.5 * k);
          if (cols <= 3) {
            // Tabela em colunas
            final cw = inner / cols;
            for (var r = 0; r < b.rows.length; r++) {
              final row = b.rows[r];
              final ps = [
                for (var i = 0; i < cols; i++)
                  tp(i < row.length ? row[i] : '', base * 0.9, bold: r == 0, maxW: cw - 8),
              ];
              final hh = ps.map((p) => p.height).reduce(math.max) + 8;
              for (var i = 0; i < cols; i++) {
                c.drawRect(Rect.fromLTWH(margin + i * cw, y, cw, hh), stroke);
                ps[i].paint(c, Offset(margin + i * cw + 4, y + 4));
              }
              y += hh;
            }
          } else {
            // Muitas colunas: cada linha vira um bloco "coluna: valor"
            final header = b.rows.first;
            for (var r = 1; r < b.rows.length || r == 1; r++) {
              final row = r < b.rows.length ? b.rows[r] : header;
              final parts = <String>[];
              for (var i = 0; i < row.length; i++) {
                if (row[i].isEmpty) continue;
                final h = (i < header.length && r < b.rows.length) ? header[i] : '';
                parts.add(h.isEmpty ? row[i] : '$h: ${row[i]}');
              }
              final p = tp(parts.join('\n'), base * 0.9);
              p.paint(c, Offset(margin, y + 4));
              y += p.height + 8;
              c.drawRect(Rect.fromLTWH(margin, y, inner, math.max(1, 1.5 * k)), line);
              y += 6;
              if (b.rows.length == 1) break;
            }
          }
          y += base * 0.6;
          break;
      }
      if (y > 6000) {
        await finish();
        start();
      }
    }
    if (y > 10 || pages.isEmpty) await finish();
    return pages;
  }
}
