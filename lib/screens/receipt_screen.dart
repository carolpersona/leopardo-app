import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/money.dart';
import '../services/printer_service.dart';
import '../services/raster.dart';
import '../services/receipt_renderer.dart';
import '../services/settings.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'connect_screen.dart';

class _ItemCtrl {
  final qty = TextEditingController(text: '1');
  final desc = TextEditingController();
  final price = TextEditingController(text: '0,00');
  void dispose() {
    qty.dispose();
    desc.dispose();
    price.dispose();
  }

  ReceiptItem toItem() => ReceiptItem(
        qty: int.tryParse(qty.text) ?? 1,
        desc: desc.text,
        priceCents: parseMoneyToCents(price.text),
      );
}

class ReceiptScreen extends StatefulWidget {
  const ReceiptScreen({super.key});
  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  final settings = AppSettings.instance;
  int _mode = 1; // 0 = texto livre, 1 = recibo

  // Texto livre
  final _free = TextEditingController();
  bool _large = false;
  bool _bold = false;
  bool _center = false;

  // Recibo
  final _client = TextEditingController();
  final List<_ItemCtrl> _items = [_ItemCtrl()];
  late final TextEditingController _footer = TextEditingController(text: settings.footer);
  bool _showLogo = true;
  bool _showPayment = true;
  String _payment = 'PIX';
  static const _payments = ['PIX', 'Dinheiro', 'Cartão de débito', 'Cartão de crédito'];

