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
import 'diagnostic_screen.dart';
import 'history_screen.dart';
import 'store_screen.dart';
import 'warranty_screen.dart';
import 'referral_screen.dart';
import 'tutorials_screen.dart';
import '../services/content.dart';
import '../services/warranty.dart';
import '../services/leopardo_contact.dart';
import 'file_print_screen.dart';
import 'pix_screen.dart';
import 'receipt_screen.dart';

class HomeScreen extends StatelessWidget {
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenHistory;
  const HomeScreen({super.key, required this.onOpenSettings, required this.onOpenHistory});

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
              animation: Listenable.merge([ps, s, PrintHistory.instance, ContentService.instance, WarrantyStore.instance]),
              builder: (context, _) => ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  _printerCard(context, ps, s),
                  for (final w in WarrantyStore.instance.attention) ...[
                    const SizedBox(height: 12),
                    _warrantyBanner(context, w),
                  ],
                  for (final a in ContentService.instance.avisos.take(3)) ...[
                    const SizedBox(height: 12),
                    _aviso(context, a),
                  ],
                  const SizedBox(height: 22),
                  const Text('O que você quer imprimir?',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  _option(context, Icons.picture_as_pdf_outlined, 'PDF, imagem ou Word',
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
                    Row(children: [
                      const Expanded(
                        child: Text('Recentes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      ),
                      TextButton(
                        onPressed: onOpenHistory,
                        style: TextButton.styleFrom(foregroundColor: LeoColors.ink),
                        child: const Text('Ver tudo', style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ]),
                    LeoCard(
                      padding: EdgeInsets.zero,
                      child: Column(children: [
                        for (var i = 0; i < PrintHistory.instance.jobs.length && i < 3; i++) ...[
                          if (i > 0) const Divider(height: 1, color: Color(0xFFE8E8E3)),
                          _recent(context, PrintHistory.instance.jobs[i]),
                        ],
                      ]),
                    ),
                  ],
                  const SizedBox(height: 22),
                  const Text('Leopardo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  _whatsappCard(),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: _smallTile(context, Icons.storefront_outlined, 'Loja Leopardo',
                          'Bobinas e impressoras', () => _push(context, const StoreScreen())),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _smallTile(context, Icons.health_and_safety_outlined, 'Diagnóstico',
                          'Testar a impressora', () => _push(context, const DiagnosticScreen())),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: _smallTile(context, Icons.play_circle_outline, 'Tutoriais',
                          'Vídeos e guias rápidos', () => _push(context, const TutorialsScreen())),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _smallTile(context, Icons.card_giftcard, 'Indique e ganhe',
                          'Compartilhe seu código', () => _push(context, const ReferralScreen())),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  _smallTile(context, Icons.verified_outlined, 'Cadastro e garantia',
                      'Cadastre sua impressora e ative a garantia', () => _push(context, const WarrantyScreen())),
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

  void _runAction(BuildContext context, String acao) {
    final a = acao.trim();
    final low = a.toLowerCase();
    if (low == 'loja') return _push(context, const StoreScreen());
    if (low == 'tutoriais') return _push(context, const TutorialsScreen());
    if (low == 'garantia') return _push(context, const WarrantyScreen());
    if (low == 'indique' || low == 'indicacao' || low == 'indicação') return _push(context, const ReferralScreen());
    if (low.startsWith('whatsapp')) {
      final msg = a.contains(':') ? a.substring(a.indexOf(':') + 1).trim() : '';
      LeopardoContact.whatsapp(msg.isEmpty ? 'Olá! Vi um aviso no app Leopardo.' : msg);
      return;
    }
    if (low.startsWith('http')) LeopardoContact.openUrl(a);
  }

  Widget _aviso(BuildContext context, Aviso a) {
    final hasAction = a.acao.trim().isNotEmpty;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: hasAction ? () => _runAction(context, a.acao) : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (a.imagem.startsWith('http'))
            AspectRatio(
              aspectRatio: 2,
              child: Image.network(a.imagem, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(color: LeoColors.segment)),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (a.titulo.isNotEmpty)
                Text(a.titulo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              if (a.texto.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(a.texto, style: const TextStyle(fontSize: 14, color: LeoColors.text2, height: 1.4)),
              ],
              if (hasAction && a.botao.isNotEmpty) ...[
                const SizedBox(height: 10),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: LeoColors.red,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => _runAction(context, a.acao),
                  child: Text(a.botao, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _warrantyBanner(BuildContext context, Warranty w) {
    final vencida = !w.valida;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: vencida ? const Color(0xFFFFF1F1) : const Color(0xFFFFF7E0),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(vencida ? Icons.gpp_bad_outlined : Icons.schedule, color: vencida ? LeoColors.red : const Color(0xFF9A6B00)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              vencida
                  ? 'A garantia da sua ${w.modelo} venceu em ${Warranty.fmt(w.validoAte)}'
                  : 'A garantia da sua ${w.modelo} vence em ${w.diasRestantes} dias (${Warranty.fmt(w.validoAte)})',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton(
            onPressed: () => LeopardoContact.whatsapp(vencida
                ? 'Olá! A garantia da minha ${w.modelo} (série ${w.serie}) venceu. Quero saber sobre revisão e novos modelos.'
                : 'Olá! A garantia da minha ${w.modelo} (série ${w.serie}) vence em ${Warranty.fmt(w.validoAte)}. Quero agendar uma revisão.'),
            child: Text(vencida ? 'Revisão ou novo modelo' : 'Agendar revisão'),
          ),
          TextButton(
            onPressed: () => _push(context, const StoreScreen()),
            child: const Text('Ver impressoras'),
          ),
        ]),
      ]),
    );
  }

  Widget _whatsappCard() => Material(
        color: const Color(0xFFE8F7EE),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => LeopardoContact.whatsapp(),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: const Color(0xFF1F9D55), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.chat_outlined, color: Colors.white),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Entre em contato com a Leopardo',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  SizedBox(height: 2),
                  Text('WhatsApp ${LeopardoContact.phoneLabel}',
                      style: TextStyle(fontSize: 13, color: LeoColors.text2)),
                ]),
              ),
              const Icon(Icons.chevron_right, color: LeoColors.muted),
            ]),
          ),
        ),
      );

  Widget _smallTile(BuildContext context, IconData icon, String title, String sub, VoidCallback onTap) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, color: LeoColors.red),
              const SizedBox(height: 8),
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              Text(sub, style: const TextStyle(fontSize: 12, color: LeoColors.muted)),
            ]),
          ),
        ),
      );

  Widget _recent(BuildContext context, PrintJob job) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(job.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
              Text('${job.subtitle} · ${job.dateLabel}',
                  style: const TextStyle(fontSize: 12, color: LeoColors.muted)),
            ]),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: LeoColors.ink, minimumSize: const Size(0, 44)),
            onPressed: () => reprintJob(context, job),
            child: const Text('Reimprimir', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ]),
      );
}
