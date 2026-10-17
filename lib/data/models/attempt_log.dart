import 'dart:convert';

/// مصدر المحاولة.
enum AttemptSource {
  manual,
  automatic,
}

extension AttemptSourceX on AttemptSource {
  /// الاسم العربي.
  String get label =>
      this == AttemptSource.manual ? 'يدوية' : 'تلقائية';
}

/// سجل واحد لمحاولة اتصال سابقة.
class AttemptLog {
  const AttemptLog({
    required this.id,
    required this.timestamp,
    required this.gateway,
    required this.username,
    required this.success,
    required this.message,
    required this.durationMs,
    required this.source,
    this.statusCode,
  });

  /// معرّف فريد.
  final String id;

  /// وقت المحاولة.
  final DateTime timestamp;

  /// عنوان البوابة المستخدمة.
  final String gateway;

  /// المعرّف المعروض في السجل: الرمز المُجرَّب.
  final String username;

  /// هل نجحت المحاولة؟
  final bool success;

  /// رسالة النتيجة.
  final String message;

  /// مدة المحاولة بالمللي ثانية.
  final int durationMs;

  /// مصدر المحاولة.
  final AttemptSource source;

  /// رمز HTTP الذي أعادته البوابة.
  final int? statusCode;

  /// نسخة قابلة للتخزين بصيغة JSON.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'gateway': gateway,
        'username': username,
        'success': success,
        'message': message,
        'durationMs': durationMs,
        'source': source.name,
        'statusCode': statusCode,
      };

  /// استعادة سجل من JSON.
  factory AttemptLog.fromJson(Map<String, dynamic> json) {
    return AttemptLog(
      id: (json['id'] ?? '').toString(),
      timestamp:
          DateTime.tryParse((json['timestamp'] ?? '').toString()) ?? DateTime.now(),
      gateway: (json['gateway'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      success: json['success'] == true,
      message: (json['message'] ?? '').toString(),
      durationMs: int.tryParse((json['durationMs'] ?? 0).toString()) ?? 0,
      source: AttemptSource.values.firstWhere(
        (AttemptSource s) => s.name == (json['source'] ?? 'manual'),
        orElse: () => AttemptSource.manual,
      ),
      statusCode: int.tryParse((json['statusCode'] ?? '').toString()),
    );
  }

  /// تحويل سجل إلى سطر نصي واحد للتصدير.
  String toLine() {
    final String time = timestamp.toIso8601String();
    final String result = success ? 'نجاح' : 'فشل';
    final String code = statusCode == null ? '-' : statusCode.toString();
    return '$time | $result | $source | $username | $gateway | HTTP $code | '
        '${durationMs}ms | $message';
  }

  @override
  String toString() => 'AttemptLog($id, $username, success: $success)';
}

/// أدوات قراءة وكتابة السجل بصيغة JSON.
class AttemptLogCodec {
  const AttemptLogCodec._();

  /// تحويل قائمة سجلات إلى نص JSON.
  static String encode(List<AttemptLog> logs) =>
      jsonEncode(logs.map((AttemptLog e) => e.toJson()).toList());

  /// قراءة قائمة سجلات من نص JSON مع تجاهل النصوص التالفة.
  static List<AttemptLog> decode(String raw) {
    if (raw.trim().isEmpty) return <AttemptLog>[];
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return <AttemptLog>[];
      return decoded
          .whereType<Map>()
          .map(
            (Map entry) => AttemptLog.fromJson(
              entry.map<String, dynamic>(
                (Object? key, Object? value) =>
                    MapEntry<String, dynamic>(key.toString(), value),
              ),
            ),
          )
          .toList();
    } on FormatException {
      return <AttemptLog>[];
    } on TypeError {
      return <AttemptLog>[];
    }
  }

  /// تصدير السجل كنص عادي.
  static String exportText(List<AttemptLog> logs) {
    final StringBuffer buffer = StringBuffer()
      ..writeln('ShadowWi-Fi — سجل المحاولات')
      ..writeln('عدد المحاولات: ${logs.length}')
      ..writeln('وقت التصدير: ${DateTime.now().toIso8601String()}')
      ..writeln('----------------------------------------');
    for (final AttemptLog log in logs) {
      buffer.writeln(log.toLine());
    }
    return buffer.toString();
  }
}
