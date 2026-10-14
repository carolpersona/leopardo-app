import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/printer_service.dart';
import '../services/warranty.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Lista das impressoras cadastradas e situação da garantia.
class WarrantyScreen extends StatelessWidget {
  const WarrantyScreen({super.key});

  Future<void> _open(BuildContext context, [Warranty? w]) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => WarrantyFormScreen(existing: w)));

  @override
  Widget build(BuildContext context) {
    final store = WarrantyStore.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Cadastro e garantia')),
      body: AnimatedBuilder(
        animation: store,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            const Text(
              'Cadastre sua impressora Leopardo para ativar a garantia de $warrantyMonths meses '
              'e ter atendimento mais rápido no suporte.',
              style: TextStyle(fontSize: 14, color: LeoColors.text2, height: 1.45),
            ),
            const SizedBox(height: 16),
            for (final w in store.items) ...[
              _card(context, w),
              const SizedBox(height: 12),
            ],
            if (store.items.isEmpty)
              const LeoCard(
                child: Column(children: [
                  Icon(Icons.verified_outlined, size: 40, color: LeoColors.muted),
                  SizedBox(height: 8),
                  Text('Nenhuma impressora cadastrada', style: TextStyle(fontWeight: FontWeight.w600)),
                ]),
              ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        color: Colors.white,
        padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + MediaQuery.of(context).padding.bottom),
        child: SizedBox(
          height: 52,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: LeoColors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () => _open(context),
            icon: const Icon(Icons.add),
            label: const Text('Cadastrar impressora', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ),
        ),
      ),
    );
  }

  Widget _card(BuildContext context, Warranty w) {
    final ok = w.valida;
    return LeoCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.print_outlined, color: LeoColors.ink),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(w.modelo, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              Text('Nº de série: ${w.serie}', style: const TextStyle(fontSize: 13, color: LeoColors.muted)),
            ]),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'edit') _open(context, w);
              if (v == 'resend') WarrantyStore.instance.send(w);
              if (v == 'delete') {
                await WarrantyStore.instance.remove(w);
                if (context.mounted) showMsg(context, 'Cadastro excluído deste aparelho.');
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Editar')),
              PopupMenuItem(value: 'resend', child: Text('Reenviar cadastro')),
              PopupMenuItem(value: 'delete', child: Text('Excluir')),
            ],
          ),
        ]),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: ok ? const Color(0xFFE8F7EE) : const Color(0xFFFFF1F1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            Icon(ok ? Icons.verified : Icons.gpp_bad_outlined, color: ok ? const Color(0xFF1F7A4D) : LeoColors.red),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                ok
                    ? 'Garantia válida até ${Warranty.fmt(w.validoAte)} (${w.diasRestantes} dias)'
                    : 'Garantia vencida em ${Warranty.fmt(w.validoAte)}',
                style: TextStyle(fontWeight: FontWeight.w600, color: ok ? const Color(0xFF1F7A4D) : LeoColors.red),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        Text(
          'Compra em ${Warranty.fmt(w.dataCompra)}${w.loja.isNotEmpty ? ' · ${w.loja}' : ''}'
          '${w.enviadoEm != null ? '\nCadastro enviado à Leopardo em ${Warranty.fmt(w.enviadoEm!)}' : '\nCadastro ainda não enviado'}',
          style: const TextStyle(fontSize: 12, color: LeoColors.muted, height: 1.4),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF1F9D55),
              side: const BorderSide(color: Color(0xFF1F9D55)),
              minimumSize: const Size(0, 46),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => WarrantyStore.instance.send(w, titulo: 'Solicitação de suporte / garantia'),
            icon: const Icon(Icons.support_agent),
            label: const Text('Acionar suporte pelo WhatsApp', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }
}

/// Formulário de cadastro da impressora.
class WarrantyFormScreen extends StatefulWidget {
  final Warranty? existing;
  const WarrantyFormScreen({super.key, this.existing});
  @override
  State<WarrantyFormScreen> createState() => _WarrantyFormScreenState();
}

class _WarrantyFormScreenState extends State<WarrantyFormScreen> {
  static const _models = ['Leopardo PROMAX', 'Leopardo XR', 'Leopardo A7', 'Outro modelo'];
  final _form = GlobalKey<FormState>();
  late final Warranty? e = widget.existing;
  late final _nome = TextEditingController(text: e?.nome ?? '');
  late final _doc = TextEditingController(text: e?.documento ?? '');
  late final _tel = TextEditingController(text: e?.telefone ?? '');
  late final _email = TextEditingController(text: e?.email ?? '');
  late final _cidade = TextEditingController(text: e?.cidade ?? '');
  late final _serie = TextEditingController(text: e?.serie ?? '');
  late final _loja = TextEditingController(text: e?.loja ?? '');
  late final _outro = TextEditingController();
  late String _model = _initialModel();
  late DateTime? _data = e?.dataCompra;
  late String? _nota = e?.notaPath;
  late bool _aceita = e?.aceitaContato ?? true;
  bool _saving = false;

