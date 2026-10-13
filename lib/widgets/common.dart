import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/history.dart';
import '../services/printer_service.dart';
import '../services/raster.dart';
import '../theme.dart';

class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: LeoColors.muted, letterSpacing: 0.4)),
      );
}

class LeoCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const LeoCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: child,
      );
}

class FieldLabel extends StatelessWidget {
  final String label;
  final Widget child;
  const FieldLabel(this.label, this.child, {super.key});
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: LeoColors.text2)),
          const SizedBox(height: 6),
          child,
        ],
      );
}

class SwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const SwitchRow(this.label, this.value, this.onChanged, {super.key});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => onChanged(!value),
        child: SizedBox(
          height: 48,
          child: Row(children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
            Switch(value: value, onChanged: onChanged),
          ]),
        ),
      );
}

/// Controle segmentado no estilo do protótipo.
class Segmented extends StatelessWidget {
  final List<String> options;
  final int selected;
  final ValueChanged<int> onChanged;
  final Color background;
  const Segmented(
      {super.key,
      required this.options,
      required this.selected,
      required this.onChanged,
      this.background = LeoColors.segment});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            for (var i = 0; i < options.length; i++)
              Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == selected ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(options[i],
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: i == selected ? FontWeight.w600 : FontWeight.w500,
                          color: i == selected ? LeoColors.ink : LeoColors.text2,
                        )),
                  ),
                ),
              ),
          ],
        ),
      );
}

/// Prévia em "papel térmico" do que será impresso.
class PaperPreview extends StatelessWidget {
  final ui.Image? image;
  final bool loading;
  final double maxHeight;
  const PaperPreview({super.key, this.image, this.loading = false, this.maxHeight = 520});
  @override
  Widget build(BuildContext context) {
    const paperW = 240.0;
    Widget inner;
    if (image == null) {
      inner = const SizedBox(
          width: paperW, height: 160, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    } else {
      final h = image!.height * paperW / image!.width;
      inner = SizedBox(
        width: paperW,
        height: h > maxHeight ? maxHeight : h,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topCenter,
            maxHeight: double.infinity,
            child: RawImage(image: image, width: paperW, height: h, fit: BoxFit.fill, filterQuality: FilterQuality.medium),
          ),
        ),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(color: LeoColors.segment, borderRadius: BorderRadius.circular(16)),
      child: Center(
        child: Stack(children: [
          Container(
            decoration: const BoxDecoration(color: Colors.white, boxShadow: [
              BoxShadow(color: Color(0x2E17181C), blurRadius: 3, offset: Offset(0, 1)),
            ]),
            child: inner,
          ),
          if (loading && image != null)
            const Positioned(right: 6, top: 6, child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
        ]),
      ),
    );
  }
}

/// Barra inferior com botão de imprimir (vermelho da marca).
class PrintBar extends StatelessWidget {
  final Widget? leading;
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  const PrintBar({super.key, this.leading, required this.label, this.onPressed, this.busy = false});
  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: LeoColors.line)),
        ),
        padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + MediaQuery.of(context).padding.bottom),
        child: Row(children: [
          if (leading != null) ...[leading!, const SizedBox(width: 10)],
          Expanded(
            child: SizedBox(
              height: 52,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: LeoColors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                onPressed: busy ? null : onPressed,
                icon: busy
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.print_outlined),
                label: Text(busy ? 'Imprimindo…' : label),
              ),
            ),
          ),
        ]),
      );
}

class OutlineAction extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  const OutlineAction({super.key, required this.label, this.icon, this.onPressed});
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 52,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: LeoColors.ink,
            side: const BorderSide(color: LeoColors.field),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          onPressed: onPressed,
          icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 20),
          label: Text(label),
        ),
      );
}

void showMsg(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Envia as páginas para a impressora, registra no histórico e mostra o resultado.
/// Se não houver impressora conectada, abre a tela de conexão.
Future<void> printWithFeedback(
  BuildContext context, {
  required List<MonoBitmap> pages,
  required String title,
  required String subtitle,
  int copies = 1,
  required Future<void> Function() openConnect,
}) async {
  final ps = PrinterService.instance;
  if (!ps.isConnected) {
    showMsg(context, 'Conecte uma impressora para imprimir.');
    await openConnect();
    if (!ps.isConnected) return;
  }
  try {
    await ps.printPages(pages, copies: copies);
    PrintHistory.instance.add(PrintJob(title, subtitle, pages));
    if (context.mounted) showMsg(context, 'Enviado para ${ps.deviceName}.');
  } catch (e) {
    if (context.mounted) showMsg(context, 'Não foi possível imprimir: $e');
  }
}
