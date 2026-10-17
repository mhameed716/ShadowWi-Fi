import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/attempt_log.dart';

/// خدمة تخزين السجل محلياً (بدون تشفير — حسب نطاق التطبيق) وتصديره.
class LogService {
  const LogService();

  /// اسم ملف التخزين.
  static const String fileName = 'shadowwifi_logs.json';

  /// مسار ملف السجل داخل مجلدDocuments.
  Future<File> logFile() async {
    final Directory directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}${Platform.pathSeparator}$fileName');
  }

  /// يقرأ السجل المحفوظ.
  Future<List<AttemptLog>> load() async {
    try {
      final File file = await logFile();
      if (!await file.exists()) return <AttemptLog>[];
      final String raw = await file.readAsString();
      return AttemptLogCodec.decode(raw);
    } catch (_) {
      return <AttemptLog>[];
    }
  }

  /// يحفظ السجل كاملاً.
  Future<bool> save(List<AttemptLog> logs) async {
    try {
      final File file = await logFile();
      await file.writeAsString(AttemptLogCodec.encode(logs), flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// يمسح ملف السجل.
  Future<bool> clear() async {
    try {
      final File file = await logFile();
      if (await file.exists()) {
        await file.delete();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// يصدّر السجل إلى ملف نصي ويعيد مساره.
  Future<File> export(List<AttemptLog> logs) async {
    final Directory directory = await getApplicationDocumentsDirectory();
    final String stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final File file = File(
      '${directory.path}${Platform.pathSeparator}shadowwifi_logs_$stamp.txt',
    );
    await file.writeAsString(AttemptLogCodec.exportText(logs), flush: true);
    return file;
  }
}
