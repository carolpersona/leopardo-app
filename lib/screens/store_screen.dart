import 'package:flutter/material.dart';

import '../services/leopardo_contact.dart';
import '../services/sheets.dart';
import '../services/warranty.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Tamanho/apresentação de um modelo (ex.: 79 mm x 30 m, caixa com 30 unidades).
class _Size {
  final String label;
  final int? perBox; // unidades por caixa (bobinas)
  const _Size(this.label, [this.perBox]);
  String get description => perBox == null ? label : '$label · caixa com $perBox unidades';
}

class _Model {
  final String label;
  final List<_Size> sizes;
  final bool askQuantity;
  const _Model(this.label, this.sizes, {this.askQuantity = true});
}

class _Product {
  final IconData icon;
  final String name;
  final String detail;
  final String modelTitle;
  final List<_Model> models;
  final String unit; // "caixa" ou "unidade"
  const _Product(this.icon, this.name, this.detail, this.modelTitle, this.models, this.unit);
}

/// Loja Leopardo: o pedido abre o WhatsApp da Leopardo com a mensagem pronta.
class StoreScreen extends StatefulWidget {
  const StoreScreen({super.key});
  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  static const _products = [
    _Product(Icons.print_outlined, 'Impressoras Leopardo', 'Impressoras térmicas portáteis', 'Modelo', [
      _Model('Leopardo PROMAX', [_Size('Leopardo PROMAX')]),
      _Model('Leopardo XR', [_Size('Leopardo XR')]),
      _Model('Leopardo MXR', [_Size('Leopardo MXR')]),
      _Model('Quero ajuda para escolher', [_Size('Ajuda para escolher')], askQuantity: false),
    ], 'unidade'),
    _Product(Icons.receipt_long_outlined, 'Bobina Térmica 58 mm', 'Para impressoras de 58 mm', 'Modelo', [
      _Model('Padrão 48 grs', [_Size('58 mm x 17 metros', 80)]),
      _Model('HD 72 grs', [_Size('58 mm x 17 metros', 56)]),
    ], 'caixa'),
    _Product(Icons.receipt_long_outlined, 'Bobina Térmica 80 mm', 'Para impressoras de 80 mm', 'Modelo', [
      _Model('Padrão 48 grs', [_Size('79 mm x 20 metros', 56), _Size('79 mm x 30 metros', 30)]),
      _Model('HD 72 grs', [_Size('79 mm x 17 metros', 48)]),
    ], 'caixa'),
    _Product(Icons.label_outline, 'Etiquetas adesivas', 'Etiquetas térmicas para envio e preço', 'Opção', [
      _Model('Quero conhecer os tamanhos', [_Size('Tamanhos disponíveis')], askQuantity: false),
    ], 'unidade'),
    _Product(Icons.cable_outlined, 'Acessórios', 'Carregador, cabo, bateria e capa de proteção', 'Opção', [
      _Model('Quero ver os acessórios', [_Size('Acessórios')], askQuantity: false),
    ], 'unidade'),
  ];

  final Map<int, int> _model = {};
  final Map<int, int> _size = {};
  final Map<int, int> _qty = {};
  final _ref = TextEditingController();

  @override
  void dispose() {
    _ref.dispose();
    super.dispose();
  }

  String _plural(String unit, int n) {
    if (n == 1) return '1 $unit';
    return unit == 'caixa' ? '$n caixas' : '$n unidades';
  }

