/// Geração do "PIX Copia e Cola" (BR Code estático, padrão EMV do Banco Central).
class PixPayload {
  final String key;
  final String merchantName;
  final String merchantCity;
  final int amountCents; // 0 = valor livre
  final String description;
  final String txid;

  PixPayload({
    required this.key,
    required this.merchantName,
    required this.merchantCity,
    this.amountCents = 0,
    this.description = '',
    this.txid = '***',
  });

  String build() {
    final account = StringBuffer()
      ..write(_f('00', 'br.gov.bcb.pix'))
      ..write(_f('01', key.trim()));
    final desc = _clean(description, 72);
    if (desc.isNotEmpty && account.length + desc.length + 4 <= 99) {
      account.write(_f('02', desc));
    }

    final b = StringBuffer()
      ..write(_f('00', '01'))
      ..write(_f('26', account.toString()))
      ..write(_f('52', '0000'))
      ..write(_f('53', '986'));
    if (amountCents > 0) {
      final v = '${amountCents ~/ 100}.${(amountCents % 100).toString().padLeft(2, '0')}';
      b.write(_f('54', v));
    }
    b
      ..write(_f('58', 'BR'))
      ..write(_f('59', _clean(merchantName, 25).toUpperCase()))
      ..write(_f('60', _clean(merchantCity, 15).toUpperCase()))
      ..write(_f('62', _f('05', _txid(txid))))
      ..write('6304');
    final payload = b.toString();
    return payload + crc16(payload);
  }

  static String _f(String id, String value) =>
      '$id${value.length.toString().padLeft(2, '0')}$value';

  static String _txid(String t) {
    final s = t.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (s.isEmpty) return '***';
    return s.length > 25 ? s.substring(0, 25) : s;
  }

  /// Remove acentos e caracteres fora do ASCII básico.
  static String _clean(String s, int max) {
    const from = 'ÀÁÂÃÄÅàáâãäåÈÉÊËèéêëÌÍÎÏìíîïÒÓÔÕÖòóôõöÙÚÛÜùúûüÇçÑñ';
    const to = 'AAAAAAaaaaaaEEEEeeeeIIIIiiiiOOOOOoooooUUUUuuuuCcNn';
    final out = StringBuffer();
    for (final ch in s.trim().split('')) {
      final i = from.indexOf(ch);
      final c = i >= 0 ? to[i] : ch;
      if (RegExp(r'[A-Za-z0-9 \.\-\/]').hasMatch(c)) out.write(c);
    }
    final r = out.toString();
    return r.length > max ? r.substring(0, max) : r;
  }

  /// CRC16-CCITT (polinômio 0x1021, valor inicial 0xFFFF).
  static String crc16(String data) {
    var crc = 0xFFFF;
    for (final byte in data.codeUnits) {
      crc ^= byte << 8;
      for (var i = 0; i < 8; i++) {
        crc = (crc & 0x8000) != 0 ? ((crc << 1) ^ 0x1021) : (crc << 1);
        crc &= 0xFFFF;
      }
    }
    return crc.toRadixString(16).toUpperCase().padLeft(4, '0');
  }
}
