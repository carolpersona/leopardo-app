import 'package:flutter_test/flutter_test.dart';
import 'package:leopardo_app/services/money.dart';
import 'package:leopardo_app/services/pix.dart';

void main() {
  test('CRC16 do PIX confere com o exemplo do Banco Central', () {
    const semCrc = '00020126580014br.gov.bcb.pix0136123e4567-e12b-12d1-a456-426655440000'
        '5204000053039865802BR5913Fulano de Tal6008BRASILIA62070503***6304';
    expect(PixPayload.crc16(semCrc), '1D3D');
  });

  test('Payload PIX tem valor e termina com CRC', () {
    final p = PixPayload(
      key: '+5511999998888',
      merchantName: 'Loja São João',
      merchantCity: 'São Paulo',
      amountCents: 4890,
    ).build();
    expect(p.contains('540548.90'), isTrue);
    expect(p.contains('5913LOJA SAO JOAO'), isTrue);
    expect(p.substring(p.length - 8, p.length - 4), '6304');
  });

  test('Formatação de dinheiro', () {
    expect(formatCents(123456), '1.234,56');
    expect(parseMoneyToCents('48,90'), 4890);
    expect(parseMoneyToCents('1.234,56'), 123456);
  });
}
