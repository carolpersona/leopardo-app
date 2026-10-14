import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'raster.dart';

/// Dados da loja, da chave PIX e preferências de impressão.
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  late SharedPreferences _p;

  String storeName = '';
  String storePhone = '';
  String storeCity = '';
  String pixKey = '';
  String pixName = '';
  String pixCity = '';
  String footer = 'Obrigado pela preferência!';
  int paperMm = 58;
  bool autoReconnect = true;

  // Comandos da impressora (lidos também pelo serviço de impressão do Android).
  int feedLines = 4;
  bool autoBoleto = true; // impressão pelo Android: refaz boletos no layout 80 mm
  bool autoDanfe = true; // impressão pelo Android: DANFE A4 vira DANFE Simplificado
  bool danfeEtiqueta = false; // DANFE Simplificado - Etiqueta (sem itens)

  // Controle de fluxo
  bool statusCheck = false; // envia DLE EOT 1 ao final e espera a resposta
  int packetDelay = 10; // ms entre pacotes
  int disconnectWait = 1; // segundos antes de desconectar
  static const packetDelayOptions = [
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, //
    25, 30, 35, //
    40, 50, 60, 70, 80, 90, 100, //
    125, 150, 175, 200, 225, 250, 275, 300, 325, 350, 375, 400, 425, 450, 475, 500, //
    525, 550, 575, 600, 625, 650, 675, 700, 725, 750, 775, 800, 825, 850, 875, 900, //
    925, 950, 975, 1000,
  ];
  static const disconnectWaitOptions = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 15, 20, 25, 30];
  int darkness = 1; // 0 claro, 1 normal, 2 escuro
  String lastPrinterId = '';
  String lastPrinterName = '';
  /// Impressoras já conectadas (endereço -> nome). Lidas também pelo serviço
  /// de impressão do Android (LeopardoPrintService.kt).
  Map<String, String> knownPrinters = {};
  Uint8List? logoPng;
  ui.Image? logoImage;

  int get paperDots => paperMm == 80 ? 576 : 384;
  bool get hasPixKey => pixKey.trim().isNotEmpty && pixName.trim().isNotEmpty;

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    storeName = _p.getString('storeName') ?? '';
    storePhone = _p.getString('storePhone') ?? '';
    storeCity = _p.getString('storeCity') ?? '';
    pixKey = _p.getString('pixKey') ?? '';
    pixName = _p.getString('pixName') ?? '';
    pixCity = _p.getString('pixCity') ?? '';
    footer = _p.getString('footer') ?? footer;
    paperMm = _p.getInt('paperMm') ?? 58;
    autoReconnect = _p.getBool('autoReconnect') ?? true;
    statusCheck = _p.getBool('statusCheck') ?? false;
    packetDelay = _p.getInt('packetDelay') ?? 10;
    disconnectWait = _p.getInt('disconnectWait') ?? 1;
    feedLines = _p.getInt('feedLines') ?? 4;
    autoBoleto = _p.getBool('autoBoleto') ?? true;
    autoDanfe = _p.getBool('autoDanfe') ?? true;
    danfeEtiqueta = _p.getBool('danfeEtiqueta') ?? false;
    darkness = _p.getInt('darkness') ?? 1;
    lastPrinterId = _p.getString('lastPrinterId') ?? '';
    lastPrinterName = _p.getString('lastPrinterName') ?? '';
    try {
      final raw = _p.getString('knownPrinters');
      if (raw != null && raw.isNotEmpty) {
        knownPrinters = Map<String, String>.from(jsonDecode(raw) as Map);
      }
    } catch (_) {}
    final logo = _p.getString('logoPng');
    if (logo != null && logo.isNotEmpty) {
      try {
        logoPng = base64Decode(logo);
        logoImage = await decodeImageBytes(logoPng!);
      } catch (_) {
        logoPng = null;
      }
    }
  }

  Future<void> save() async {
    await _p.setString('storeName', storeName);
    await _p.setString('storePhone', storePhone);
    await _p.setString('storeCity', storeCity);
    await _p.setString('pixKey', pixKey);
    await _p.setString('pixName', pixName);
    await _p.setString('pixCity', pixCity);
    await _p.setString('footer', footer);
    await _p.setInt('paperMm', paperMm);
    await _p.setBool('autoReconnect', autoReconnect);
    await _p.setBool('statusCheck', statusCheck);
    await _p.setInt('packetDelay', packetDelay);
    await _p.setInt('disconnectWait', disconnectWait);
    await _p.setInt('feedLines', feedLines);
    await _p.setBool('autoBoleto', autoBoleto);
    await _p.setBool('autoDanfe', autoDanfe);
    await _p.setBool('danfeEtiqueta', danfeEtiqueta);
    await _p.setInt('darkness', darkness);
    await _p.setString('lastPrinterId', lastPrinterId);
    await _p.setString('lastPrinterName', lastPrinterName);
    await _p.setString('knownPrinters', jsonEncode(knownPrinters));
    notifyListeners();
  }

  /// Guarda a logo já reduzida (a impressão é monocromática e estreita).
  Future<void> setLogo(Uint8List? originalBytes) async {
    if (originalBytes == null) {
      logoPng = null;
      logoImage = null;
      await _p.remove('logoPng');
      notifyListeners();
      return;
    }
    final img = await decodeImageBytes(originalBytes, targetWidth: 240);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    logoPng = png!.buffer.asUint8List();
    logoImage = img;
    await _p.setString('logoPng', base64Encode(logoPng!));
    notifyListeners();
  }
}
