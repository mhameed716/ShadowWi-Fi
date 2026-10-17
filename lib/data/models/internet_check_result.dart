/// نتيجة فحص الاتصال بالإنترنت.
class InternetCheckResult {
  const InternetCheckResult({
    required this.online,
    required this.latencyMs,
    this.statusCode,
  });

  /// هل الاتصال بالإنترنت متاح؟
  final bool online;

  /// زمن الاستجابة بالمللي ثانية.
  final int latencyMs;

  /// رمز HTTP الذي أعاده خادم الفحص.
  final int? statusCode;

  /// وصف عربي مختصر.
  String get label {
    if (!online) return 'غير متصل بالإنترنت';
    return 'متصل بالإنترنت (${latencyMs}ms)';
  }
}
