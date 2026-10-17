/// معلومات البوابة الافتراضية المكتشفة.
class GatewayInfo {
  const GatewayInfo({
    required this.host,
    required this.baseUrl,
    required this.source,
    this.statusCode,
    this.pageTitle,
    this.responded = false,
  });

  /// عنوان المضيف مثل 192.168.1.1.
  final String host;

  /// الرابط الأساسي http://192.168.1.1.
  final String baseUrl;

  /// مصدر الاكتشاف: النظام أو الفحص اليدوي أو الافتراضي.
  final String source;

  /// رمز HTTP الذي أعادته البوابة.
  final int? statusCode;

  /// عنوان صفحة البوابة إن وُجد.
  final String? pageTitle;

  /// هل استجابت البوابة فعلاً؟
  final bool responded;

  /// وصف عربي لمصدر الاكتشاف.
  String get sourceLabel {
    switch (source) {
      case 'system':
        return 'من إعدادات النظام';
      case 'probe':
        return 'من الفحص التلقائي';
      default:
        return 'قيمة افتراضية';
    }
  }

  /// نسخة قابلة للتخزين.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'host': host,
        'baseUrl': baseUrl,
        'source': source,
        'statusCode': statusCode,
        'pageTitle': pageTitle,
        'responded': responded,
      };

  @override
  String toString() => 'GatewayInfo($baseUrl, source: $source)';
}
