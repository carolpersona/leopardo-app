import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/content.dart';
import '../services/leopardo_contact.dart';
import '../services/sheets.dart';
import '../services/warranty.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Programa de indicação: o cliente compartilha o próprio código.
class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key});
  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  String? _code;

  @override
  void initState() {
    super.initState();
    ContentService.instance.referralCode().then((c) {
      if (mounted) setState(() => _code = c);
    });
  }

  String get _link => 'https://wa.me/${LeopardoContact.phone}?text='
      '${Uri.encodeComponent('Olá! Quero conhecer as impressoras e bobinas Leopardo. Tenho o código de indicação $_code.')}';

  String get _message => 'Conheça as impressoras térmicas e bobinas Leopardo! '
      'Use meu código de indicação $_code na sua compra.\n\nFale com a Leopardo: $_link';

  /// Registra o código na planilha da Leopardo (uma vez), com os dados do cadastro.
  Future<void> _register() async {
    final p = await SharedPreferences.getInstance();
    if (p.getBool('referralRegistered') == true) return;
    final w = WarrantyStore.instance.items.isNotEmpty ? WarrantyStore.instance.items.first : null;
    final ok = await SheetsSync.send('indicacao', {
      'Código': _code ?? '',
      'Nome': w?.nome ?? '',
      'Telefone': w?.telefone ?? '',
      'Cidade/UF': w?.cidade ?? '',
    });
    if (ok) await p.setBool('referralRegistered', true);
  }

  Future<void> _share() async {
    if (_code == null) return;
    _register();
    final ok = await ContentService.shareText(_message);
    if (!ok && mounted) showMsg(context, 'Não foi possível abrir o compartilhamento.');
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ContentService.instance.indicacao;
    return Scaffold(
      appBar: AppBar(title: const Text('Indique e ganhe')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: LeoColors.ink, borderRadius: BorderRadius.circular(18)),
            child: Column(children: [
              const Icon(Icons.card_giftcard, color: Colors.white, size: 40),
              const SizedBox(height: 10),
              Text(cfg.titulo,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              const Text('Seu código', style: TextStyle(color: Color(0xFFC9CBD1), fontSize: 13)),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () {
                  if (_code == null) return;
                  Clipboard.setData(ClipboardData(text: _code!));
                  showMsg(context, 'Código copiado.');
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white54, width: 1.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(_code ?? '…',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 2)),
                ),
              ),
              const SizedBox(height: 6),
              const Text('Toque para copiar', style: TextStyle(color: Color(0xFFC9CBD1), fontSize: 12)),
            ]),
          ),
          const SizedBox(height: 16),
          LeoCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Como funciona', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 8),
              Text(cfg.regras, style: const TextStyle(fontSize: 14, color: LeoColors.text2, height: 1.5)),
            ]),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: LeoColors.red,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _share,
              icon: const Icon(Icons.share_outlined),
              label: const Text('Compartilhar meu código', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ),
          const SizedBox(height: 10),
          OutlineAction(
            label: 'Dúvidas sobre a indicação',
            icon: Icons.chat_outlined,
            onPressed: () => LeopardoContact.whatsapp(
                'Olá! Quero saber mais sobre o programa de indicação. Meu código é ${_code ?? ''}.'),
          ),
        ],
      ),
    );
  }
}
