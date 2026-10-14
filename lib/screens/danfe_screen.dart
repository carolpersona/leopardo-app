import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/danfe.dart';
import '../services/printer_service.dart';
import '../services/raster.dart';
import '../services/settings.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'connect_screen.dart';

/// DANFE A4 (PDF da NF-e) refeito como DANFE Simplificado na bobina.
class DanfeScreen extends StatefulWidget {
  final String? path;
  const DanfeScreen({super.key, this.path});

  @override
  State<DanfeScreen> createState() => _DanfeScreenState();
}

class _DanfeScreenState extends State<DanfeScreen> {
  final settings = AppSettings.instance;
  String? _path;
  bool _reading = false;
  String? _error;
  List<Map<String, dynamic>> _notas = [];
  int _current = 0;
  bool _valorTotal = true;

  final Map<String, TextEditingController> _ctrl = {};
  final Map<int, MonoBitmap> _mono = {};
  ui.Image? _preview;
  bool _rendering = false;
  int _token = 0;
  Timer? _debounce;

  bool get _etiqueta => settings.danfeEtiqueta;

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
      _notas = [];
      _mono.clear();
      _preview = null;
      _current = 0;
    });
    try {
      _notas = await DanfeService.read(path);
      if (_notas.isEmpty) {
        _error = 'Não encontramos a chave de acesso de uma NF-e neste PDF. '
            'Confira se o arquivo é o DANFE (nota fiscal) em PDF.';
      }
    } on PlatformException catch (e) {
      _error = 'Não foi possível ler o PDF (${e.message}).';
    } catch (e) {
      _error = 'Não foi possível ler o PDF ($e).';
    }
    if (!mounted) return;
    setState(() => _reading = false);
    if (_notas.isNotEmpty) _select(0);
  }

  void _select(int i) {
    _current = i;
    final d = _notas[i];
    for (final f in DanfeService.fields) {
      (_ctrl[f[0]] ??= TextEditingController()).text = '${d[f[0]] ?? ''}';
    }
    setState(() {});
    _render();
  }

  void _onEdit(String key, String value) {
    _notas[_current][key] = value;
    _mono.remove(_current);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _render);
    setState(() {});
  }

  void _setMode(bool etiqueta) {
    settings.danfeEtiqueta = etiqueta;
    settings.save();
    _mono.clear();
    _render();
  }

  Future<MonoBitmap> _monoFor(int i) async {
    final cached = _mono[i];
    if (cached != null) return cached;
    final dots = settings.paperDots;
    final img = await DanfeService.render(_notas[i], dots, etiqueta: _etiqueta, valorTotal: _valorTotal);
    final m = await toMono(img, dots);
    img.dispose();
    _mono[i] = m;
    return m;
  }

  Future<void> _render() async {
    if (_notas.isEmpty) return;
    final token = ++_token;
    setState(() => _rendering = true);
    try {
      final m = await _monoFor(_current);
      final img = await m.toImage();
      if (!mounted || token != _token) return;
      setState(() {
        _preview = img;
        _rendering = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _rendering = false;
        _error = 'Não foi possível montar o DANFE ($e).';
      });
    }
  }

  Future<void> _print({required bool all}) async {
    final idx = all ? List.generate(_notas.length, (i) => i) : [_current];
    final pages = <MonoBitmap>[];
    for (final i in idx) {
      pages.add(await _monoFor(i));
    }
    if (!mounted) return;
    final d = _notas[_current];
    await printWithFeedback(
      context,
      pages: pages,
      title: 'DANFE NF-e ${d['numero']} · R\$ ${d['vNF']}',
      subtitle: pages.length > 1
          ? '${pages.length} DANFEs simplificados'
          : 'DANFE Simplificado${_etiqueta ? ' - Etiqueta' : ''} · ${d['destNome'] ?? ''}',
      openConnect: () => openConnectScreen(context),
    );
  }

  Widget _summary(Map<String, dynamic> d) {
    Widget row(String a, String b) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 92, child: Text(a, style: const TextStyle(fontSize: 13, color: LeoColors.muted))),
            Expanded(child: Text(b, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
          ]),
        );
    final itens = (d['itens'] as List?)?.length ?? 0;
    return LeoCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        row('NF-e', 'Nº ${d['numero']} · Série ${d['serie']}'),
        row('Emitente', '${d['emitNome'] ?? ''}'),
        row('Destinatário', '${d['destNome'] ?? ''}'),
        row('Emissão', '${d['emissao'] ?? ''}'),
        row('Valor', 'R\$ ${d['vNF'] ?? ''}'),
        row('Itens', '$itens'),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = _path == null ? '' : _path!.split(Platform.pathSeparator).last;
    final n = _notas.length;
    final d = n > 0 ? _notas[_current] : null;
    final missing = d == null ? const <String>[] : DanfeService.missing(d);
    return Scaffold(
      appBar: AppBar(title: const Text('DANFE Simplificado')),
      body: _reading
          ? const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircularProgressIndicator(),
                SizedBox(height: 14),
                Text('Lendo a nota fiscal…'),
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
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: const TextStyle(color: LeoColors.red, fontSize: 14)),
                ],
                if (d != null) ...[
                  const SizedBox(height: 16),
                  const SectionLabel('Modelo'),
                  Segmented(
                    options: const ['Completo (com itens)', 'Etiqueta'],
                    selected: _etiqueta ? 1 : 0,
                    onChanged: (i) => _setMode(i == 1),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _etiqueta
                        ? 'DANFE Simplificado - Etiqueta: emitente, destinatário, chave de acesso e protocolo, '
                            'para colar na embalagem.'
                        : 'Com os produtos, totais, transporte e informações complementares.',
                    style: const TextStyle(fontSize: 13, color: LeoColors.muted, height: 1.4),
                  ),
                  if (_etiqueta)
                    SwitchRow('Mostrar o valor total da nota', _valorTotal, (v) {
                      setState(() => _valorTotal = v);
                      _mono.clear();
                      _render();
                    }),
                  if (d['chaveAviso'] == true) ...[
                    const SizedBox(height: 10),
                    const Text('Atenção: o dígito verificador da chave de acesso não confere. '
                        'Confira se o PDF é de uma NF-e autorizada.',
                        style: TextStyle(color: LeoColors.red, fontSize: 14)),
                  ],
                  if (missing.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text('Não encontramos: ${missing.join(', ')}. Confira em "Conferir dados" antes de imprimir.',
                        style: const TextStyle(color: LeoColors.red, fontSize: 14)),
                  ],
                  if (n > 1) ...[
                    const SizedBox(height: 14),
                    SectionLabel('$n notas neste PDF'),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (var i = 0; i < n; i++)
                        ChoiceChip(
                          label: Text('NF ${_notas[i]['numero']}'),
                          selected: i == _current,
                          onSelected: (_) => _select(i),
                        ),
                    ]),
                  ],
                  const SizedBox(height: 16),
                  _summary(d),
                  const SizedBox(height: 16),
                  SectionLabel('Prévia · ${settings.paperMm} mm'),
                  PaperPreview(image: _preview, loading: _rendering, maxHeight: 3000),
                  const SizedBox(height: 16),
                  LeoCard(
                    padding: EdgeInsets.zero,
                    child: Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        initiallyExpanded: missing.isNotEmpty,
                        title: const Text('Conferir dados',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                        subtitle: const Text('Os dados devem ser iguais aos da nota fiscal',
                            style: TextStyle(fontSize: 13, color: LeoColors.muted)),
                        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        children: [
                          for (final f in DanfeService.fields)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: FieldLabel(
                                f[1],
                                TextField(
                                  controller: _ctrl[f[0]],
                                  minLines: 1,
                                  maxLines: DanfeService.multiline.contains(f[0]) ? 6 : 1,
                                  onChanged: (v) => _onEdit(f[0], v),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'O DANFE Simplificado pode ser usado em vendas fora do estabelecimento, no varejo para '
                    'consumidor final e no comércio eletrônico (Ajuste SINIEF 07/05). Os dados são copiados '
                    'do DANFE original.',
                    style: TextStyle(fontSize: 12, color: LeoColors.muted, height: 1.4),
                  ),
                ],
              ],
            ),
      bottomNavigationBar: AnimatedBuilder(
        animation: PrinterService.instance,
        builder: (context, _) => PrintBar(
          busy: PrinterService.instance.printing,
          leading: n > 1 ? OutlineAction(label: 'Só esta', onPressed: () => _print(all: false)) : null,
          label: n > 1 ? 'Imprimir $n DANFEs' : 'Imprimir DANFE',
          onPressed: (_reading || n == 0) ? null : () => _print(all: n > 1),
        ),
      ),
    );
  }
}
