import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../services/doc_reflow.dart';
import '../services/printer_service.dart';
import '../services/raster.dart';
import '../services/settings.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'boleto_screen.dart';
import 'danfe_screen.dart';
import 'connect_screen.dart';

/// Imprimir PDF, imagem, Word (.docx) ou texto (.txt) — da galeria, dos arquivos ou do WhatsApp.
/// Documentos com texto podem ser reorganizados na largura da bobina, com letra maior.
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
  bool _isText = false; // Word ou .txt: sempre reorganizado
  bool _reflow = false; // reorganizar texto para a bobina
  int _fontSize = 1; // 0 pequena, 1 média, 2 grande
  List<ui.Image> _originalPages = [];
  List<DocBlock>? _blocks;
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
      allowedExtensions: const ['pdf', 'docx', 'txt', 'png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif'],
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
      _originalPages = [];
      _blocks = null;
      _reflow = false;
      _isText = false;
      _mono.clear();
      _preview = null;
      _page = 0;
    });
    try {
      final lower = path.toLowerCase();
      final bytes = await File(path).readAsBytes();
      final isZip = bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4B;
      _isPdf = lower.endsWith('.pdf') ||
          (bytes.length > 4 && bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46);
      if (lower.endsWith('.doc')) {
        throw 'arquivo .doc antigo não é suportado. Salve como .docx ou PDF e tente de novo';
      }
      if (!_isPdf && (lower.endsWith('.docx') || lower.endsWith('.txt') || (isZip && !lower.endsWith('.png')))) {
        _isText = true;
        _reflow = true;
        _blocks = lower.endsWith('.txt') ? PlainTextReader.read(bytes) : DocxReader.read(bytes);
        if (_blocks!.isEmpty) throw 'o documento não tem texto';
        _pages = await DocRenderer.render(_blocks!, AppSettings.instance.paperDots, _fontSize);
        await _renderCurrent();
        return;
      }
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
      _originalPages = pages;
      await _renderCurrent();
    } catch (e) {
      _error = 'Não foi possível abrir este arquivo ($e).';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  RasterOptions get _opts => _reflow
      ? RasterOptions(dither: false, contrast: _contrast, cropBlank: false, fitWidth: true)
      : RasterOptions(dither: _photo, contrast: _contrast, cropBlank: _crop, fitWidth: _fit || _isPdf);

  /// Liga/desliga a reorganização do texto do PDF na largura da bobina.
  Future<void> _setReflow(bool on) async {
    if (_path == null) return;
    setState(() {
      _loading = true;
      _reflow = on;
    });
    try {
      if (on) {
        _blocks ??= await PdfTextReader.read(_path!);
        if (_blocks!.isEmpty) {
          _blocks = null;
          _reflow = false;
          if (mounted) {
            showMsg(context, 'Este PDF é uma imagem (sem texto). Não dá para reorganizar, só imprimir como está.');
          }
        } else {
          _pages = await DocRenderer.render(_blocks!, AppSettings.instance.paperDots, _fontSize);
        }
      }
      if (!_reflow) _pages = _originalPages;
    } catch (e) {
      _reflow = false;
      _pages = _originalPages;
      if (mounted) showMsg(context, 'Não foi possível reorganizar o texto: $e');
    }
    _page = 0;
    _mono.clear();
    await _renderCurrent();
  }

  Future<void> _setFontSize(int level) async {
    final blocks = _blocks;
    if (blocks == null) return;
    setState(() {
      _fontSize = level;
      _loading = true;
    });
    _pages = await DocRenderer.render(blocks, AppSettings.instance.paperDots, level);
    _page = 0;
    _mono.clear();
    await _renderCurrent();
  }

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
      subtitle: _isText
          ? 'Documento'
          : _isPdf
              ? (_reflow ? 'PDF reorganizado' : 'PDF · ${mono.length} página${mono.length > 1 ? 's' : ''}')
              : 'Imagem',
      openConnect: () => openConnectScreen(context),
    );
  }

  Widget _shortcut(IconData icon, String label, Widget Function() page) => Material(
        color: const Color(0xFFFFF1F1),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => page())),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Icon(icon, color: LeoColors.red),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
              const Icon(Icons.chevron_right),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final fileName = _path == null ? 'Nenhum arquivo' : _path!.split(Platform.pathSeparator).last;
    final n = _pages.length;
    return Scaffold(
      appBar: AppBar(title: const Text('PDF, imagem ou documento')),
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
                child: Icon(
                    _isText
                        ? Icons.description_outlined
                        : (_isPdf ? Icons.picture_as_pdf_outlined : Icons.image_outlined),
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
                    n > 0 && !_reflow ? '$_source · $n página${n > 1 ? 's' : ''}' : _source,
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
            _shortcut(Icons.request_page_outlined, 'É um boleto? Refazer o layout para 80 mm',
                () => BoletoScreen(path: _path)),
            const SizedBox(height: 10),
            _shortcut(Icons.local_shipping_outlined, 'É uma nota fiscal (DANFE)? Fazer o DANFE Simplificado',
                () => DanfeScreen(path: _path)),
            const SizedBox(height: 16),
          ],
          if ((_isPdf || _isText) && _error == null) ...[
            LeoCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (_isPdf)
                  SwitchRow('Reorganizar texto para 80 mm (letra maior)', _reflow, (v) => _setReflow(v))
                else
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Text('Documento reorganizado na largura da bobina',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                if (_reflow) ...[
                  const SizedBox(height: 6),
                  const Text('Tamanho da letra',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: LeoColors.text2)),
                  const SizedBox(height: 6),
                  Segmented(
                    background: const Color(0xFFEFEFEA),
                    options: const ['Pequena', 'Média', 'Grande'],
                    selected: _fontSize,
                    onChanged: _setFontSize,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'O texto é remontado na largura do papel, com quebra de linha automática. '
                    'Imagens do documento não são impressas neste modo.',
                    style: TextStyle(fontSize: 12, color: LeoColors.muted, height: 1.4),
                  ),
                ] else
                  const Text(
                    'Ligue para imprimir o texto com letra legível, em vez de reduzir a página A4.',
                    style: TextStyle(fontSize: 12, color: LeoColors.muted, height: 1.4),
                  ),
              ]),
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
              if (!_reflow) ...[
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
              ],
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
              if (!_isPdf && !_reflow)
                SwitchRow('Ajustar à largura do papel', _fit, (v) => _optionsChanged(() => _fit = v)),
              if (!_reflow) SwitchRow('Cortar margens em branco', _crop, (v) => _optionsChanged(() => _crop = v)),
            ]),
          ),
        ],
      ),
      bottomNavigationBar: AnimatedBuilder(
        animation: PrinterService.instance,
        builder: (context, _) => PrintBar(
          busy: PrinterService.instance.printing,
          leading: n > 1 && !_reflow
              ? OutlineAction(label: 'Só esta página', onPressed: () => _print(onlyCurrent: true))
              : null,
          label: n > 1 && !_reflow ? 'Imprimir $n páginas' : 'Imprimir',
          onPressed: n == 0 ? null : () => _print(onlyCurrent: false),
        ),
      ),
    );
  }
}
