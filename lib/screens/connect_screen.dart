import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../services/native_printers.dart';
import '../services/printer_service.dart';
import '../services/settings.dart';
import '../services/system_print.dart';
import '../theme.dart';
import '../widgets/common.dart';

Future<void> openConnectScreen(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const ConnectScreen(asTab: false)),
  );
}

class ConnectScreen extends StatefulWidget {
  /// Na aba "Impressoras" não há botão de voltar e a busca não fecha a tela.
  final bool asTab;
  const ConnectScreen({super.key, this.asTab = false});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final ps = PrinterService.instance;
  final settings = AppSettings.instance;

  @override
  void initState() {
    super.initState();
    // Na aba, a busca começa quando o usuário abre a aba (ver main.dart).
    if (!widget.asTab && !ps.isConnected) ps.startScan();
    ps.loadNativeDevices();
  }

  @override
  void dispose() {
    ps.stopScan();
    super.dispose();
  }

  Future<void> _connect(ScanResult r) async {
    final ok = await ps.connect(r.device, name: PrinterService.nameOf(r));
    if (!mounted) return;
    if (ok) {
      showMsg(context, 'Conectada a ${ps.deviceName}.');
      if (!widget.asTab) Navigator.of(context).pop();
    } else {
      showMsg(context, ps.lastError ?? 'Não foi possível conectar.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.asTab,
        title: const Text('Conectar impressora'),
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([ps, settings]),
        builder: (context, _) => RefreshIndicator(
          onRefresh: ps.startScan,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              if (ps.isConnected) ...[
                _connectedCard(),
                const SizedBox(height: 18),
              ],
              _scanCard(),
              if (ps.lastError != null) ...[
                const SizedBox(height: 12),
                Text(ps.lastError!, style: const TextStyle(color: LeoColors.red, fontSize: 14)),
              ],
              const SizedBox(height: 18),
              if (ps.results.isNotEmpty) ...[
                const SectionLabel('Encontradas'),
                LeoCard(
                  padding: EdgeInsets.zero,
                  child: Column(children: [
                    for (var i = 0; i < ps.results.length; i++) ...[
                      if (i > 0) const Divider(height: 1, color: Color(0xFFE8E8E3)),
                      _resultTile(ps.results[i]),
                    ],
                  ]),
                ),
                const SizedBox(height: 18),
              ],
              if (ps.bonded.isNotEmpty) ...[
                const SectionLabel('Bluetooth pareado (clássico)'),
                LeoCard(
                  padding: EdgeInsets.zero,
                  child: Column(children: [
                    for (var i = 0; i < ps.bonded.length; i++) ...[
                      if (i > 0) const Divider(height: 1, color: Color(0xFFE8E8E3)),
                      _nativeTile(ps.bonded[i]),
                    ],
                  ]),
                ),
                const SizedBox(height: 18),
              ],
              if (ps.usbDevices.isNotEmpty) ...[
                const SectionLabel('USB (cabo OTG)'),
                LeoCard(
                  padding: EdgeInsets.zero,
                  child: Column(children: [
                    for (var i = 0; i < ps.usbDevices.length; i++) ...[
                      if (i > 0) const Divider(height: 1, color: Color(0xFFE8E8E3)),
                      _nativeTile(ps.usbDevices[i]),
                    ],
                  ]),
                ),
                const SizedBox(height: 18),
              ],
              const SectionLabel('Papel'),
              LeoCard(
                child: Segmented(
                  background: const Color(0xFFEFEFEA),
                  options: const ['58 mm', '80 mm'],
                  selected: settings.paperMm == 80 ? 1 : 0,
                  onChanged: (i) {
                    settings.paperMm = i == 1 ? 80 : 58;
                    settings.save();
                  },
                ),
              ),
              const SizedBox(height: 10),
              LeoCard(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SwitchRow('Reconectar sozinha ao abrir o app', settings.autoReconnect, (v) {
                  settings.autoReconnect = v;
                  settings.save();
                }),
              ),
              const SizedBox(height: 18),
              const SectionLabel('Imprimir de qualquer app'),
              LeoCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.print_outlined, color: LeoColors.red),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Ative uma vez e as impressoras Leopardo passam a aparecer na tela '
                        '"Imprimir" do Android: PDF, navegador, galeria, documentos e outros apps.',
                        style: TextStyle(fontSize: 14, height: 1.45),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  const Text(
                    'Na tela que abrir, toque em "Leopardo" e ligue a chave. '
                    'Conecte cada impressora aqui no app pelo menos uma vez.',
                    style: TextStyle(fontSize: 13, color: LeoColors.muted, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlineAction(
                      label: 'Ativar no Android',
                      icon: Icons.settings_outlined,
                      onPressed: () async {
                        final ok = await SystemPrint.openSettings();
                        if (!ok && context.mounted) {
                          showMsg(context,
                              'Abra Configurações do celular e procure por "Impressão".');
                        }
                      },
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFB8BAB2)),
                ),
                child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Não encontrou sua impressora?',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  SizedBox(height: 8),
                  Text(
                    '1. Ligue a impressora e deixe a até 5 metros do celular.\n'
                    '2. Confira se o Bluetooth está ativo.\n'
                    '3. Permita o acesso a "Dispositivos próximos" quando o app pedir.\n'
                    '4. Se ela estiver conectada a outro celular, desconecte lá primeiro.\n'
                    '5. Puxe a tela para baixo para buscar de novo.\n'
                    '6. Impressora Bluetooth comum (não BLE)? Pareie primeiro em Configurações › Bluetooth do celular; ela aparece em "Bluetooth pareado".',
                    style: TextStyle(fontSize: 14, color: LeoColors.text2, height: 1.5),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _connectedCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: LeoColors.ink, borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          const Icon(Icons.print_outlined, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ps.deviceName,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
              Text('Conectada · ${ps.kindLabel}', style: const TextStyle(color: LeoColors.okFg, fontSize: 13)),
            ]),
          ),
          TextButton(
            onPressed: ps.disconnect,
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: const Text('Desconectar'),
          ),
        ]),
      );

  Widget _scanCard() => LeoCard(
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 18),
        child: Column(children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: LeoColors.red,
              boxShadow: [
                BoxShadow(color: const Color(0x40DA2A32), spreadRadius: ps.scanning ? 12 : 0),
              ],
            ),
            child: const Icon(Icons.bluetooth_searching, color: Colors.white, size: 34),
          ),
          const SizedBox(height: 14),
          Text(
            ps.scanning
                ? 'Procurando impressoras por perto…'
                : (ps.results.isEmpty ? 'Nenhuma impressora encontrada' : 'Busca concluída'),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          const Text('Ligue a impressora e deixe a até 5 metros do celular.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: LeoColors.muted)),
          if (!ps.scanning) ...[
            const SizedBox(height: 12),
            OutlineAction(label: 'Buscar novamente', icon: Icons.refresh, onPressed: ps.startScan),
          ],
        ]),
      );

  Future<void> _connectNative(NativePrinterInfo p) async {
    final ok = await ps.connectNative(p);
    if (!mounted) return;
    if (ok) {
      showMsg(context, 'Conectada a ${p.name}.');
      if (!widget.asTab) Navigator.of(context).pop();
    } else {
      showMsg(context, ps.lastError ?? 'Não foi possível conectar.');
    }
  }

  Widget _nativeTile(NativePrinterInfo p) {
    final isCurrent = ps.nativeId == p.id;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: p.looksLikePrinter ? LeoColors.ink : const Color(0xFF9EA19A),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(p.isUsb ? Icons.usb : Icons.bluetooth, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            Text(p.isUsb ? 'Cabo USB' : 'Pareada no Android',
                style: const TextStyle(fontSize: 12, color: LeoColors.muted)),
          ]),
        ),
        if (isCurrent)
          const Text('Conectada', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF1F7A4D)))
        else
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: LeoColors.red,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 40),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: ps.connecting ? null : () => _connectNative(p),
            child: const Text('Conectar'),
          ),
      ]),
    );
  }

  Widget _resultTile(ScanResult r) {
    final name = PrinterService.nameOf(r);
    final isCurrent = ps.device?.remoteId == r.device.remoteId && ps.isConnected;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: LeoColors.ink, borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.print_outlined, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            Text(PrinterService.signalLabel(r.rssi),
                style: const TextStyle(fontSize: 12, color: LeoColors.muted)),
          ]),
        ),
        if (isCurrent)
          const Text('Conectada', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF1F7A4D)))
        else
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: LeoColors.red,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 40),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: ps.connecting ? null : () => _connect(r),
            child: ps.connecting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Conectar'),
          ),
      ]),
    );
  }
}
