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
