import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'leopardo_contact.dart';
import 'sheets.dart';

/// Modelos e prazo de garantia (meses) a partir da data da compra.
const warrantyModels = <String, int>{
  'Leopardo PROMAX': 24,
  'Leopardo XR': 18,
  'Leopardo MXR': 12,
};

int warrantyMonthsFor(String modelo) => warrantyModels[modelo] ?? 12;

class Warranty {
  final String id;
  String nome;
  String documento;
  String telefone;
  String email;
  String cidade;
  String modelo;
  String serie;
  String notaNumero;
  DateTime dataCompra;
  String loja;
  String? notaPath;
  bool aceitaContato;
  DateTime? enviadoEm;

  Warranty({
    required this.id,
    required this.nome,
    required this.documento,
    required this.telefone,
    required this.email,
    required this.cidade,
    required this.modelo,
    required this.serie,
    this.notaNumero = '',
    required this.dataCompra,
    required this.loja,
    this.notaPath,
    this.aceitaContato = true,
    this.enviadoEm,
  });

  int get meses => warrantyMonthsFor(modelo);
  DateTime get validoAte => DateTime(dataCompra.year, dataCompra.month + meses, dataCompra.day);
  bool get valida => !DateTime.now().isAfter(validoAte.add(const Duration(days: 1)));
  int get diasRestantes => validoAte.difference(DateTime.now()).inDays;

  static String fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Map<String, dynamic> toJson() => {
        'id': id,
        'nome': nome,
        'documento': documento,
        'telefone': telefone,
        'email': email,
        'cidade': cidade,
        'modelo': modelo,
        'serie': serie,
        'notaNumero': notaNumero,
        'dataCompra': dataCompra.millisecondsSinceEpoch,
        'loja': loja,
        'notaPath': notaPath,
        'aceitaContato': aceitaContato,
        'enviadoEm': enviadoEm?.millisecondsSinceEpoch,
      };

  static Warranty fromJson(Map<String, dynamic> m) => Warranty(
        id: m['id'] as String,
        nome: m['nome'] as String? ?? '',
        documento: m['documento'] as String? ?? '',
        telefone: m['telefone'] as String? ?? '',
        email: m['email'] as String? ?? '',
        cidade: m['cidade'] as String? ?? '',
        modelo: m['modelo'] as String? ?? '',
        serie: m['serie'] as String? ?? '',
        notaNumero: m['notaNumero'] as String? ?? '',
        dataCompra: DateTime.fromMillisecondsSinceEpoch((m['dataCompra'] as num).toInt()),
        loja: m['loja'] as String? ?? '',
        notaPath: m['notaPath'] as String?,
        aceitaContato: m['aceitaContato'] as bool? ?? true,
        enviadoEm: m['enviadoEm'] == null ? null : DateTime.fromMillisecondsSinceEpoch((m['enviadoEm'] as num).toInt()),
      );

  /// Mensagem enviada ao WhatsApp da Leopardo.
  String message({String titulo = 'Cadastro de garantia'}) {
    final b = StringBuffer()
      ..writeln('*$titulo - App Leopardo*')
      ..writeln()
      ..writeln('Nome: $nome')
      ..writeln('CPF/CNPJ: $documento')
      ..writeln('Telefone: $telefone');
    if (email.isNotEmpty) b.writeln('E-mail: $email');
    if (cidade.isNotEmpty) b.writeln('Cidade/UF: $cidade');
    b
      ..writeln()
      ..writeln('Modelo: $modelo')
      ..writeln('Nº de série: $serie');
    if (notaNumero.isNotEmpty) b.writeln('Nº da nota fiscal: $notaNumero');
    b.writeln('Data da compra: ${fmt(dataCompra)}');
    if (loja.isNotEmpty) b.writeln('Loja: $loja');
    b
      ..writeln('Garantia: $meses meses, até ${fmt(validoAte)}')
      ..writeln('Aceita receber novidades: ${aceitaContato ? 'Sim' : 'Não'}');
    if (notaPath != null) b.writeln('\nNota fiscal em anexo.');
    return b.toString();
  }
}

