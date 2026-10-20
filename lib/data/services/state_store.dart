import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// رمز مكتشف مع توقيت الاكتشاف.
class FoundCode {
  const FoundCode({required this.code, required this.discoveredAt});

  /// الرمز الصحيح.
  final String code;

  /// توقيت اكتشافه.
  final DateTime discoveredAt;

  /// نسخة قابلة للتخزين.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'code': code,
        'discoveredAt': discoveredAt.toIso8601String(),
      };

  /// استعادة من التخزين.
  static FoundCode fromJson(Map<String, dynamic> json) {
    return FoundCode(
      code: (json['code'] ?? '').toString(),
      discoveredAt:
          DateTime.tryParse((json['discoveredAt'] ?? '').toString()) ??
              DateTime.now(),
    );
  }
}

/// حالة الواجهة التلقائية المحفوظة محلياً (استئناف بعد الخروج).
class AutoPortalState {
  const AutoPortalState({
    this.lastNumber = 0,
    this.portalUrl = '',
    this.foundCodes = const <FoundCode>[],
  });

  /// آخر رقم تم فحصه.
  final int lastNumber;

  /// آخر رابط بوابة مستهدف.
  final String portalUrl;

  /// الرموز المكتشفة (الأحدث أولاً).
  final List<FoundCode> foundCodes;

  /// نسخة قابلة للتخزين.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'lastNumber': lastNumber,
        'portalUrl': portalUrl,
        'foundCodes': foundCodes
            .map((FoundCode entry) => entry.toJson())
            .toList(),
      };

  /// استعادة من التخزين.
  static AutoPortalState fromJson(Map<String, dynamic> json) {
    final Object? raw = json['foundCodes'];
    final List<FoundCode> codes = raw is List
        ? raw
            .whereType<Map>()
            .map((Map entry) => FoundCode.fromJson(
                  entry.map<String, dynamic>(
                    (Object? key, Object? value) =>
                        MapEntry<String, dynamic>(key.toString(), value),
                  ),
                ))
            .toList()
        : <FoundCode>[];
    return AutoPortalState(
      lastNumber: int.tryParse((json['lastNumber'] ?? 0).toString()) ?? 0,
      portalUrl: (json['portalUrl'] ?? '').toString(),
      foundCodes: codes,
    );
  }
}

/// تخزين JSON بسيط في مجلد المستندات (قابل لحقن مجلد للاختبارات).
class StateStore {
  StateStore({Directory? directory}) : _injected = directory;

  final Directory? _injected;

  Future<Directory> _resolveDir() async {
    if (_injected != null) return _injected;
    return getApplicationDocumentsDirectory();
  }

  File _file(Directory dir) =>
      File('${dir.path}${Platform.pathSeparator}auto_portal_state.json');

  /// يقرأ الحالة المحفوظة (أو حالة فارغة).
  Future<AutoPortalState> load() async {
    try {
      final Directory dir = await _resolveDir();
      final File file = _file(dir);
      if (!file.existsSync()) return const AutoPortalState();
      final String raw = file.readAsStringSync();
      if (raw.trim().isEmpty) return const AutoPortalState();
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return const AutoPortalState();
      return AutoPortalState.fromJson(
        decoded.map<String, dynamic>(
          (Object? key, Object? value) =>
              MapEntry<String, dynamic>(key.toString(), value),
        ),
      );
    } catch (_) {
      return const AutoPortalState();
    }
  }

  /// يحفظ الحالة (كتابة كاملة مع مسح المخزن).
  Future<void> save(AutoPortalState state) async {
    final Directory dir = await _resolveDir();
    await _file(dir).writeAsString(
      jsonEncode(state.toJson()),
      flush: true,
    );
  }
}
