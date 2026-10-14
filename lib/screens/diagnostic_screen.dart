import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/diagnostic_page.dart';
import '../services/leopardo_contact.dart';
import '../services/printer_service.dart';
import '../services/raster.dart';
import '../services/settings.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'connect_screen.dart';

/// Diagnóstico: imprime a página de teste completa e envia o relatório ao suporte.
class DiagnosticScreen extends StatefulWidget {
  const DiagnosticScreen({super.key});
  @override
  State<DiagnosticScreen> createState() => _DiagnosticScreenState();
}

class _DiagnosticScreenState extends State<DiagnosticScreen> {
  final ps = PrinterService.instance;
  final s = AppSettings.instance;
  Map<String, dynamic> _device = {};
  ui.Image? _preview;
  bool _printed = false;
  String? _photo;

  // Respostas do teste (null = não respondido)
  final Map<String, bool?> _checks = {
    'Moldura saiu completa dos dois lados': null,
    'Preto sólido sem riscos brancos': null,
    'Blocos de densidade do claro ao escuro': null,
    'Textos legíveis': null,
    'Códigos lidos pela câmera': null,
    'A última linha ("Fim do teste") saiu': null,
  };

  @override
  void initState() {
    super.initState();
    LeopardoContact.deviceInfo().then((d) {
      if (mounted) setState(() => _device = d);
      _renderPreview();
    });
  }

  static const _tones = ['Claro', 'Normal', 'Escuro'];

  String _now() {
    final d = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  List<String> _info() => [
        'Data: ${_now()}',
        'Impressora: ${ps.isConnected ? ps.deviceName : '(não conectada)'}',
        'Conexão: ${ps.isConnected ? ps.kindLabel : '-'}${ps.battery != null ? ' · Bateria ${ps.battery}%' : ''}',
        'Papel: ${s.paperMm} mm (${s.paperDots} pontos) · Tom: ${_tones[s.darkness.clamp(0, 2)]}',
        'Atraso: ${s.packetDelay} ms · Espera: ${s.disconnectWait} s · Status: ${s.statusCheck ? 'sim' : 'não'}',
        'Celular: ${_device['manufacturer'] ?? ''} ${_device['model'] ?? ''} · Android ${_device['android'] ?? '?'}',
        'App Leopardo ${_device['appVersion'] ?? ''}',
      ];

  Future<MonoBitmap> _page() async {
    final img = await DiagnosticPage.render(width: s.paperDots, info: _info());
    final m = await toMono(img, s.paperDots);
    img.dispose();
    return m;
  }

  Future<void> _renderPreview() async {
    final m = await _page();
    final img = await m.toImage();
    if (mounted) setState(() => _preview = img);
  }

  Future<void> _print() async {
    final m = await _page();
    if (!mounted) return;
    await printWithFeedback(
      context,
      pages: [m],
      title: 'Página de diagnóstico',
      subtitle: 'Diagnóstico',
      openConnect: () => openConnectScreen(context),
    );
    if (mounted) setState(() => _printed = true);
    _renderPreview();
  }

  Future<void> _pickPhoto() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image);
    final p = r?.files.single.path;
    if (p != null && mounted) setState(() => _photo = p);
  }

  String _report() {
    final b = StringBuffer()
      ..writeln('*Diagnóstico - App Leopardo*')
      ..writeln();
    for (final l in _info()) {
      b.writeln(l);
    }
    if (ps.lastError != null) b.writeln('Último erro: ${ps.lastError}');
    b
      ..writeln()
      ..writeln('*Resultado do teste:*');
    _checks.forEach((k, v) {
      b.writeln('${v == null ? '⚪' : (v ? '✅' : '❌')} $k');
    });
    b
      ..writeln()
      ..writeln(_photo == null ? 'Vou enviar a foto da página de teste em seguida.' : 'Foto da página de teste em anexo.');
    return b.toString();
  }

  Future<void> _send() async {
    final ok = await LeopardoContact.sendWhatsApp(_report(), imagePath: _photo);
    if (!ok && mounted) showMsg(context, 'Não foi possível abrir o WhatsApp.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Diagnóstico')),
      body: AnimatedBuilder(
        animation: ps,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            LeoCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(ps.isConnected ? Icons.check_circle : Icons.error_outline,
                      color: ps.isConnected ? const Color(0xFF1F7A4D) : LeoColors.red),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      ps.isConnected ? '${ps.deviceName} · ${ps.kindLabel}' : 'Nenhuma impressora conectada',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                const Text(
                  '1. Imprima a página de teste.\n'
                  '2. Confira cada item abaixo.\n'
                  '3. Tire uma foto da impressão e envie o relatório ao suporte.',
                  style: TextStyle(fontSize: 14, color: LeoColors.text2, height: 1.5),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            const SectionLabel('Página de teste'),
            PaperPreview(image: _preview, maxHeight: 700),
            const SizedBox(height: 16),
            SectionLabel(_printed ? 'Como saiu a impressão?' : 'Depois de imprimir, confira'),
            LeoCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Column(children: [
                for (final k in _checks.keys)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Expanded(child: Text(k, style: const TextStyle(fontSize: 14))),
                      ChoiceChip(
                        label: const Text('OK'),
                        selected: _checks[k] == true,
                        onSelected: (_) => setState(() => _checks[k] = true),
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: const Text('Problema'),
                        selected: _checks[k] == false,
                        onSelected: (_) => setState(() => _checks[k] = false),
                      ),
                    ]),
                  ),
              ]),
            ),
            const SizedBox(height: 16),
            LeoCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Enviar ao suporte Leopardo',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 6),
                Text(
                  'O relatório vai pelo WhatsApp ${LeopardoContact.phoneLabel} com os dados da impressora, '
                  'do celular, os ajustes e o resultado do teste.',
                  style: const TextStyle(fontSize: 13, color: LeoColors.text2, height: 1.4),
                ),
                const SizedBox(height: 12),
                OutlineAction(
                  label: _photo == null ? 'Anexar foto da página de teste' : 'Foto anexada (trocar)',
                  icon: _photo == null ? Icons.add_a_photo_outlined : Icons.check,
                  onPressed: _pickPhoto,
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1F9D55),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _send,
                    icon: const Icon(Icons.chat_outlined),
                    label: const Text('Enviar relatório pelo WhatsApp',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
      bottomNavigationBar: AnimatedBuilder(
        animation: ps,
        builder: (context, _) => PrintBar(
          busy: ps.printing,
          label: 'Imprimir página de teste',
          onPressed: _print,
        ),
      ),
    );
  }
}