/// Impressoras cadastradas neste aparelho.
class WarrantyStore extends ChangeNotifier {
  WarrantyStore._();
  static final WarrantyStore instance = WarrantyStore._();
  static const _key = 'warranties';
  static const _ch = MethodChannel('leopardo/system');

  final List<Warranty> items = [];

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw == null) return;
      items
        ..clear()
        ..addAll((jsonDecode(raw) as List).map((e) => Warranty.fromJson(Map<String, dynamic>.from(e as Map))));
      notifyListeners();
      _syncReminders();
    } catch (_) {}
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(items.map((w) => w.toJson()).toList()));
    notifyListeners();
    await _syncReminders();
  }

  /// Garantias que vencem nos próximos 30 dias (ou venceram há até 60 dias).
  List<Warranty> get attention => items.where((w) => w.diasRestantes <= 30 && w.diasRestantes >= -60).toList();

  /// Agenda notificações 30 e 7 dias antes do fim de cada garantia.
  Future<void> _syncReminders() async {
    final list = <Map<String, dynamic>>[];
    var n = 0;
    for (final w in items) {
      for (final days in const [30, 7]) {
        final v = w.validoAte;
        final at = DateTime(v.year, v.month, v.day - days, 10);
        list.add({
          'id': 7000 + n++,
          'at': at.millisecondsSinceEpoch,
          'title': 'Garantia Leopardo',
          'text': 'A garantia da sua ${w.modelo} (série ${w.serie}) vence em $days dias, '
              'em ${Warranty.fmt(v)}. Fale com a Leopardo para uma revisão ou para conhecer as novidades.',
        });
      }
    }
    try {
      await _ch.invokeMethod('setReminders', {'list': list});
    } catch (_) {}
  }

  /// Guarda uma cópia da foto da nota dentro do app (o arquivo original pode sumir).
  Future<String?> keepPhoto(String? path, String id) async {
    if (path == null) return null;
    try {
      final base = await _ch.invokeMethod<String>('filesDir') ?? Directory.systemTemp.path;
      final dir = Directory('$base/garantia');
      if (!await dir.exists()) await dir.create(recursive: true);
      final ext = path.contains('.') ? path.substring(path.lastIndexOf('.')) : '.jpg';
      final dst = '${dir.path}/nota_$id$ext';
      if (path != dst) await File(path).copy(dst);
      return dst;
    } catch (_) {
      return path;
    }
  }

  Future<void> upsert(Warranty w) async {
    final i = items.indexWhere((e) => e.id == w.id);
    if (i >= 0) {
      items[i] = w;
    } else {
      items.insert(0, w);
    }
    await _save();
  }

  Future<void> remove(Warranty w) async {
    items.remove(w);
    final n = w.notaPath;
    if (n != null) {
      try {
        await File(n).delete();
      } catch (_) {}
    }
    await _save();
  }

  /// Linha da aba "Garantias" na planilha Google.
  Map<String, String> sheetFields(Warranty w) => {
        'ID do cadastro': w.id,
        'Nome': w.nome,
        'CPF/CNPJ': w.documento,
        'Telefone': w.telefone,
        'E-mail': w.email,
        'Cidade/UF': w.cidade,
        'Modelo': w.modelo,
        'Nº de série': w.serie,
        'Nº da nota fiscal': w.notaNumero,
        'Data da compra': Warranty.fmt(w.dataCompra),
        'Loja': w.loja,
        'Garantia (meses)': '${w.meses}',
        'Garantia até': Warranty.fmt(w.validoAte),
        'Aceita novidades': w.aceitaContato ? 'Sim' : 'Não',
      };

  /// Envia o cadastro (ou pedido de suporte) para o WhatsApp da Leopardo.
  Future<bool> send(Warranty w, {String titulo = 'Cadastro de garantia'}) async {
    final ok = await LeopardoContact.sendWhatsApp(w.message(titulo: titulo), imagePath: w.notaPath);
    if (titulo == 'Cadastro de garantia') {
      // Também grava na planilha Google (em segundo plano).
      SheetsSync.send('garantia', sheetFields(w), imagePath: w.notaPath);
      if (ok) {
        w.enviadoEm = DateTime.now();
        await _save();
      }
    }
    return ok;
  }
}
