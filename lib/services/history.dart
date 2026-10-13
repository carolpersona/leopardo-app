import 'package:flutter/foundation.dart';

import 'raster.dart';

class PrintJob {
  final String title;
  final String subtitle;
  final DateTime time;
  final List<MonoBitmap> pages;

  PrintJob(this.title, this.subtitle, this.pages) : time = DateTime.now();

  String get timeLabel =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

/// Últimas impressões desta sessão, para reimprimir com um toque.
class PrintHistory extends ChangeNotifier {
  PrintHistory._();
  static final PrintHistory instance = PrintHistory._();

  final List<PrintJob> jobs = [];

  void add(PrintJob job) {
    jobs.insert(0, job);
    if (jobs.length > 10) jobs.removeLast();
    notifyListeners();
  }
}
