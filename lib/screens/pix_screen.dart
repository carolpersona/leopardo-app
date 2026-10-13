import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/money.dart';
import '../services/pix.dart';
import '../services/printer_service.dart';
import '../services/raster.dart';
import '../services/receipt_renderer.dart';
import '../services/settings.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'connect_screen.dart';
import 'settings_screen.dart';

class PixScreen extends StatefulWidget {
  const PixScreen({super.key});
  @override
  State<PixScreen> createState() => _PixScreenState();
}

class _PixScreenState extends State<PixScreen> {
  final settings = AppSettings.instance;
  final _amount = TextEditingController(text: '0,00');
  final _desc = TextEditingController();
  bool _copyPaste = true;

  MonoBitmap? _mono;
  ui.Image? _preview;
  bool _rendering = false;
  Timer? _debounce;
  int _token = 0;

  int get _cents => parseMoneyToCents(_amount.text);

  String get _payload => PixPayload(
        key: settings.pixKey,
        merchantName: settings.pixName,
        merchantCity: settings.pixCity.isEmpty ? 'BRASIL' : settings.pixCity,
        amountCents: _cents,
        description: _desc.text,
      ).build();

  @override
  void initState() {
    super.initState();
    settings.addListener(_render);
    WidgetsBinding.instance.addPostFrameCallback((_) => _render());
  }

  @override
  void dispose() {
    settings.removeListener(_render);
    _debounce?.cancel();
    _amount.dispose();
    _desc.dispose();
    super.dispose();
  }

  void _changed() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _render);
  }

  Future<void> _render() async {
    if (!mounted || !settings.hasPixKey) {
      if (mounted) setState(() {});
      return;
    }
    final token = ++_token;
    setState(() => _rendering = true);
    final img = await renderPix(
      width: settings.paperDots,
      storeName: settings.storeName,
      payload: _payload,
      amountCents: _cents,
      description: _desc.text,
      showCopyPaste: _copyPaste,
    );
    final mono = await toMono(img, settings.paperDots);
    final preview = await mono.toImage();
    if (!mounted || token != _token) return;
    setState(() {
      _mono = mono;
      _preview = preview;
      _rendering = false;
    });
  }

  Future<void> _openSettings() => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const SettingsScreen(standalone: true)));

  Future<void> _print() async {
    if (!settings.hasPixKey) {
      await _openSettings();
      return;
    }
    await _render();
    final m = _mono;
    if (m == null || !mounted) return;
    await printWithFeedback(
      context,
      pages: [m],
      title: 'PIX · ${_cents > 0 ? formatBRL(_cents) : 'valor livre'}',
      subtitle: _desc.text.trim().isEmpty ? 'Cobrança' : _desc.text.trim(),
      openConnect: () => openConnectScreen(context),
    );
  }

  Future<void> _copy() async {
    if (!settings.hasPixKey) return;
    await Clipboard.setData(ClipboardData(text: _payload));
    if (mounted) showMsg(context, 'PIX copia e cola copiado. Cole no WhatsApp do cliente.');
  }

  @override
  Widget build(BuildContext context) {
    final hasKey = settings.hasPixKey;
    return Scaffold(
      appBar: AppBar(title: const Text('Cobrança PIX')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: LeoColors.ink, borderRadius: BorderRadius.circular(18)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Valor a cobrar', style: TextStyle(fontSize: 13, color: Color(0xFFC9CBD1))),
              Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                const Text('R\$',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Color(0xFFFF6B71))),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _amount,
                    keyboardType: TextInputType.number,
                    inputFormatters: [CentsInputFormatter()],
                    onChanged: (_) => _changed(),
                    style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w800, color: Colors.white),
                    cursorColor: Colors.white,
                    decoration: const InputDecoration(
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ]),
              const Text('Deixe 0,00 para o cliente digitar o valor no banco.',
                  style: TextStyle(fontSize: 12, color: Color(0xFFC9CBD1))),
            ]),
          ),
          const SizedBox(height: 16),
          LeoCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FieldLabel('Descrição (opcional)',
                  TextField(controller: _desc, maxLength: 40, onChanged: (_) => _changed())),
              const SizedBox(height: 4),
              const Text('Receber na chave',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: LeoColors.text2)),
              const SizedBox(height: 6),
              InkWell(
                onTap: _openSettings,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: hasKey ? LeoColors.field : LeoColors.red),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(hasKey ? settings.pixKey : 'Cadastrar chave PIX',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: hasKey ? LeoColors.ink : LeoColors.red)),
                        Text(
                          hasKey
                              ? [settings.pixName, settings.pixCity].where((s) => s.isNotEmpty).join(' · ')
                              : 'Toque para informar sua chave e o nome do recebedor',
                          style: const TextStyle(fontSize: 12, color: LeoColors.muted),
                        ),
                      ]),
                    ),
                    const Icon(Icons.chevron_right),
                  ]),
                ),
              ),
              const SizedBox(height: 6),
              SwitchRow('Imprimir "copia e cola" abaixo do QR', _copyPaste, (v) {
                setState(() => _copyPaste = v);
                _render();
              }),
            ]),
          ),
          const SizedBox(height: 16),
          if (hasKey) ...[
            SectionLabel('Prévia · ${settings.paperMm} mm'),
            PaperPreview(image: _preview, loading: _rendering, maxHeight: 900),
          ],
        ],
      ),
      bottomNavigationBar: AnimatedBuilder(
        animation: PrinterService.instance,
        builder: (context, _) => PrintBar(
          busy: PrinterService.instance.printing,
          leading: OutlineAction(
            label: 'Copiar',
            icon: Icons.copy_outlined,
            onPressed: hasKey ? _copy : null,
          ),
          label: hasKey ? 'Imprimir cobrança' : 'Cadastrar chave',
          onPressed: _print,
        ),
      ),
    );
  }
}
