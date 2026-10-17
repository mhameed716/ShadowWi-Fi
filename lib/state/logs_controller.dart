import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/models/attempt_log.dart';
import '../data/services/log_service.dart';

/// يدير سجل المحاولات ويوفّر عمليات المسح والتصدير.
class LogsController extends ChangeNotifier {
  LogsController(this._service);

  final LogService _service;

  /// السجل المحمّل.
  List<AttemptLog> logs = <AttemptLog>[];

  /// هل جارٍ التحميل؟
  bool loading = false;

  /// هل جارٍ المسح؟
  bool clearing = false;

  /// مسار آخر ملف مُصدَّر.
  String? lastExportPath;

  /// رسالة خطأ آنية.
  String? error;

  /// يقرأ السجل من التخزين المحلي.
  Future<void> load() async {
    loading = true;
    notifyListeners();
    try {
      logs = await _service.load();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// يضيف محاولة جديدة إلى السجل.
  Future<void> addAttempt(AttemptLog log) async {
    logs = <AttemptLog>[log, ...logs];
    if (logs.length > 500) {
      logs = logs.sublist(0, 500);
    }
    notifyListeners();
    await _service.save(logs);
  }

  /// يمسح السجل بالكامل.
  Future<void> clear() async {
    clearing = true;
    notifyListeners();
    try {
      logs = <AttemptLog>[];
      await _service.clear();
      lastExportPath = null;
    } finally {
      clearing = false;
      notifyListeners();
    }
  }

  /// يصدّر السجل إلى ملف نصي ويعيد مساره.
  Future<String?> export() async {
    try {
      final File file = await _service.export(logs);
      lastExportPath = file.path;
      notifyListeners();
      return lastExportPath;
    } catch (e) {
      error = 'تعذّر تصدير السجل: $e';
      notifyListeners();
      return null;
    }
  }

  /// رسالة خطأ آنية (تُستهلك مرة واحدة).
  String? takeError() {
    final String? value = error;
    error = null;
    return value;
  }
}
