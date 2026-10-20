/// نتيجة محاولة تسجيل الدخول إلى البوابة.
class LoginOutcome {
  const LoginOutcome({
    required this.success,
    required this.message,
    this.statusCode,
    this.finalUrl,
    this.pageTitle,
    this.durationMs = 0,
    this.internetVerified = false,
    this.inconclusive = false,
  });

  /// لا دليل قطعي (لا استجابة مثلًا) — يستحق إعادة المحاولة.
  final bool inconclusive;

  /// هل نجحت المحاولة؟
  final bool success;

  /// وصف النتيجة بالعربية.
  final String message;

  /// رمز HTTP المُعاد.
  final int? statusCode;

  /// الرابط النهائي بعد التحويلات.
  final String? finalUrl;

  /// عنوان صفحة البوابة.
  final String? pageTitle;

  /// مدة المحاولة.
  final int durationMs;

  /// هل تم التحقق من الاتصال بالإنترنت بعد المحاولة؟
  final bool internetVerified;

  /// نسخة قابلة للتخزين.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'success': success,
        'message': message,
        'statusCode': statusCode,
        'finalUrl': finalUrl,
        'pageTitle': pageTitle,
        'durationMs': durationMs,
        'internetVerified': internetVerified,
        'inconclusive': inconclusive,
      };

  @override
  String toString() => 'LoginOutcome($success, $message)';
}
