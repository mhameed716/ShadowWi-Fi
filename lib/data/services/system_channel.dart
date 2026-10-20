import 'package:flutter/services.dart';

import '../../core/app_constants.dart';

/// غلاف حول قناة المنصّة الأصلية (Android) لجلب معلومات النظام.
class SystemChannel {
  SystemChannel._();

  /// النسخة الوحيدة.
  static final SystemChannel instance = SystemChannel._();

  static const MethodChannel _channel =
      MethodChannel(AppConstants.systemChannelName);

  /// بوابة DHCP الافتراضية كما يقرأها النظام.
  Future<String?> gateway() async {
    try {
      final String? value =
          await _channel.invokeMethod<String>('getGateway');
      if (value == null || value.trim().isEmpty) return null;
      return value.trim();
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// خوادم DNS المستخدمة حالياً.
  Future<List<String>> dnsServers() async {
    try {
      final List<dynamic>? value =
          await _channel.invokeMethod<List<dynamic>>('getDnsServers');
      if (value == null) return const <String>[];
      return value.map((dynamic e) => e.toString()).toList();
    } on PlatformException {
      return const <String>[];
    } on MissingPluginException {
      return const <String>[];
    }
  }

  /// معلومات الجهاز: العناوين، نوع الشبكة، وMAC.
  Future<Map<String, dynamic>> deviceInfo() async {
    try {
      final Map<dynamic, dynamic>? value =
          await _channel.invokeMethod<Map<dynamic, dynamic>>('getDeviceInfo');
      if (value == null) return <String, dynamic>{};
      return value.map<String, dynamic>(
        (dynamic key, dynamic val) => MapEntry<String, dynamic>(
          key.toString(),
          val is Map ? val.map<String, dynamic>(
                (dynamic k, dynamic v) =>
                    MapEntry<String, dynamic>(k.toString(), v),
              ) as dynamic : val,
        ),
      );
    } on PlatformException {
      return <String, dynamic>{};
    } on MissingPluginException {
      return <String, dynamic>{};
    }
  }

  /// محاولة اتصال حاسمة عبر WifiNetworkSpecifier (أندرويد 10+).
  ///
  /// يعيد: connected=true/false + message — نتيجة نهائية من النظام.
  Future<Map<String, dynamic>> connectViaSpecifier({
    required String ssid,
    required String password,
    bool wpa3 = false,
    int timeoutMs = 25000,
  }) async {
    try {
      final Map<dynamic, dynamic>? value =
          await _channel.invokeMethod<dynamic>('connectViaSpecifier', <String, dynamic>{
        'ssid': ssid,
        'password': password,
        'wpa3': wpa3,
        'timeoutMs': timeoutMs,
      });
      if (value == null) {
        return <String, dynamic>{'connected': false, 'message': 'لا استجابة'};
      }
      return value.map<String, dynamic>(
        (dynamic key, dynamic val) =>
            MapEntry<String, dynamic>(key.toString(), val),
      );
    } on PlatformException catch (error) {
      return <String, dynamic>{
        'connected': false,
        'message': error.message ?? 'فشل طلب الاتصال',
      };
    } on MissingPluginException {
      return <String, dynamic>{
        'connected': false,
        'unsupported': true,
        'message': 'القناة غير متاحة',
      };
    }
  }

  /// يفتح لوحة الواي فاي الرسمية (أندرويد 10+) — الاتصال بضغطة من النظام.
  Future<bool> openWifiPanel() async {
    try {
      await _channel.invokeMethod<void>('openWifiPanel');
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// محاولة الاتصال الحقيقي بشبكة واي فاي بكلمة مرور.
  ///
  /// يعيد خريطة من المنصة: mode = legacy | suggestion | error + message.
  Future<Map<String, dynamic>> connectToWifi({
    required String ssid,
    required String password,
    bool wpa3 = false,
  }) async {
    try {
      final Map<dynamic, dynamic>? value =
          await _channel.invokeMethod<dynamic>('connectToWifi', <String, dynamic>{
        'ssid': ssid,
        'password': password,
        'wpa3': wpa3,
      });
      if (value == null) return <String, dynamic>{'mode': 'error'};
      return value.map<String, dynamic>(
        (dynamic key, dynamic val) =>
            MapEntry<String, dynamic>(key.toString(), val),
      );
    } on PlatformException catch (error) {
      return <String, dynamic>{'mode': 'error', 'message': error.message};
    } on MissingPluginException {
      return <String, dynamic>{
        'mode': 'error',
        'message': 'القناة النظامية غير متاحة على هذه المنصة',
      };
    }
  }

  /// هل الجهاز متصل فعلياً بالشبكة المطلوبة الآن؟
  /// حالة التحقق من الشبكة (validated / captivePortal) من النظام.
  Future<Map<String, dynamic>> captiveState() async {
    try {
      final Map<dynamic, dynamic>? value =
          await _channel.invokeMethod<dynamic>('getCaptiveState');
      if (value == null) return <String, dynamic>{};
      return value.map<String, dynamic>(
        (dynamic key, dynamic val) =>
            MapEntry<String, dynamic>(key.toString(), val),
      );
    } on PlatformException {
      return <String, dynamic>{};
    } on MissingPluginException {
      return <String, dynamic>{};
    }
  }

  /// حالة الاقتران الخام (SCANNING/ASSOCIATED/FOUR_WAY_HANDSHAKE/...).
  Future<String> supplicantState() async {
    try {
      final String? value =
          await _channel.invokeMethod<String>('getSupplicantState');
      return value ?? 'UNKNOWN';
    } on PlatformException {
      return 'UNKNOWN';
    } on MissingPluginException {
      return 'UNKNOWN';
    }
  }

  Future<bool> isConnectedTo(String ssid) async {
    try {
      final bool? value = await _channel
          .invokeMethod<bool>('isConnectedTo', <String, String>{'ssid': ssid});
      return value ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// نسيان الشبكة (حذف الإعداد أو الاقتراح المحفوظ).
  Future<bool> forgetNetwork(String ssid) async {
    try {
      final bool? value = await _channel
          .invokeMethod<bool>('forgetNetwork', <String, String>{'ssid': ssid});
      return value ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// يفتح إعدادات الواي فاي في النظام.
  Future<bool> openWifiSettings() async {
    try {
      await _channel.invokeMethod<void>('openWifiSettings');
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// يفتح إعدادات الموقع في النظام (لتفعيل خدمة الموقع).
  Future<bool> openLocationSettings() async {
    try {
      await _channel.invokeMethod<void>('openLocationSettings');
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// معلومات الواي فاي المتصلة: SSID، BSSID، القوة، والتردد.
  Future<Map<String, dynamic>> wifiInfo() async {
    try {
      final Map<dynamic, dynamic>? value =
          await _channel.invokeMethod<Map<dynamic, dynamic>>('getWifiInfo');
      if (value == null) return <String, dynamic>{};
      return value.map<String, dynamic>(
        (dynamic key, dynamic val) =>
            MapEntry<String, dynamic>(key.toString(), val),
      );
    } on PlatformException {
      return <String, dynamic>{};
    } on MissingPluginException {
      return <String, dynamic>{};
    }
  }
}
