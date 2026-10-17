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
  static const Duration connectTimeout = Duration(seconds: 14);

  /// الفاصل بين استعلامات حالة الاتصال.
  static const Duration pollInterval = Duration(seconds: 2);

  /// يستنتج هل الشبكة WPA3 لاختيار مسار كلمة المرور المناسب.
  static bool isWpa3(SecurityType security) {
    return security == SecurityType.wpa3 ||
        security == SecurityType.wpa3Enterprise;
  }

  /// يطلب من المنصة الاتصال بالشبكة.
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

  /// نسيان الشبكة.
  Future<bool> forget(String ssid) => _system.forgetNetwork(ssid);

  /// بيانات الشبكة المتصلة حالياً (ssid/bssid/level/...).
  Future<Map<String, dynamic>> currentWifi() => _system.wifiInfo();

  /// يفتح إعدادات الواي فاي في النظام.
  Future<bool> openWifiSettings() => _system.openWifiSettings();
}