  int _copies = 1;
  MonoBitmap? _mono;
  ui.Image? _preview;
  bool _rendering = false;
  Timer? _debounce;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _render());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _free.dispose();
    _client.dispose();
    _footer.dispose();
    for (final i in _items) {
      i.dispose();
    }
    super.dispose();
  }

  void _changed() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _render);
  }

  Future<void> _render() async {
    final token = ++_token;
    setState(() => _rendering = true);
    final w = settings.paperDots;
    final ui.Image img = _mode == 0
        ? await renderFreeText(width: w, text: _free.text, large: _large, bold: _bold, center: _center)
        : await renderReceipt(
            width: w,
            storeName: settings.storeName,
            storePhone: settings.storePhone,
            storeCity: settings.storeCity,
            logo: _showLogo ? settings.logoImage : null,
            client: _client.text,
            items: _items.map((e) => e.toItem()).toList(),
            payment: _showPayment ? _payment : null,
            footer: _footer.text,
          );
    final mono = await toMono(img, w);
    final preview = await mono.toImage();
    if (!mounted || token != _token) return;
    setState(() {
      _mono = mono;
      _preview = preview;
      _rendering = false;
    });
  }

  Future<void> _print() async {
    await _render();
    final m = _mono;
    if (m == null || !mounted) return;
    await printWithFeedback(
      context,
      pages: [m],
      copies: _copies,
      title: _mode == 0 ? 'Texto' : 'Recibo${_client.text.trim().isEmpty ? '' : ' · ${_client.text.trim()}'}',
      subtitle: _mode == 0 ? 'Texto livre' : 'Recibo',
      openConnect: () => openConnectScreen(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Texto e recibo')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        children: [
          Segmented(
            options: const ['Texto livre', 'Recibo'],
            selected: _mode,
            onChanged: (i) {
              setState(() => _mode = i);
              _render();
            },
          ),
          const SizedBox(height: 16),
          LeoCard(child: _mode == 0 ? _freeForm() : _receiptForm()),
          const SizedBox(height: 16),
          SectionLabel('Prévia · ${settings.paperMm} mm'),
          PaperPreview(image: _preview, loading: _rendering, maxHeight: 900),
        ],
      ),
      bottomNavigationBar: AnimatedBuilder(
        animation: PrinterService.instance,
        builder: (context, _) => PrintBar(
          busy: PrinterService.instance.printing,
          leading: _copiesStepper(),
          label: 'Imprimir',
          onPressed: _print,
        ),
      ),
    );
  }

  Widget _freeForm() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: _free,
          minLines: 5,
          maxLines: 12,
          onChanged: (_) => _changed(),
          decoration: const InputDecoration(hintText: 'Digite ou cole o texto (ex.: pedido do WhatsApp)'),
        ),
        const SizedBox(height: 8),
        SwitchRow('Letra grande', _large, (v) {
          setState(() => _large = v);
          _render();
        }),
        SwitchRow('Negrito', _bold, (v) {
          setState(() => _bold = v);
          _render();
        }),
        SwitchRow('Centralizado', _center, (v) {
          setState(() => _center = v);
          _render();
        }),
      ]);

  Widget _receiptForm() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FieldLabel(
          'Cliente',
          TextField(controller: _client, onChanged: (_) => _changed(), textCapitalization: TextCapitalization.words),
        ),
        const SizedBox(height: 14),
        const Text('Itens', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: LeoColors.text2)),
        const SizedBox(height: 6),
        for (var i = 0; i < _items.length; i++) _itemRow(i),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: LeoColors.ink,
              side: const BorderSide(color: Color(0xFF9EA19A)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              setState(() => _items.add(_ItemCtrl()));
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Adicionar item', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            'Total: ${formatBRL(_items.fold<int>(0, (s, e) => s + e.toItem().total))}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
        ),
        const Divider(height: 24, color: Color(0xFFE8E8E3)),
        SwitchRow(
          settings.logoImage == null ? 'Imprimir minha logo (adicione em Ajustes)' : 'Imprimir minha logo',
          _showLogo,
          (v) {
            setState(() => _showLogo = v);
            _render();
          },
        ),
        SwitchRow('Mostrar forma de pagamento', _showPayment, (v) {
          setState(() => _showPayment = v);
          _render();
        }),
        if (_showPayment)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: DropdownButtonFormField<String>(
              value: _payment,
              items: [for (final p in _payments) DropdownMenuItem(value: p, child: Text(p))],
              onChanged: (v) {
                setState(() => _payment = v ?? 'PIX');
                _render();
              },
            ),
          ),
        FieldLabel('Mensagem no rodapé', TextField(controller: _footer, onChanged: (_) => _changed())),
      ]);

  Widget _itemRow(int i) {
    final it = _items[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        SizedBox(
          width: 52,
          child: TextField(
            controller: it.qty,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            onChanged: (_) {
              setState(() {});
              _changed();
            },
            decoration: const InputDecoration(labelText: 'Qtd'),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: TextField(
            controller: it.desc,
            onChanged: (_) => _changed(),
            decoration: const InputDecoration(labelText: 'Descrição'),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 92,
          child: TextField(
            controller: it.price,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.right,
            inputFormatters: [CentsInputFormatter()],
            onChanged: (_) {
              setState(() {});
              _changed();
            },
            decoration: const InputDecoration(labelText: 'Valor un.'),
          ),
        ),
        if (_items.length > 1)
          IconButton(
            tooltip: 'Remover item',
            onPressed: () {
              setState(() => _items.removeAt(i).dispose());
              _render();
            },
            icon: const Icon(Icons.close, size: 20),
          ),
      ]),
    );
  }

  Widget _copiesStepper() => Container(
        height: 52,
        decoration: BoxDecoration(
          border: Border.all(color: LeoColors.field),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            tooltip: 'Menos uma cópia',
            onPressed: _copies > 1 ? () => setState(() => _copies--) : null,
            icon: const Icon(Icons.remove),
          ),
          Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('$_copies', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            Text(_copies == 1 ? 'cópia' : 'cópias', style: const TextStyle(fontSize: 11)),
          ]),
          IconButton(
            tooltip: 'Mais uma cópia',
            onPressed: _copies < 9 ? () => setState(() => _copies++) : null,
            icon: const Icon(Icons.add),
          ),
        ]),
      );
}
