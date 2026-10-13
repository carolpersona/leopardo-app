import 'dart:typed_data';

import 'raster.dart';

/// Comandos ESC/POS usados pelo app. Tudo é impresso como imagem (GS v 0),
/// o que garante acentos, logo e QR Code de qualquer tamanho (inclusive PIX).
class EscPos {
  static const List<int> init = [0x1B, 0x40]; // ESC @
  static const List<int> cutPartial = [0x1D, 0x56, 0x42, 0x00]; // GS V 66 0
  static const List<int> openDrawer = [0x1B, 0x70, 0x00, 0x19, 0xFA]; // ESC p 0

  static List<int> feed(int lines) =>
      [0x1B, 0x64, lines < 0 ? 0 : (lines > 255 ? 255 : lines)]; // ESC d n

  /// Imagem em faixas de [band] linhas, para não estourar o buffer da impressora.
  static List<int> raster(MonoBitmap bmp, {int band = 96}) {
    final out = <int>[];
    final bpr = bmp.bytesPerRow;
    for (var y = 0; y < bmp.height; y += band) {
      final h = (bmp.height - y) < band ? (bmp.height - y) : band;
      out.addAll([
        0x1D, 0x76, 0x30, 0x00, // GS v 0, modo normal
        bpr & 0xFF, (bpr >> 8) & 0xFF,
        h & 0xFF, (h >> 8) & 0xFF,
      ]);
      out.addAll(bmp.bits.sublist(y * bpr, (y + h) * bpr));
    }
    return out;
  }

  static Uint8List job(
    List<MonoBitmap> pages, {
    int copies = 1,
    int feedLines = 4,
    bool cut = false,
    bool openDrawer = false,
  }) {
    final out = <int>[...init];
    if (openDrawer) out.addAll(EscPos.openDrawer);
    for (var c = 0; c < copies; c++) {
      for (final p in pages) {
        out.addAll(raster(p));
        out.addAll(feed(feedLines));
      }
      if (cut) out.addAll(cutPartial);
    }
    return Uint8List.fromList(out);
  }
}
