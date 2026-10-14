import 'package:flutter/material.dart';

import '../services/history.dart';
import '../services/printer_service.dart';
import '../services/raster.dart';
import '../services/receipt_renderer.dart';
import '../services/settings.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'connect_screen.dart';
import 'boleto_screen.dart';
import 'file_print_screen.dart';
import 'pix_screen.dart';
import 'receipt_screen.dart';

class HomeScreen extends StatelessWidget {
  final VoidCallback onOpenSettings;
  const HomeScreen({super.key, required this.onOpenSettings});

  void _push(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  Future<void> _testPrint(BuildContext context) async {
    final ps = PrinterService.instance;
    final s = AppSettings.instance;
    final img = await renderTestPage(
        width: s.paperDots, printerName: ps.deviceName.isEmpty ? '-' : ps.deviceName, paperMm: s.paperMm);
    final mono = await toMono(img, s.paperDots);
    if (!context.mounted) return;
    await printWithFeedback(
      context,
      pages: [mono],
      title: 'Página de teste',
      subtitle: 'Teste',
      openConnect: () => openConnectScreen(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ps = PrinterService.instance;
    final s = AppSettings.instance;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
            child: Row(children: [
              Image.asset('assets/logo.png', height: 40, semanticLabel: 'Impressoras Leopardo'),
              const Spacer(),
              IconButton(
                tooltip: 'Ajustes',
                onPressed: onOpenSettings,
                icon: const Icon(Icons.settings_outlined),
              ),
            ]),
          ),
          const Divider(height: 1, color: LeoColors.line),
          Expanded(
            child: AnimatedBuilder(
              animation: Listenable.merge([ps, s, PrintHistory.instance]),
              builder: (context, _) => ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  _printerCard(context, ps, s),
                  const SizedBox(height: 22),
                  const Text('O que você quer imprimir?',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  _option(context, Icons.picture_as_pdf_outlined, 'PDF ou imagem',
                      'Da galeria, arquivos ou WhatsApp', () => _push(context, const FilePrintScreen())),
                  _option(context, Icons.request_page_outlined, 'Boleto em 80 mm',
                      'PDF A4 refeito para a bobina', () => _push(context, const BoletoScreen())),
                  _option(context, Icons.receipt_long_outlined, 'Texto e recibo',
                      'Recibo com itens, total e sua logo', () => _push(context, const ReceiptScreen())),
                  _option(context, Icons.qr_code_2, 'Cobrança PIX', 'Gera e imprime o QR Code do valor',
                      () => _push(context, const PixScreen())),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFB8BAB2)),
                    ),
                    child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.ios_share, size: 22),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text.rich(TextSpan(
                          style: TextStyle(fontSize: 14, height: 1.45),
                          children: [
                            TextSpan(text: 'Recebeu um pedido no WhatsApp? Toque em '),
                            TextSpan(text: 'Compartilhar', style: TextStyle(fontWeight: FontWeight.w700)),
                            TextSpan(text: ' e escolha '),
                            TextSpan(text: 'Leopardo', style: TextStyle(fontWeight: FontWeight.w700)),
                            TextSpan(text: ' para imprimir na hora.'),
                          ],
                        )),
                      ),
                    ]),
                  ),
                  if (PrintHistory.instance.jobs.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    const Text('Recentes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    LeoCard(
                      padding: EdgeInsets.zero,
                      child: Column(children: [
                        for (var i = 0; i < PrintHistory.instance.jobs.length; i++) ...[
                          if (i > 0) const Divider(height: 1, color: Color(0xFFE8E8E3)),
                          _recent(context, PrintHistory.instance.jobs[i]),
                        ],
                      ]),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _printerCard(BuildContext context, PrinterService ps, AppSettings s) {
    final connected = ps.isConnected;
    final name = connected
        ? ps.deviceName
        : (s.lastPrinterName.isNotEmpty ? s.lastPrinterName : 'Nenhuma impressora');
    Widget stat(String label, String value) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: LeoColors.inkSoft, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFFC9CBD1))),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
            ]),
          ),
        );
    final outline = OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      side: const BorderSide(color: LeoColors.inkLine),
      minimumSize: const Size(0, 44),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
    );
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: LeoColors.ink, borderRadius: BorderRadius.circular(18)),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Impressora', style: TextStyle(fontSize: 13, color: Color(0xFFC9CBD1))),
              const SizedBox(height: 4),
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: connected ? LeoColors.okBg : LeoColors.offBg,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.circle, size: 8, color: connected ? LeoColors.okFg : LeoColors.offFg),
              const SizedBox(width: 6),
              Text(
                ps.connecting ? 'Conectando…' : (connected ? 'Conectada' : 'Desconectada'),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: connected ? LeoColors.okFg : LeoColors.offFg),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          stat('Bateria', connected && ps.battery != null ? '${ps.battery}%' : '—'),
          const SizedBox(width: 8),
          stat('Papel', '${s.paperMm} mm'),
          const SizedBox(width: 8),
          stat('Conexão', connected ? ps.kindLabel : '—'),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              style: outline,
              onPressed: connected ? () => _testPrint(context) : null,
              child: const Text('Imprimir teste'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: connected
                ? OutlinedButton(
                    style: outline,
                    onPressed: () => openConnectScreen(context),
                    child: const Text('Trocar'),
                  )
                : FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: LeoColors.red,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 44),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => openConnectScreen(context),
                    child: const Text('Conectar'),
                  ),
          ),
        ]),
      ]),
    );
  }

  Widget _option(BuildContext context, IconData icon, String title, String subtitle, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: LeoColors.red, borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 13, color: LeoColors.muted)),
                ]),
              ),
              const Icon(Icons.chevron_right, color: LeoColors.muted),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _recent(BuildContext context, PrintJob job) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(job.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
              Text('${job.subtitle} · ${job.timeLabel}',
                  style: const TextStyle(fontSize: 12, color: LeoColors.muted)),
            ]),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: LeoColors.ink, minimumSize: const Size(0, 44)),
            onPressed: () => printWithFeedback(
              context,
              pages: job.pages,
              title: job.title,
              subtitle: job.subtitle,
              openConnect: () => openConnectScreen(context),
            ),
            child: const Text('Reimprimir', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ]),
      );
}
