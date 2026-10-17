/// ثوابت التطبيق العامة: العناوين، البوابات الافتراضية، والمهل الزمنية.
class AppConstants {
  const AppConstants._();

  /// اسم التطبيق كما يظهر في شريط العنوان.
  static const String appTitle = 'ShadowWi-Fi';

  /// العنوان الفرعي العربي.
  static const String appSubtitle = 'أدوات بوابة الشبكة';

  /// إصدار التطبيق المعروض في الواجهة (يزامن pubspec.yaml يدوياً).
  static const String appVersion = '1.1.2';

  /// اسم الباقة وعنوان القناة الأصلية.
  static const String packageName = 'com.shadowwifi.app';
  static const String systemChannelName = 'com.shadowwifi.app/system';

  /// عنوان فحص الاتصال بالإنترنت (يرجع 204 عند النجاح).
  static const String internetCheckUrl =
      'http://connectivitycheck.gstatic.com/generate_204';

  /// وجهة الاتصال الافتراضية بعد نجاح الدخول إلى البوابة.
  static const String defaultDestination = 'http://neverssl.com';

  /// مهلة فحص البوابة الافتراضية.
  static const Duration probeTimeout = Duration(seconds: 4);

  /// مهلة محاولة تسجيل الدخول.
  static const Duration loginTimeout = Duration(seconds: 10);

  /// مهلة التحقق من الإنترنت بعد تسجيل الدخول.
  static const Duration internetTimeout = Duration(seconds: 8);

  /// مدة مسح شبكات الواي فاي.
  static const Duration scanDuration = Duration(seconds: 6);

  /// البوابات الشائعة التي يتم فحصها عند تعذّر اكتشافها من النظام.
  static const List<String> commonGateways = <String>[
    '192.168.1.1',
    '192.168.0.1',
    '192.168.88.1',
    '192.168.2.1',
    '10.0.0.1',
    '10.0.1.1',
    '10.1.1.1',
    '172.16.0.1',
  ];

  /// البوابة الافتراضية المستخدمة عند فشل كل الفحوصات (MikroTik).
  static const String fallbackGateway = '192.168.88.1';

  /// حجم ملف السجل الأقصى (بالكيلوبايت) قبل تدويره.
  static const int maxLogFileSizeKb = 512;
}
