import '../models/security_type.dart';
import 'system_channel.dart';

/// نتيجة طلب الاتصال بالشبكة من المنصة.
class WifiConnectResult {
  const WifiConnectResult({
    required this.mode,
    this.message,
    this.status,
    this.netId,
  });

  /// legacy = بدأ اتصال برمجي كامل (أندرويد 9-)،
  /// suggestion = قُدّم اقتراح للنظام (أندرويد 10+)،
  /// error = فشل الطلب.
  final String mode;

  /// رسالة عربية من المنصة.
  final String? message;

  /// رمز حالة الاقتراح (أندرويد 10+).
  final int? status;

  /// معرّف الشبكة (المسار التقليدي).
  final int? netId;

  /// هل بدأ الاتصال فعلاً (بأي مسار)؟
  bool get initiated => mode == 'legacy' || mode == 'suggestion';

  /// هل هو المسار التقليدي (اتصال صامت كامل)؟
  bool get isLegacy => mode == 'legacy';
}

/// غلاف عالي المستوى حول الاتصال الحقيقي بالواي فاي.
class WifiConnectService {
  WifiConnectService(this._system);

  final SystemChannel _system;

  /// مهلة انتظار تأكيد الاتصال بعد كل محاولة.
  static const Duration connectTimeout = Duration(seconds: 20);

  /// الفاصل بين استعلامات حالة الاتصال.
  static const Duration pollInterval = Duration(milliseconds: 300);

  /// يستنتج هل الشبكة WPA3 لاختيار مسار كلمة المرور المناسب.
  static bool isWpa3(SecurityType security) {
    return security == SecurityType.wpa3 ||
        security == SecurityType.wpa3Enterprise;
  }

  /// حالات الارتباط بالشبكة — بلوغها يعني بدء التفاوض الفعلي.
  /// ASSOCIATED مشمولة عمداً: الارتباط ثم الانفصال هو التوقيع الحقيقي
  /// لكلمة المرور الخاطئة حتى دون التقاط لحظة المصادقة العابرة.
  static const Set<String> _linkStates = <String>{
    'ASSOCIATED',
    'FOUR_WAY_HANDSHAKE',
    'GROUP_HANDSHAKE',
    'COMPLETED',
  };

  /// حالات الارتداد — بعد مرور المصادقة تعني كلمة مرور خاطئة.
  static const Set<String> _regressedStates = <String>{
    'SCANNING',
    'ASSOCIATING',
    'ASSOCIATED',
    'DISCONNECTED',
    'DORMANT',
    'INACTIVE',
    'UNINITIALIZED',
    'INVALID',
    'INTERFACE_DISABLED',
    'LOGOFF',
  };

  /// هل الحالة من حالات الارتباط بالشبكة؟
  static bool isLinkState(String state) =>
      _linkStates.contains(state.toUpperCase());

  /// هل وُجد انفصال بعد ارتباط حقيقي (توقيع كلمة مرور خاطئة)؟
  ///
  /// هذا التوقيع الجوهري: النظام يرتبط بالشبكة ثم يفشل التفاوض على
  /// كلمة خاطئة فينفض الجلسة ويعود للفحص — الاقتران الصحيح لا يرتد.
  /// لا يُصدَّق الانفصال قبل رؤية ارتباط فعلي في هذه المحاولة.
  static bool authRegressionObserved({
    required String? state,
    required bool sawLink,
  }) {
    if (!sawLink || state == null) return false;
    return _regressedStates.contains(state.toUpperCase());
  }

  /// نسخة أندرويد المخزنة (29+ = مسار Specifier الحاسم).
  int? _cachedSdk;

  /// إصدار أندرويد (يُقرأ مرة واحدة من قناة النظام).
  Future<int> sdkVersion() async {
    if (_cachedSdk != null) return _cachedSdk!;
    try {
      final Map<String, dynamic> info = await _system.deviceInfo();
      final Object? sdk = info['sdk'];
      _cachedSdk = sdk is int ? sdk : 29;
    } catch (_) {
      _cachedSdk = 29;
    }
    return _cachedSdk!;
  }

