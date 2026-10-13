import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'settings.dart';

/// Imagem 1 bit (preto/branco) no formato da cabeça térmica.
/// [bits]: linhas de cima para baixo, 8 pixels por byte, bit mais
/// significativo à esquerda, 1 = ponto preto.
class MonoBitmap {
  final int width; // sempre múltiplo de 8
  final int height;
  final Uint8List bits;

  MonoBitmap(this.width, this.height, this.bits);

  int get bytesPerRow => width ~/ 8;

  /// Converte de volta para imagem, para mostrar a prévia exata da impressão.
  Future<ui.Image> toImage() {
    final rgba = Uint8List(width * height * 4);
    final bpr = bytesPerRow;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final on = (bits[y * bpr + (x >> 3)] & (0x80 >> (x & 7))) != 0;
        final i = (y * width + x) * 4;
        final v = on ? 0x17 : 0xFF;
        rgba[i] = v;
        rgba[i + 1] = v;
        rgba[i + 2] = v;
        rgba[i + 3] = 0xFF;
      }
    }
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(
        rgba, width, height, ui.PixelFormat.rgba8888, c.complete);
    return c.future;
  }
}

class RasterOptions {
  /// true = pontilhado (fotos); false = limiar (texto nítido).
  final bool dither;

  /// -0.5 a +0.5
  final double contrast;

  /// Remove margens em branco ao redor do conteúdo.
  final bool cropBlank;

  /// Se falso, imagens menores que o papel não são ampliadas.
  final bool fitWidth;

  const RasterOptions({
    this.dither = false,
    this.contrast = 0,
    this.cropBlank = false,
    this.fitWidth = true,
  });
}

Future<ByteData> _rgba(ui.Image img) async {
  final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  return bd!;
}

/// Encontra o retângulo com conteúdo (ignora fundo branco/transparente).
Future<ui.Rect> _contentBounds(ui.Image img) async {
  final data = await _rgba(img);
  final w = img.width, h = img.height;
  var minX = w, minY = h, maxX = -1, maxY = -1;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      final a = data.getUint8(i + 3);
      if (a < 16) continue;
      final l = (data.getUint8(i) * 299 +
              data.getUint8(i + 1) * 587 +
              data.getUint8(i + 2) * 114) ~/
          1000;
      if (l < 235) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  if (maxX < 0) {
    return ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
  }
  const pad = 4;
  return ui.Rect.fromLTRB(
    (minX - pad).clamp(0, w).toDouble(),
    (minY - pad).clamp(0, h).toDouble(),
    (maxX + 1 + pad).clamp(0, w).toDouble(),
    (maxY + 1 + pad).clamp(0, h).toDouble(),
  );
}

/// Converte qualquer imagem em bitmap 1 bit na largura do papel ([paperDots]).
Future<MonoBitmap> toMono(
  ui.Image src,
  int paperDots, {
  RasterOptions options = const RasterOptions(),
}) async {
  final srcRect = options.cropBlank
      ? await _contentBounds(src)
      : ui.Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble());

  var drawW = paperDots.toDouble();
  if (!options.fitWidth && srcRect.width < paperDots) drawW = srcRect.width;
  final scale = drawW / srcRect.width;
  var outH = (srcRect.height * scale).round();
  if (outH < 1) outH = 1;
  if (outH > 20000) outH = 20000;
  final width = paperDots; // já é múltiplo de 8 (384 ou 576)
  final dx = ((width - drawW) / 2).floorToDouble();

  // Desenha sobre fundo branco (resolve transparência) já na escala final.
  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), outH.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  canvas.drawImageRect(
    src,
    srcRect,
    ui.Rect.fromLTWH(dx, 0, drawW, outH.toDouble()),
    ui.Paint()..filterQuality = ui.FilterQuality.high,
  );
  final scaled = await rec.endRecording().toImage(width, outH);
  final data = await _rgba(scaled);
  scaled.dispose();

  // Luminância com ajuste de contraste.
  final k = 1 + options.contrast * 2;
  final lum = Float32List(width * outH);
  for (var i = 0; i < lum.length; i++) {
    final o = i * 4;
    final l = data.getUint8(o) * 0.299 +
        data.getUint8(o + 1) * 0.587 +
        data.getUint8(o + 2) * 0.114;
    lum[i] = ((l - 128) * k + 128).clamp(0, 255).toDouble();
  }

  final bpr = width ~/ 8;
  final bits = Uint8List(bpr * outH);
  // Tom da impressão (Ajustes): claro / normal / escuro.
  final shift = (AppSettings.instance.darkness.clamp(0, 2) - 1) * 30;
  if (options.dither) {
    // Floyd–Steinberg
    for (var y = 0; y < outH; y++) {
      for (var x = 0; x < width; x++) {
        final i = y * width + x;
        final old = lum[i];
        final black = old < 128 + shift;
        final err = old - (black ? 0 : 255);
        if (black) bits[y * bpr + (x >> 3)] |= (0x80 >> (x & 7));
        if (x + 1 < width) lum[i + 1] += err * 7 / 16;
        if (y + 1 < outH) {
          if (x > 0) lum[i + width - 1] += err * 3 / 16;
          lum[i + width] += err * 5 / 16;
          if (x + 1 < width) lum[i + width + 1] += err * 1 / 16;
        }
      }
    }
  } else {
    for (var y = 0; y < outH; y++) {
      for (var x = 0; x < width; x++) {
        if (lum[y * width + x] < 150 + shift) {
          bits[y * bpr + (x >> 3)] |= (0x80 >> (x & 7));
        }
      }
    }
  }
  return MonoBitmap(width, outH, bits);
}

/// Decodifica bytes de PNG/JPG/WEBP em imagem.
Future<ui.Image> decodeImageBytes(Uint8List bytes, {int? targetWidth}) async {
  final codec = await ui.instantiateImageCodec(bytes, targetWidth: targetWidth);
  final frame = await codec.getNextFrame();
  return frame.image;
}
