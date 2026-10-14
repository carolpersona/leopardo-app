import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/settings.dart';
import '../services/sheets.dart';
import '../theme.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatefulWidget {
  /// true quando aberta por cima de outra tela (mostra voltar e botão salvar).
  final bool standalone;
  const SettingsScreen({super.key, this.standalone = false});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final s = AppSettings.instance;
  late final _storeName = TextEditingController(text: s.storeName);
  late final _storePhone = TextEditingController(text: s.storePhone);
  late final _storeCity = TextEditingController(text: s.storeCity);
  late final _pixKey = TextEditingController(text: s.pixKey);
  late final _pixName = TextEditingController(text: s.pixName);
  late final _pixCity = TextEditingController(text: s.pixCity);
  late final _footer = TextEditingController(text: s.footer);

  bool _testing = false;

  Future<void> _testSheets() async {
    setState(() => _testing = true);
    await SheetsSync.flush();
    final msg = await SheetsSync.test();
    if (!mounted) return;
    setState(() => _testing = false);
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Conexão com a Leopardo'),
        content: Text(msg),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );
  }

  @override
  void dispose() {
    for (final c in [_storeName, _storePhone, _storeCity, _pixKey, _pixName, _pixCity, _footer]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    s.storeName = _storeName.text.trim();
    s.storePhone = _storePhone.text.trim();
    s.storeCity = _storeCity.text.trim();
    s.pixKey = _pixKey.text.trim();
    s.pixName = _pixName.text.trim();
    s.pixCity = _pixCity.text.trim();
    s.footer = _footer.text.trim();
    await s.save();
    if (!mounted) return;
    showMsg(context, 'Ajustes salvos.');
    if (widget.standalone) Navigator.of(context).pop();
  }

  Future<void> _pickLogo() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final f = r?.files.single;
    if (f == null) return;
    final bytes = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
    if (bytes == null) return;
    try {
      await s.setLogo(bytes);
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) showMsg(context, 'Não foi possível usar esta imagem.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: widget.standalone,
        title: const Text('Ajustes'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          const SectionLabel('Sua loja (aparece nos recibos)'),
          LeoCard(
            child: Column(children: [
              FieldLabel('Nome da loja',
                  TextField(controller: _storeName, textCapitalization: TextCapitalization.words)),
              const SizedBox(height: 12),
              FieldLabel('Telefone',
                  TextField(controller: _storePhone, keyboardType: TextInputType.phone)),
              const SizedBox(height: 12),
              FieldLabel('Cidade',
                  TextField(controller: _storeCity, textCapitalization: TextCapitalization.words)),
              const SizedBox(height: 14),
              Row(children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    border: Border.all(color: LeoColors.field),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: s.logoPng == null
                      ? const Center(
                          child: Text('SUA\nLOGO',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 10, color: LeoColors.muted)))
                      : Image.memory(s.logoPng!, fit: BoxFit.contain),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Wrap(spacing: 8, children: [
                    OutlinedButton(
                      onPressed: _pickLogo,
                      child: Text(s.logoPng == null ? 'Adicionar logo' : 'Trocar logo'),
                    ),
                    if (s.logoPng != null)
                      TextButton(
                        onPressed: () async {
                          await s.setLogo(null);
                          if (mounted) setState(() {});
                        },
                        child: const Text('Remover'),
                      ),
                  ]),
                ),
              ]),
            ]),
          ),
          const SizedBox(height: 18),
          const SectionLabel('PIX'),
          LeoCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FieldLabel('Chave PIX', TextField(controller: _pixKey)),
              const SizedBox(height: 6),
              const Text(
                'CPF/CNPJ só números · e-mail · celular com +55 (ex.: +5511999998888) · chave aleatória',
                style: TextStyle(fontSize: 12, color: LeoColors.muted),
              ),
              const SizedBox(height: 12),
              FieldLabel('Nome do recebedor',
                  TextField(controller: _pixName, textCapitalization: TextCapitalization.words)),
              const SizedBox(height: 12),
              FieldLabel('Cidade do recebedor',
                  TextField(controller: _pixCity, textCapitalization: TextCapitalization.words)),
            ]),
          ),
          const SizedBox(height: 18),
          const SectionLabel('Impressão'),
          LeoCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FieldLabel('Mensagem padrão no rodapé do recibo', TextField(controller: _footer)),
              const SizedBox(height: 12),
              const Text('Papel', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: LeoColors.text2)),
              const SizedBox(height: 6),
              Segmented(
                background: const Color(0xFFEFEFEA),
                options: const ['58 mm', '80 mm'],
                selected: s.paperMm == 80 ? 1 : 0,
                onChanged: (i) => setState(() => s.paperMm = i == 1 ? 80 : 58),
              ),
              SwitchRow('Reconectar sozinha ao abrir o app', s.autoReconnect,
                  (v) => setState(() => s.autoReconnect = v)),
            ]),
          ),
          const SizedBox(height: 18),
          const SectionLabel('Comandos da impressora'),
          LeoCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Tom da impressão',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: LeoColors.text2)),
              const SizedBox(height: 6),
              Segmented(
                background: const Color(0xFFEFEFEA),
                options: const ['Claro', 'Normal', 'Escuro'],
                selected: s.darkness,
                onChanged: (i) => setState(() => s.darkness = i),
              ),
              const SizedBox(height: 8),
              Row(children: [
                const Expanded(
                  child: Text('Avanço do papel no final', style: TextStyle(fontSize: 15)),
                ),
                IconButton(
                  tooltip: 'Menos',
                  onPressed: s.feedLines > 0 ? () => setState(() => s.feedLines--) : null,
                  icon: const Icon(Icons.remove),
                ),
                Text('${s.feedLines} linhas', style: const TextStyle(fontWeight: FontWeight.w600)),
                IconButton(
                  tooltip: 'Mais',
                  onPressed: s.feedLines < 12 ? () => setState(() => s.feedLines++) : null,
                  icon: const Icon(Icons.add),
                ),
              ]),
              const Text(
                'O avanço é feito com linhas em branco, depois do documento. '
                'Se as últimas linhas não saírem, aumente o avanço.',
                style: TextStyle(fontSize: 12, color: LeoColors.muted, height: 1.4),
              ),
            ]),
          ),
          const SizedBox(height: 18),
          const SectionLabel('Controle de fluxo'),
          LeoCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SwitchRow('Enviar comando de transmissão de status', s.statusCheck,
                  (v) => setState(() => s.statusCheck = v)),
              const Text(
                'Ao final de cada impressão o app pede o status à impressora e espera a resposta '
                'antes de seguir. Ajuda quando o documento sai cortado.',
                style: TextStyle(fontSize: 12, color: LeoColors.muted, height: 1.4),
              ),
              const SizedBox(height: 14),
              FieldLabel(
                'Velocidade de impressão (o envio acompanha a impressora)',
                DropdownButtonFormField<int>(
                  value: AppSettings.printSpeedOptions.contains(s.printSpeed) ? s.printSpeed : 50,
                  items: [
                    for (final v in AppSettings.printSpeedOptions)
                      DropdownMenuItem(
                          value: v,
                          child: Text(v == 0 ? 'Sem limite (mais rápido)' : (v == 50 ? '50 mm/s (recomendado)' : '$v mm/s'))),
                  ],
                  onChanged: (v) => setState(() => s.printSpeed = v ?? 50),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Se o documento sair cortado no final, diminua a velocidade (ex.: 40 ou 30 mm/s).',
                style: TextStyle(fontSize: 12, color: LeoColors.muted, height: 1.4),
              ),
              const SizedBox(height: 14),
              FieldLabel(
                'Atraso entre pacotes para impedir o estouro de buffer (ms)',
                DropdownButtonFormField<int>(
                  value: AppSettings.packetDelayOptions.contains(s.packetDelay) ? s.packetDelay : 10,
                  items: [
                    for (final v in AppSettings.packetDelayOptions)
                      DropdownMenuItem(value: v, child: Text('$v ms')),
                  ],
                  onChanged: (v) => setState(() => s.packetDelay = v ?? 10),
                ),
              ),
              const SizedBox(height: 14),
              FieldLabel(
                'Aguardar antes de desconectar (segundos)',
                DropdownButtonFormField<int>(
                  value: AppSettings.disconnectWaitOptions.contains(s.disconnectWait) ? s.disconnectWait : 1,
                  items: [
                    for (final v in AppSettings.disconnectWaitOptions)
                      DropdownMenuItem(value: v, child: Text(v == 1 ? '1 segundo' : '$v segundos')),
                  ],
                  onChanged: (v) => setState(() => s.disconnectWait = v ?? 1),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Use se a impressora não imprimir o final do documento. '
                'Vale para a impressão pelo Android (tela "Imprimir" de outros apps).',
                style: TextStyle(fontSize: 12, color: LeoColors.muted, height: 1.4),
              ),
            ]),
          ),
          const SizedBox(height: 18),
          const SectionLabel('Conexão com a Leopardo'),
          LeoCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text(
                'Garantias, pedidos da loja e indicações são enviados para a Leopardo. '
                'Toque para conferir se a conexão está funcionando.',
                style: TextStyle(fontSize: 13, color: LeoColors.text2, height: 1.4),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlineAction(
                  label: _testing ? 'Testando…' : 'Testar conexão',
                  icon: Icons.cloud_done_outlined,
                  onPressed: _testing ? null : _testSheets,
                ),
              ),
            ]),
          ),
          const SizedBox(height: 18),
          const Center(
            child: Text('App Leopardo · versão 1.0.0',
                style: TextStyle(fontSize: 12, color: LeoColors.muted)),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        color: Colors.white,
        padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + MediaQuery.of(context).padding.bottom),
        child: SizedBox(
          height: 52,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: LeoColors.ink,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            onPressed: _save,
            child: const Text('Salvar ajustes'),
          ),
        ),
      ),
    );
  }
}
