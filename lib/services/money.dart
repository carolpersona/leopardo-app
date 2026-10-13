import 'package:flutter/services.dart';

/// Converte "48,90", "R$ 1.234,56" ou "48.9" em centavos.
int parseMoneyToCents(String input) {
  var s = input.replaceAll(RegExp(r'[^0-9,\.]'), '');
  if (s.isEmpty) return 0;
  if (s.contains(',')) {
    // Formato brasileiro: ponto é milhar, vírgula é decimal.
    s = s.replaceAll('.', '').replaceAll(',', '.');
  }
  final v = double.tryParse(s) ?? 0;
  return (v * 100).round();
}

/// 4890 -> "48,90" ; 123456 -> "1.234,56"
String formatCents(int cents) {
  final negative = cents < 0;
  cents = cents.abs();
  final reais = cents ~/ 100;
  final cent = (cents % 100).toString().padLeft(2, '0');
  final digits = reais.toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    final fromEnd = digits.length - i;
    buf.write(digits[i]);
    if (fromEnd > 1 && fromEnd % 3 == 1) buf.write('.');
  }
  return '${negative ? '-' : ''}$buf,$cent';
}

String formatBRL(int cents) => 'R\$ ${formatCents(cents)}';

/// Campo de valor que preenche da direita para a esquerda (como maquininha).
class CentsInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > 11) digits = digits.substring(0, 11);
    final cents = digits.isEmpty ? 0 : int.parse(digits);
    final text = formatCents(cents);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
