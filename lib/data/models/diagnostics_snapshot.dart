/// لقطة واحدة لنتائج التشخيص.
class DiagnosticsSnapshot {
  const DiagnosticsSnapshot({
    required this.takenAt,
    this.connectionType,
    this.deviceAddresses = const <String>[],
    this.gateway,
    this.dnsServers = const <String>[],
    this.hasInternet = false,
    this.internetLatencyMs,
    this.internetStatusCode,
    this.portalTitle,
    this.portalStatusCode,
    this.portalUrl,
    this.error,
  });

  /// وقت تنفيذ الفحص.
  final DateTime takenAt;

  /// نوع الاتصال: wifi / ethernet / none.
  final String? connectionType;

  /// عناوين IP الخاصة بالجهاز.
  final List<String> deviceAddresses;

  /// البوابة الافتراضية.
  final String? gateway;

  /// خوادم DNS المستخدمة.
  final List<String> dnsServers;

  /// هل يتوفر اتصال بالإنترنت؟
  final bool hasInternet;

  /// زمن الاستجابة لاختبار الإنترنت.
  final int? internetLatencyMs;

  /// رمز HTTP لاختبار الإنترنت.
  final int? internetStatusCode;

  /// عنوان صفحة البوابة.
  final String? portalTitle;

  /// رمز HTTP لصفحة البوابة.
  final int? portalStatusCode;

  /// رابط صفحة البوابة.
  final String? portalUrl;

  /// رسالة خطأ إن وُجدت.
  final String? error;

  /// هل اكتمل الفحص دون أخطاء؟
  bool get hasError => error != null && error!.isNotEmpty;

  /// وصف عربي لنوع الاتصال.
  String get connectionLabel {
    switch (connectionType) {
      case 'wifi':
        return 'واي فاي';
      case 'ethernet':
        return 'إيثرنت';
      case 'vpn':
        return 'VPN';
      case 'mobile':
        return 'شبكة الجوال';
      case 'other':
        return 'أخرى';
      case 'none':
        return 'غير متصل';
      default:
        return 'غير معروف';
    }
  }
}
