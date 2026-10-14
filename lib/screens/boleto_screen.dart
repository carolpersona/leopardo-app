import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/boleto.dart';
import '../services/boleto_renderer.dart';
import '../services/printer_service.dart';
import '../services/raster.dart';
import '../services/settings.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'connect_screen.dart';

/// Boleto A4 em PDF refeito para a bobina de 80 mm (layout deitado).
class BoletoScreen extends StatefulWidget {
  final String? path;
  const BoletoScreen({super.key, this.path});

  @override
  State<BoletoScreen> createState() => _BoletoScreenState();
}

class _BoletoScreenState extends State<BoletoScreen> {
  final settings = AppSettings.instance;
  String? _path;
  bool _reading = false;
  String? _error;
  List<BoletoData> _boletos = [];
  int _current = 0;

  final Map<String, TextEditingController> _ctrl = {};
  final Map<int, MonoBitmap> _mono = {};
  ui.Image? _preview;
  bool _rendering = false;
  int _token = 0;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.path != null) {
        _load(widget.path!);
      } else {
        _pick();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pick() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf']);
    final p = r?.files.single.path;
    if (p == null) {
      if (_path == null && mounted) Navigator.of(context).maybePop();
      return;
    }
    await _load(p);
  }

  Future<void> _load(String path) async {
    setState(() {
      _path = path;
      _reading = true;
      _error = null;
      _boletos = [];
      _mono.clear();
      _preview = null;
      _current = 0;
    });
    try {
      final list = await BoletoReader.read(path);
      if (list.isEmpty) {
        _error = 'Não encontramos um boleto neste PDF. '
            'Se for um boleto escaneado ou de conta de consumo (começa com 8), '
            'digite a linha digitável abaixo.';
        _boletos = [BoletoData()];
      } else {
        _boletos = list;
      }
    } on PlatformException catch (e) {
      _error = 'Não foi possível ler o PDF (${e.message}). Digite a linha digitável abaixo.';
      _boletos = [BoletoData()];
    } catch (e) {
      _error = 'Não foi possível ler o PDF ($e). Digite a linha digitável abaixo.';
      _boletos = [BoletoData()];
    }
    if (!mounted) return;
    setState(() => _reading = false);
    _select(0);
  }

  void _select(int i) {
    _current = i;
    final d = _boletos[i];
    for (final f in BoletoData.fields) {
      final key = f[0];
      (_ctrl[key] ??= TextEditingController()).text = d[key];
    }
    setState(() {});
    _render();
  }

  void _onEdit(String key, String value) {
    final d = _boletos[_current];
    d[key] = value;
    if (key == 'linha') {
      final bc = barcodeFromLinha(value);
      if (bc != null) {
        d.applyBarcode(bc);
        d['linha'] = value;
        for (final k in ['vencimento', 'valor', 'banco', 'bancoNome']) {
          _ctrl[k]?.text = d[k];
        }
      }
      setState(() {});
    }
    _mono.remove(_current);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _render);
  }

  Future<MonoBitmap> _monoFor(int i) async {
    final cached = _mono[i];
    if (cached != null) return cached;
    final img = await BoletoRenderer.render(_boletos[i], settings.paperDots);
    final m = await toMono(img, settings.paperDots);
    img.dispose();
    _mono[i] = m;
    return m;
  }

  Future<void> _render() async {
    if (_boletos.isEmpty) return;
    final token = ++_token;
    setState(() => _rendering = true);
    final m = await _monoFor(_current);
    final img = await m.toImage();
    if (!mounted || token != _token) return;
    setState(() {
      _preview = img;
      _rendering = false;
    });
  }

  Future<void> _print({required bool all}) async {
    final idx = all ? List.generate(_boletos.length, (i) => i) : [_current];
    for (final i in idx) {
      if (_boletos[i].barcode == null) {
        showMsg(context, 'Boleto ${i + 1}: linha digitável inválida. Confira antes de imprimir.');
        return;
      }
    }
    final pages = <MonoBitmap>[];
    for (final i in idx) {
      pages.add(await _monoFor(i));
    }
    if (!mounted) return;
    final d = _boletos[_current];
    await printWithFeedback(
      context,
      pages: pages,
      title: 'Boleto ${d['bancoNome']} · R\$ ${d['valor']}',
      subtitle: pages.length > 1 ? '${pages.length} boletos' : 'Boleto · venc. ${d['vencimento']}',
      openConnect: () => openConnectScreen(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = _path == null ? '' : _path!.split(Platform.pathSeparator).last;
    final n = _boletos.length;
    final valid = n > 0 && _boletos[_current].barcode != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Boleto em 80 mm')),
      body: _reading
          ? const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircularProgressIndicator(),
                SizedBox(height: 14),
                Text('Lendo o boleto…'),
              ]),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              children: [
                LeoCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(children: [
                    const Icon(Icons.picture_as_pdf_outlined, color: LeoColors.red),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(name.isEmpty ? 'Nenhum arquivo' : name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    TextButton(
                      onPressed: _pick,
                      style: TextButton.styleFrom(foregroundColor: LeoColors.ink),
                      child: const Text('Trocar', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),
                if (settings.paperMm != 80) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'O boleto foi pensado para bobina de 80 mm. Em 58 mm ele sai reduzido '
                    '(o código de barras continua no tamanho oficial).',
                    style: TextStyle(fontSize: 13, color: LeoColors.text2),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: const TextStyle(color: LeoColors.red, fontSize: 14)),
                ],
                if (n > 1) ...[
                  const SizedBox(height: 14),
                  SectionLabel('$n boletos neste PDF'),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (var i = 0; i < n; i++)
                      ChoiceChip(
                        label: Text('${i + 1} · ${_boletos[i]['vencimento']}'),
                        selected: i == _current,
                        onSelected: (_) => _select(i),
                      ),
                  ]),
                ],
                const SizedBox(height: 16),
                SectionLabel('Prévia · ${settings.paperMm} mm'),
                PaperPreview(image: _preview, loading: _rendering, maxHeight: 2400),
                const SizedBox(height: 16),
                LeoCard(
                  padding: EdgeInsets.zero,
                  child: Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      initiallyExpanded: _error != null,
                      title: const Text('Conferir e editar dados',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                      subtitle: Text(
                        valid
                            ? 'Venc. ${_boletos[_current]['vencimento']} · R\$ ${_boletos[_current]['valor']}'
                            : 'Linha digitável inválida',
                        style: TextStyle(fontSize: 13, color: valid ? LeoColors.muted : LeoColors.red),
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        for (final f in BoletoData.fields)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: FieldLabel(
                              f[1],
                              TextField(
                                controller: _ctrl[f[0]],
                                minLines: 1,
                                maxLines: BoletoData.multiline.contains(f[0]) ? 6 : 1,
                                keyboardType: f[0] == 'linha' ? TextInputType.number : null,
                                onChanged: (v) => _onEdit(f[0], v),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: AnimatedBuilder(
        animation: PrinterService.instance,
        builder: (context, _) => PrintBar(
          busy: PrinterService.instance.printing,
          leading: n > 1 ? OutlineAction(label: 'Só este', onPressed: () => _print(all: false)) : null,
          label: n > 1 ? 'Imprimir $n boletos' : 'Imprimir boleto',
          onPressed: (_reading || n == 0) ? null : () => _print(all: n > 1),
        ),
      ),
    );
  }
}