  Future<void> _order(int i) async {
    final p = _products[i];
    final m = p.models[_model[i] ?? 0];
    final s = m.sizes[_size[i] ?? 0];
    final q = _qty[i] ?? 1;
    String msg;
    if (!m.askQuantity) {
      msg = p.name.startsWith('Impressoras')
          ? 'Olá! Quero ajuda para escolher a impressora Leopardo ideal para mim.'
          : 'Olá! Tenho interesse em ${p.name}: ${m.label}. Pode me passar opções, valores e prazo?';
    } else if (p.unit == 'caixa') {
      msg = 'Olá! Quero comprar ${_plural('caixa', q)} de ${p.name} ${m.label}, '
          '${s.description}. Pode me passar valores e prazo de entrega?';
    } else {
      msg = 'Olá! Quero comprar ${_plural('unidade', q)} da impressora ${m.label}. '
          'Pode me passar valores e condições?';
    }
    final ref = _ref.text.trim().toUpperCase();
    if (ref.isNotEmpty) msg = '$msg\nCódigo de indicação: $ref';
    final ok = await LeopardoContact.whatsapp(msg);
    if (!ok && mounted) showMsg(context, 'Não foi possível abrir o WhatsApp.');

    // Registra o pedido na planilha Google (com os dados do cadastro, se houver).
    final cliente = WarrantyStore.instance.items.isNotEmpty ? WarrantyStore.instance.items.first : null;
    SheetsSync.send('pedido', {
      'Produto': p.name,
      'Modelo': m.label,
      'Tamanho': p.unit == 'caixa' ? s.description : '',
      'Quantidade': m.askQuantity ? '$q' : '',
      'Unidade': m.askQuantity ? (p.unit == 'caixa' ? 'caixa(s)' : 'unidade(s)') : '',
      'Total de bobinas': (p.unit == 'caixa' && s.perBox != null) ? '${q * s.perBox!}' : '',
      'Nome': cliente?.nome ?? '',
      'Telefone': cliente?.telefone ?? '',
      'Cidade/UF': cliente?.cidade ?? '',
      'Código de indicação': ref,
      'Mensagem': msg,
    });
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Text(t, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: LeoColors.text2)),
      );

  Widget _card(int i) {
    final p = _products[i];
    final mi = _model[i] ?? 0;
    final m = p.models[mi];
    final si = (_size[i] ?? 0).clamp(0, m.sizes.length - 1);
    final s = m.sizes[si];
    final q = _qty[i] ?? 1;
    return LeoCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: LeoColors.red, borderRadius: BorderRadius.circular(12)),
            child: Icon(p.icon, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              Text(p.detail, style: const TextStyle(fontSize: 13, color: LeoColors.muted)),
            ]),
          ),
        ]),
        _label(p.modelTitle),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var j = 0; j < p.models.length; j++)
            ChoiceChip(
              label: Text(p.models[j].label),
              selected: mi == j,
              onSelected: (_) => setState(() {
                _model[i] = j;
                _size[i] = 0;
              }),
            ),
        ]),
        if (p.unit == 'caixa') ...[
          if (m.sizes.length > 1) ...[
            _label('Tamanho'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (var j = 0; j < m.sizes.length; j++)
                ChoiceChip(
                  label: Text(m.sizes[j].label),
                  selected: si == j,
                  onSelected: (_) => setState(() => _size[i] = j),
                ),
            ]),
          ],
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: LeoColors.segment, borderRadius: BorderRadius.circular(10)),
            child: Text('${m.label} · ${s.description}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ],
        if (m.askQuantity) ...[
          _label(p.unit == 'caixa' ? 'Quantidade de caixas' : 'Quantidade'),
          Row(children: [
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: LeoColors.field),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: 'Menos',
                  onPressed: q > 1 ? () => setState(() => _qty[i] = q - 1) : null,
                  icon: const Icon(Icons.remove),
                ),
                SizedBox(
                  width: 40,
                  child: Text('$q',
                      textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                ),
                IconButton(
                  tooltip: 'Mais',
                  onPressed: q < 999 ? () => setState(() => _qty[i] = q + 1) : null,
                  icon: const Icon(Icons.add),
                ),
              ]),
            ),
            const SizedBox(width: 12),
            if (p.unit == 'caixa' && s.perBox != null)
              Expanded(
                child: Text('= ${q * s.perBox!} bobinas',
                    style: const TextStyle(fontSize: 14, color: LeoColors.text2, fontWeight: FontWeight.w500)),
              ),
          ]),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1F9D55),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => _order(i),
            icon: const Icon(Icons.chat_outlined),
            label: const Text('Pedir pelo WhatsApp', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Loja Leopardo')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          const Text(
            'Escolha o produto, o modelo e a quantidade. O pedido abre no WhatsApp da Leopardo com a mensagem pronta.',
            style: TextStyle(fontSize: 14, color: LeoColors.text2, height: 1.45),
          ),
          const SizedBox(height: 12),
          LeoCard(
            child: FieldLabel(
              'Tem um código de indicação? (opcional)',
              TextField(
                controller: _ref,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(hintText: 'Ex.: LEO-7K3PQ'),
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < _products.length; i++) ...[
            _card(i),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 4),
          Center(
            child: Text('Atendimento Leopardo: ${LeopardoContact.phoneLabel}',
                style: const TextStyle(fontSize: 13, color: LeoColors.muted)),
          ),
        ],
      ),
    );
  }
}
