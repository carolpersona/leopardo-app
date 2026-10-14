import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'raster.dart';

class _PageRef {
  final String file;
  final int width;
  final int height;
  _PageRef(this.file, this.width, this.height);

  Map<String, dynamic> toJson() => {'file': file, 'w': width, 'h': height};
  static _PageRef fromJson(Map<String, dynamic> m) =>
      _PageRef(m['file'] as String, (m['w'] as num).toInt(), (m['h'] as num).toInt());
}

/// Uma impressão guardada no aparelho (para reimprimir depois).
class PrintJob {
  final String id;
  final String title;
  final String subtitle;
  final DateTime time;
  final List<_PageRef> _refs;
  List<MonoBitmap>? _pages;

  PrintJob._(this.id, this.title, this.subtitle, this.time, this._refs, [this._pages]);

  int get pageCount => _refs.length;

  String get timeLabel =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  String get dateLabel {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(time.year, time.month, time.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Hoje, $timeLabel';
    if (diff == 1) return 'Ontem, $timeLabel';
    return '${time.day.toString().padLeft(2, '0')}/${time.month.toString().padLeft(2, '0')}/${time.year}, $timeLabel';
  }

  /// Carrega as páginas salvas (imagem já pronta para a impressora).
  Future<List<MonoBitmap>> load() async {
    final cached = _pages;
    if (cached != null) return cached;
    final dir = await PrintHistory.instance._dir();
    final out = <MonoBitmap>[];
    for (final r in _refs) {
      final bytes = await File('${dir.path}/${r.file}').readAsBytes();
      out.add(MonoBitmap(r.width, r.height, bytes));
    }
    _pages = out;
    return out;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'time': time.millisecondsSinceEpoch,
        'pages': _refs.map((r) => r.toJson()).toList(),
      };

  static PrintJob fromJson(Map<String, dynamic> m) => PrintJob._(
        m['id'] as String,
        m['title'] as String,
        m['subtitle'] as String,
        DateTime.fromMillisecondsSinceEpoch((m['time'] as num).toInt()),
        (m['pages'] as List).map((e) => _PageRef.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      );
}

/// Histórico de impressões salvo na memória interna do app (sobrevive ao fechar o app).
class PrintHistory extends ChangeNotifier {
  PrintHistory._();
  static final PrintHistory instance = PrintHistory._();

  static const maxJobs = 60;
  static const _ch = MethodChannel('leopardo/system');

  final List<PrintJob> jobs = [];
  Directory? _cachedDir;

  Future<Directory> _dir() async {
    final c = _cachedDir;
    if (c != null) return c;
    String base;
    try {
      base = await _ch.invokeMethod<String>('filesDir') ?? Directory.systemTemp.path;
    } catch (_) {
      base = Directory.systemTemp.path;
    }
    final d = Directory('$base/historico');
    if (!await d.exists()) await d.create(recursive: true);
    _cachedDir = d;
    return d;
  }

  Future<File> _index() async => File('${(await _dir()).path}/index.json');

  Future<void> load() async {
    try {
      final f = await _index();
      if (!await f.exists()) return;
      final list = jsonDecode(await f.readAsString()) as List;
      jobs
        ..clear()
        ..addAll(list.map((e) => PrintJob.fromJson(Map<String, dynamic>.from(e as Map))));
      notifyListeners();
    } catch (_) {
      // índice corrompido: começa vazio
    }
  }

  Future<void> _saveIndex() async {
    final f = await _index();
    await f.writeAsString(jsonEncode(jobs.map((j) => j.toJson()).toList()));
  }

  Future<void> add(String title, String subtitle, List<MonoBitmap> pages) async {
    try {
      final dir = await _dir();
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      final refs = <_PageRef>[];
      for (var i = 0; i < pages.length; i++) {
        final name = '${id}_$i.bin';
        await File('${dir.path}/$name').writeAsBytes(Uint8List.fromList(pages[i].bits), flush: true);
        refs.add(_PageRef(name, pages[i].width, pages[i].height));
      }
      jobs.insert(0, PrintJob._(id, title, subtitle, DateTime.now(), refs, pages));
      while (jobs.length > maxJobs) {
        await _deleteFiles(jobs.removeLast());
      }
      await _saveIndex();
      notifyListeners();
    } catch (_) {
      // Falha ao salvar o histórico não deve atrapalhar a impressão.
    }
  }

  Future<void> _deleteFiles(PrintJob job) async {
    final dir = await _dir();
    for (final r in job._refs) {
      try {
        await File('${dir.path}/${r.file}').delete();
      } catch (_) {}
    }
  }

  Future<void> remove(PrintJob job) async {
    jobs.remove(job);
    await _deleteFiles(job);
    await _saveIndex();
    notifyListeners();
  }

  Future<void> clear() async {
    final all = List<PrintJob>.from(jobs);
    jobs.clear();
    for (final j in all) {
      await _deleteFiles(j);
    }
    await _saveIndex();
    notifyListeners();
  }
}