  /// المحاولة الحاسمة عبر WifiNetworkSpecifier (أندرويد 10+).
  ///
  /// النظام يحاول الاقتران بالشبكة بكلمة المرور ويعيد نتيجة نهائية:
  /// connected=true يعني اقترنا فعلاً، false يعني فشلاً مع سبب دقيق
  /// (واي فاي مغلق / الموقع مغلق / كلمة خاطئة / انتهاء مهلة).
  Future<SpecifierConnectResult> connectViaSpecifier({
    required String ssid,
    required String password,
    bool wpa3 = false,
    int timeoutMs = 25000,
  }) async {
    final Map<String, dynamic> raw = await _system.connectViaSpecifier(
      ssid: ssid,
      password: password,
      wpa3: wpa3,
      timeoutMs: timeoutMs,
    );
    return SpecifierConnectResult(
      connected: raw['connected'] == true,
      message: raw['message']?.toString(),
      unsupported: raw['unsupported'] == true,
      reason: raw['reason']?.toString(),
    );
  }

  /// رسالة عربية دقيقة حسب سبب فشل الاقتران.
  static String specifierFailureMessage(String? reason) {
    switch (reason) {
      case 'wifi_off':
        return 'الواي فاي مغلق — فعّله ثم أعد المحاولة';
      case 'location_off':
        return 'خدمة الموقع مغلقة — أندرويد يشترطها لاقتران الواي فاي';
      case 'timeout':
        return 'انتهت المهلة دون اقتران — تأكد من قرب الراوتر وقوة إشارته';
      case 'declined':
        return 'أُلغيت نافذة النظام «اختيار جهاز» — أعد المحاولة واضغط على '
            'اسم شبكتك داخلها ثم اقبل';
      case 'error':
        return 'تعذّر تنفيذ طلب الاقتران على هذا الجهاز';
      case 'unsupported':
        return 'هذا الجهاز لا يدعم المسار الحاسم — جُرِّب المسار البديل';
      default:
        return 'لم يتم الاقتران — إذا ظهرت نافذة تأكيد من النظام اختر '
            'الشبكة واضغط «اتصال»، وتأكد من صحة كلمة المرور';
    }
  }

  /// يفتح إعدادات الموقع (لتفعيل خدمة الموقع المطلوبة للاقتران).
  Future<bool> openLocationSettings() => _system.openLocationSettings();

  /// يطلب من المنصة الاتصال/حفظ الشبكة (اقتراح على 10+، كامل على 9-).
  Future<WifiConnectResult> connect({
    required String ssid,
    required String password,
    bool wpa3 = false,
  }) async {
    final Map<String, dynamic> raw =
        await _system.connectToWifi(ssid: ssid, password: password, wpa3: wpa3);
    return WifiConnectResult(
      mode: (raw['mode'] ?? 'error').toString(),
      message: raw['message']?.toString(),
      status: raw['status'] is int ? raw['status'] as int : null,
      netId: raw['netId'] is int ? raw['netId'] as int : null,
    );
  }

  /// هل الجهاز متصل فعلياً بالشبكة الآن؟
  Future<bool> isConnectedTo(String ssid) => _system.isConnectedTo(ssid);

  /// حالة الاقتران الخام من المنصة (لكشف فشل المصادقة مبكراً).
  Future<String> supplicantState() => _system.supplicantState();

  /// نسيان الشبكة.
  Future<bool> forget(String ssid) => _system.forgetNetwork(ssid);

  /// بيانات الشبكة المتصلة حالياً (ssid/bssid/level/...).
  Future<Map<String, dynamic>> currentWifi() => _system.wifiInfo();

  /// لوحة الواي فاي الرسمية — الاتصال المضمون من النظام نفسه.
  Future<bool> openWifiPanel() => _system.openWifiPanel();

  /// يفتح إعدادات الواي فاي في النظام.
  Future<bool> openWifiSettings() => _system.openWifiSettings();
}

/// نتيجة المحاولة الحاسمة عبر الـ Specifier.
class SpecifierConnectResult {
  const SpecifierConnectResult({
    required this.connected,
    this.message,
    this.unsupported = false,
    this.reason,
  });

  /// هل تم الاقتران بالشبكة فعلاً؟
  final bool connected;

  /// رسالة عربية من المنصة.
  final String? message;

  /// المسار غير مدعوم على هذه المنصة (أندرويد 9-).
  final bool unsupported;

  /// سبب الفشل الدقيق: wifi_off/location_off/timeout/error/unavailable.
  final String? reason;

  /// هل السبب نظامي يُصلَح من الإعدادات (الواي فاي أو الموقع مغلق)؟
  /// في هذه الحالة إعادة المحاولة بلا فائدة حتى يُرفع المانع.
  bool get needsSystemFix =>
      reason == 'wifi_off' || reason == 'location_off';
}
