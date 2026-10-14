import 'package:flutter/material.dart';

import '../services/leopardo_contact.dart';
import '../theme.dart';
import '../widgets/common.dart';

class _Product {
  final IconData icon;
  final String name;
  final String detail;
  final List<String> options; // quantidades / variações
  const _Product(this.icon, this.name, this.detail, this.options);
}

/// Loja Leopardo: cada pedido abre o WhatsApp com a mensagem pronta.
class StoreScreen extends StatefulWidget {
  const StoreScreen({super.key});
  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  static const _products = [
    _Product(Icons.receipt_long_outlined, 'Bobina térmica 58 mm', 'Para impressoras portáteis de 58 mm',
        ['10 unidades', '30 unidades', '60 unidades', '100 unidades']),
    _Product(Icons.receipt_long_outlined, 'Bobina térmica 80 mm', 'Para impressoras de 80 mm',
        ['10 unidades', '30 unidades', '60 unidades', '100 unidades']),
    _Product(Icons.label_outline, 'Etiquetas adesivas', 'Etiquetas térmicas para envio e preço',
        ['Quero conhecer os tamanhos']),
    _Product(Icons.print_outlined, 'Impressoras Leopardo', 'Portáteis 58 mm e 80 mm, Bluetooth e USB',
        ['Leopardo PROMAX', 'Leopardo XR', 'Leopardo A7', 'Quero ajuda para escolher']),
    _Product(Icons.cable_outlined, 'Acessórios', 'Carregador, cabo, bateria e capa de proteção',
        ['Quero ver os acessórios']),
  ];

  final Map<int, int> _choice = {};

  Future<void> _order(_Product p, String option) async {
    final msg = p.name.startsWith('Impressoras')
        ? 'Olá! Tenho interesse em impressora Leopardo: $option. Pode me passar valores e condições?'
        : 'Olá! Quero comprar ${p.name}: $option. Pode me passar valores e prazo de entrega?';
    final ok = await LeopardoContact.whatsapp(msg);
    if (!ok && mounted) showMsg(context, 'Não foi possível abrir o WhatsApp.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Loja Leopardo')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          const Text(
            'Escolha o produto e a quantidade. O pedido abre no WhatsApp da Leopardo com a mensagem pronta.',
            style: TextStyle(fontSize: 14, color: LeoColors.text2, height: 1.45),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < _products.length; i++) ...[
            LeoCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: LeoColors.red, borderRadius: BorderRadius.circular(12)),
                    child: Icon(_products[i].icon, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_products[i].name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      Text(_products[i].detail, style: const TextStyle(fontSize: 13, color: LeoColors.muted)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (var j = 0; j < _products[i].options.length; j++)
                    ChoiceChip(
                      label: Text(_products[i].options[j]),
                      selected: (_choice[i] ?? 0) == j,
                      onSelected: (_) => setState(() => _choice[i] = j),
                    ),
                ]),
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
                    onPressed: () => _order(_products[i], _products[i].options[_choice[i] ?? 0]),
                    icon: const Icon(Icons.chat_outlined),
                    label: const Text('Pedir pelo WhatsApp', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ),
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
