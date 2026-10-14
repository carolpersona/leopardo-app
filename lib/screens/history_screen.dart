import 'package:flutter/material.dart';

import '../services/history.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'connect_screen.dart';

/// Reimprime uma impressão do histórico.
Future<void> reprintJob(BuildContext context, PrintJob job) async {
  try {
    final pages = await job.load();
    if (!context.mounted) return;
    await printWithFeedback(
      context,
      pages: pages,
      title: job.title,
      subtitle: job.subtitle,
      openConnect: () => openConnectScreen(context),
      saveToHistory: false,
    );
  } catch (_) {
    if (context.mounted) showMsg(context, 'Não foi possível abrir esta impressão.');
  }
}

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Limpar histórico?'),
        content: const Text('Todas as impressões guardadas serão apagadas deste aparelho.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: LeoColors.red),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Limpar'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await PrintHistory.instance.clear();
      if (context.mounted) showMsg(context, 'Histórico apagado.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = PrintHistory.instance;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Histórico'),
        actions: [
          AnimatedBuilder(
            animation: h,
            builder: (context, _) => h.jobs.isEmpty
                ? const SizedBox.shrink()
                : TextButton.icon(
                    onPressed: () => _confirmClear(context),
                    style: TextButton.styleFrom(foregroundColor: LeoColors.red),
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: const Text('Limpar'),
                  ),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: h,
        builder: (context, _) {
          if (h.jobs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.history, size: 48, color: LeoColors.muted),
                  SizedBox(height: 12),
                  Text('Nenhuma impressão ainda', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                  SizedBox(height: 6),
                  Text('As impressões feitas pelo app ficam guardadas aqui para reimprimir.',
                      textAlign: TextAlign.center, style: TextStyle(color: LeoColors.muted)),
                ]),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            itemCount: h.jobs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final job = h.jobs[i];
              return Dismissible(
                key: ValueKey(job.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  decoration: BoxDecoration(color: LeoColors.red, borderRadius: BorderRadius.circular(16)),
                  child: const Icon(Icons.delete_outline, color: Colors.white),
                ),
                onDismissed: (_) {
                  h.remove(job);
                  showMsg(context, 'Impressão excluída.');
                },
                child: LeoCard(
                  padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(job.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                        Text('${job.subtitle} · ${job.dateLabel}',
                            style: const TextStyle(fontSize: 12, color: LeoColors.muted)),
                      ]),
                    ),
                    IconButton(
                      tooltip: 'Excluir',
                      onPressed: () {
                        h.remove(job);
                        showMsg(context, 'Impressão excluída.');
                      },
                      icon: const Icon(Icons.delete_outline, color: LeoColors.muted),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: LeoColors.ink),
                      onPressed: () => reprintJob(context, job),
                      child: const Text('Reimprimir', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
