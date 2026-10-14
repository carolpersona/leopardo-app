import 'package:flutter/material.dart';

import '../services/content.dart';
import '../services/leopardo_contact.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Tutoriais: vídeos (da planilha da Leopardo) e guias rápidos passo a passo.
class TutorialsScreen extends StatelessWidget {
  const TutorialsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = ContentService.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Tutoriais')),
      body: AnimatedBuilder(
        animation: cs,
        builder: (context, _) => RefreshIndicator(
          onRefresh: cs.refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            children: [
              if (cs.videos.isNotEmpty) ...[
                const SectionLabel('Vídeos'),
                for (final v in cs.videos) ...[
                  _video(context, v),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 8),
              ],
              const SectionLabel('Guias rápidos'),
              for (final g in guides) ...[
                LeoCard(
                  padding: EdgeInsets.zero,
                  child: Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      leading: const Icon(Icons.menu_book_outlined, color: LeoColors.red),
                      title: Text(g.titulo, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      subtitle: Text(g.resumo, style: const TextStyle(fontSize: 12, color: LeoColors.muted)),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      children: [
                        for (var i = 0; i < g.passos.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Container(
                                width: 24,
                                height: 24,
                                alignment: Alignment.center,
                                decoration: const BoxDecoration(color: LeoColors.ink, shape: BoxShape.circle),
                                child: Text('${i + 1}',
                                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                              ),
                              const SizedBox(width: 10),
                              Expanded(child: Text(g.passos[i], style: const TextStyle(fontSize: 14, height: 1.4))),
                            ]),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 6),
              OutlineAction(
                label: 'Ainda com dúvida? Fale com a Leopardo',
                icon: Icons.chat_outlined,
                onPressed: () => LeopardoContact.whatsapp('Olá! Preciso de ajuda com minha impressora Leopardo.'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _video(BuildContext context, Video v) {
    final thumb = v.thumbnail;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => LeopardoContact.openUrl(v.link),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (thumb != null)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(fit: StackFit.expand, children: [
                Image.network(thumb, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: LeoColors.segment)),
                const Center(child: Icon(Icons.play_circle_fill, size: 64, color: Colors.white)),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              if (thumb == null) ...[
                const Icon(Icons.play_circle_outline, color: LeoColors.red, size: 32),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(v.titulo, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  if (v.descricao.isNotEmpty)
                    Text(v.descricao, style: const TextStyle(fontSize: 13, color: LeoColors.muted)),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
