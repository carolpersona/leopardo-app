import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../services/printer_service.dart';
import '../services/raster.dart';
import '../services/settings.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'boleto_screen.dart';
import 'connect_screen.dart';

/// Imprimir PDF ou imagem (da galeria, dos arquivos ou compartilhado pelo WhatsApp).
class FilePrintScreen extends StatefulWidget {
  final String? path;
  final String? sourceLabel;
  const FilePrintScreen({super.key, this.path, this.sourceLabel});

  @override
  State<FilePrintScreen> createState() => _FilePrintScreenState();
}

class _FilePrintScreenState extends State<FilePrintScreen> {
  String? _path;
  String _source = '';
  bool _isPdf = false;
  bool _loading = false;
  String? _error;

  List<ui.Image> _pages = [];
  final Map<int, MonoBitmap> _mono = {};
  int _page = 0;
  ui.Image? _preview;
  int _renderToken = 0;

  bool _photo = false;
  double _contrast = 0.2;
  bool _fit = true;
  bool _crop = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.path != null) {
        _load(widget.path!, widget.sourceLabel ?? 'Recebido de outro app');
      } else {
        _pick();
      }
    });
  }

  Future<void> _pick() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif'],
    );
    final p = r?.files.single.path;
    if (p == null) {
      if (_path == null && mounted) Navigator.of(context).maybePop();
      return;
    }
    await _load(p, 'Escolhido no celular');
  }

  Future<void> _load(String path, String source) async {
    setState(() {
      _path = path;
      _source = source;
      _loading = true;
      _error = null;
      _pages = [];
      _mono.clear();
      _preview = null;
      _page = 0;
    });
    try {
      final bytes = await File(path).readAsBytes();
      _isPdf = path.toLowerCase().endsWith('.pdf') ||
          (bytes.length > 4 && bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46);
      final pages = <ui.Image>[];
      if (_isPdf) {
        await for (final raster in Printing.raster(bytes, dpi: 150)) {
          pages.add(await raster.toImage());
        }
      } else {
        pages.add(await decodeImageBytes(Uint8List.fromList(bytes)));
      }
      if (pages.isEmpty) throw 'arquivo sem páginas';
      _photo = !_isPdf;
      _crop = _isPdf;
      _pages = pages;
      await _renderCurrent();
    } catch (e) {
      _error = 'Não foi possível abrir este arquivo ($e).';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  RasterOptions get _opts =>
      RasterOptions(dither: _photo, contrast: _contrast, cropBlank: _crop, fitWidth: _fit || _isPdf);

  Future<MonoBitmap> _monoFor(int i) async {
    final cached = _mono[i];
    if (cached != null) return cached;
    final m = await toMono(_pages[i], AppSettings.instance.paperDots, options: _opts);
    _mono[i] = m;
    return m;
  }

  Future<void> _renderCurrent() async {
    if (_pages.isEmpty) return;
    final token = ++_renderToken;
    setState(() => _loading = true);
    final m = await _monoFor(_page);
    final img = await m.toImage();
    if (!mounted || token != _renderToken) return;
    setState(() {
      _preview = img;
      _loading = false;
    });
  }

  void _optionsChanged(VoidCallback change) {
    setState(change);
    _mono.clear();
    _renderCurrent();
  }

  Future<void> _print({required bool onlyCurrent}) async {
    final idx = onlyCurrent ? [_page] : List.generate(_pages.length, (i) => i);
    final mono = <MonoBitmap>[];
    for (final i in idx) {
      mono.add(await _monoFor(i));
    }
    if (!mounted) return;
    final name = _path == null ? 'Arquivo' : _path!.split(Platform.pathSeparator).last;
    await printWithFeedback(
      context,
      pages: mono,
      title: name,
      subtitle: _isPdf ? 'PDF · ${mono.length} página${mono.length > 1 ? 's' : ''}' : 'Imagem',
      openConnect: () => openConnectScreen(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fileName = _path == null ? 'Nenhum arquivo' : _path!.split(Platform.pathSeparator).last;
    final n = _pages.length;
    return Scaffold(
      appBar: AppBar(title: const Text('PDF ou imagem')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        children: [
          LeoCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: const Color(0xFFE9F6EE), borderRadius: BorderRadius.circular(10)),
                child: Icon(_isPdf ? Icons.picture_as_pdf_outlined : Icons.image_outlined,
                    color: const Color(0xFF1F7A4D), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  Text(
                    n > 0 ? '$_source · $n página${n > 1 ? 's' : ''}' : _source,
                    style: const TextStyle(fontSize: 12, color: LeoColors.text2),
                  ),
                ]),
              ),
              TextButton(
                onPressed: _pick,
                style: TextButton.styleFrom(foregroundColor: LeoColors.ink),
                child: const Text('Trocar', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          if (_isPdf && _path != null) ...[
            Material(
              color: const Color(0xFFFFF1F1),
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => BoletoScreen(path: _path)),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Row(children: [
                    Icon(Icons.request_page_outlined, color: LeoColors.red),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text('É um boleto? Refazer o layout para 80 mm',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    ),
                    Icon(Icons.chevron_right),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_error != null)
            LeoCard(child: Text(_error!, style: const TextStyle(color: LeoColors.red)))
          else ...[
            PaperPreview(image: _preview, loading: _loading),
            if (n > 1)
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton(
                  tooltip: 'Página anterior',
                  onPressed: _page > 0
                      ? () {
                          setState(() => _page--);
                          _renderCurrent();
                        }
                      : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('Página ${_page + 1} de $n', style: const TextStyle(fontWeight: FontWeight.w500)),
                IconButton(
                  tooltip: 'Próxima página',
                  onPressed: _page < n - 1
                      ? () {
                          setState(() => _page++);
                          _renderCurrent();
                        }
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ]),
          ],
          const SizedBox(height: 16),
          LeoCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Modo de impressão',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: LeoColors.text2)),
              const SizedBox(height: 8),
              Segmented(
                background: const Color(0xFFEFEFEA),
                options: const ['Texto nítido', 'Foto'],
                selected: _photo ? 1 : 0,
                onChanged: (i) => _optionsChanged(() => _photo = i == 1),
              ),
              const SizedBox(height: 14),
              Row(children: [
                const Expanded(
                    child: Text('Contraste',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: LeoColors.text2))),
                Text('${_contrast >= 0 ? '+' : ''}${(_contrast * 100).round()}%',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ]),
              Slider(
                value: _contrast,
                min: -0.5,
                max: 0.5,
                divisions: 20,
                onChanged: (v) => setState(() => _contrast = v),
                onChangeEnd: (v) => _optionsChanged(() => _contrast = v),
              ),
              if (!_isPdf) SwitchRow('Ajustar à largura do papel', _fit, (v) => _optionsChanged(() => _fit = v)),
              SwitchRow('Cortar margens em branco', _crop, (v) => _optionsChanged(() => _crop = v)),
            ]),
          ),
        ],
      ),
      bottomNavigationBar: AnimatedBuilder(
        animation: PrinterService.instance,
        builder: (context, _) => PrintBar(
          busy: PrinterService.instance.printing,
          leading: n > 1
              ? OutlineAction(label: 'Só esta página', onPressed: () => _print(onlyCurrent: true))
              : null,
          label: n > 1 ? 'Imprimir $n páginas' : 'Imprimir',
          onPressed: n == 0 ? null : () => _print(onlyCurrent: false),
        ),
      ),
    );
  }
}
