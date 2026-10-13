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