  String _initialModel() {
    final m = e?.modelo;
    if (m != null) {
      if (_models.contains(m)) return m;
      _outro.text = m;
      return 'Outro modelo';
    }
    // Sugere pelo nome da impressora conectada
    final n = PrinterService.instance.deviceName.toLowerCase().replaceAll(' ', '');
    if (n.contains('promax')) return 'Leopardo PROMAX';
    if (n.contains('xr')) return 'Leopardo XR';
    if (n.contains('a7')) return 'Leopardo A7';
    return _models.first;
  }

  @override
  void dispose() {
    for (final c in [_nome, _doc, _tel, _email, _cidade, _serie, _loja, _outro]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _data ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      helpText: 'Data da compra',
    );
    if (d != null) setState(() => _data = d);
  }

  Future<void> _pickNota() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image);
    final p = r?.files.single.path;
    if (p != null) setState(() => _nota = p);
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Obrigatório' : null;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_data == null) {
      showMsg(context, 'Informe a data da compra.');
      return;
    }
    setState(() => _saving = true);
    final id = e?.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    final nota = await WarrantyStore.instance.keepPhoto(_nota, id);
    final w = Warranty(
      id: id,
      nome: _nome.text.trim(),
      documento: _doc.text.trim(),
      telefone: _tel.text.trim(),
      email: _email.text.trim(),
      cidade: _cidade.text.trim(),
      modelo: _model == 'Outro modelo' ? (_outro.text.trim().isEmpty ? 'Outro modelo' : _outro.text.trim()) : _model,
      serie: _serie.text.trim(),
      dataCompra: _data!,
      loja: _loja.text.trim(),
      notaPath: nota,
      aceitaContato: _aceita,
      enviadoEm: e?.enviadoEm,
    );
    await WarrantyStore.instance.upsert(w);
    final sent = await WarrantyStore.instance.send(w);
    if (!mounted) return;
    setState(() => _saving = false);
    showMsg(context, sent ? 'Cadastro salvo. Confirme o envio no WhatsApp.' : 'Cadastro salvo no aparelho.');
    Navigator.of(context).pop();
  }

  Widget _field(String label, TextEditingController c,
          {String? Function(String?)? validator, TextInputType? type, String? hint}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: FieldLabel(
          label,
          TextFormField(
            controller: c,
            keyboardType: type,
            validator: validator,
            decoration: InputDecoration(hintText: hint),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(e == null ? 'Cadastrar impressora' : 'Editar cadastro')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            const SectionLabel('Seus dados'),
            LeoCard(
              child: Column(children: [
                _field('Nome ou razão social *', _nome, validator: _required),
                _field('CPF ou CNPJ *', _doc, validator: _required, type: TextInputType.number),
                _field('Telefone / WhatsApp *', _tel, validator: _required, type: TextInputType.phone),
                _field('E-mail', _email, type: TextInputType.emailAddress),
                _field('Cidade / UF', _cidade, hint: 'Ex.: Cotia / SP'),
              ]),
            ),
            const SizedBox(height: 16),
            const SectionLabel('Impressora'),
            LeoCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                FieldLabel(
                  'Modelo *',
                  DropdownButtonFormField<String>(
                    value: _model,
                    items: [for (final m in _models) DropdownMenuItem(value: m, child: Text(m))],
                    onChanged: (v) => setState(() => _model = v ?? _models.first),
                  ),
                ),
                if (_model == 'Outro modelo') ...[
                  const SizedBox(height: 12),
                  _field('Qual modelo?', _outro, validator: _required),
                ] else
                  const SizedBox(height: 12),
                _field('Número de série *', _serie,
                    validator: _required, hint: 'Na etiqueta embaixo da impressora (S/N)'),
                FieldLabel(
                  'Data da compra *',
                  InkWell(
                    onTap: _pickDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(suffixIcon: Icon(Icons.calendar_today_outlined)),
                      child: Text(_data == null ? 'Selecionar data' : Warranty.fmt(_data!)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _field('Loja onde comprou', _loja, hint: 'Ex.: Mercado Livre, loja física...'),
                const Text('Nota fiscal (foto)',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: LeoColors.text2)),
                const SizedBox(height: 6),
                Row(children: [
                  if (_nota != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(File(_nota!), width: 64, height: 64, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox(width: 64, height: 64)),
                    ),
                  if (_nota != null) const SizedBox(width: 12),
                  Expanded(
                    child: OutlineAction(
                      label: _nota == null ? 'Anexar foto da nota' : 'Trocar foto',
                      icon: Icons.receipt_long_outlined,
                      onPressed: _pickNota,
                    ),
                  ),
                ]),
              ]),
            ),
            const SizedBox(height: 12),
            LeoCard(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SwitchRow('Aceito receber novidades e ofertas da Leopardo', _aceita,
                  (v) => setState(() => _aceita = v)),
            ),
            const SizedBox(height: 10),
            const Text(
              'Ao salvar, o cadastro fica guardado neste celular e é enviado ao WhatsApp da Leopardo '
              'com a foto da nota. Confirme o envio na conversa.',
              style: TextStyle(fontSize: 12, color: LeoColors.muted, height: 1.4),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        color: Colors.white,
        padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + MediaQuery.of(context).padding.bottom),
        child: SizedBox(
          height: 52,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: LeoColors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Salvando…' : 'Salvar e enviar à Leopardo',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ),
        ),
      ),
    );
  }
}
