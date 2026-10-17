import 'dart:async';

import 'package:wifi_scan/wifi_scan.dart';

import '../models/security_type.dart';
import '../models/wifi_network_item.dart';
import 'permission_service.dart';

/// خطأ مخصص أثناء فحص الشبكات.
class WifiScanException implements Exception {
  const WifiScanException(this.message);

  /// الرسالة العربية.
  final String message;

  @override
  String toString() => message;
}

/// خدمة فحص شبكات الواي فاي القريبة باستخدام حزمة wifi_scan.
class WifiScanService {
  WifiScanService(this._permissions);

  final PermissionService _permissions;

  /// مهلة انتظار وصول نتائج الفحص عبر البث.
  static const Duration _resultsTimeout = Duration(seconds: 8);

  /// يفحص الشبكات القريبة بعد التأكد من إذن الموقع.
  Future<List<WifiNetworkItem>> scan() async {
    final bool granted = await _permissions.requestScanPermissions();
    if (!granted) {
      throw const WifiScanException(
        'يلزم السماح بالوصول إلى الموقع لفحص شبكات الواي فاي القريبة',
      );
    }

    final WiFiScan scanner = WiFiScan.instance;

    // نستمع للبث قبل تفعيل الفحص حتى لا نفوّت أول دفعة نتائج.
    final Completer<List<WiFiAccessPoint>> completer =
        Completer<List<WiFiAccessPoint>>();
    StreamSubscription<List<WiFiAccessPoint>>? subscription;
    try {
      subscription = scanner.onScannedResultsAvailable.listen(
        (List<WiFiAccessPoint> results) {
          if (!completer.isCompleted) completer.complete(results);
        },
        onError: (Object error) {
          if (!completer.isCompleted) completer.completeError(error);
        },
      );
    } catch (_) {
      // قد يفشل إنشاء البث على بعض الأجهزة؛ سنعتمد على النتائج المخزّنة.
    }

    List<WiFiAccessPoint> accessPoints;
    try {
      await scanner.startScan();
      try {
        accessPoints = await completer.future.timeout(_resultsTimeout);
      } on TimeoutException {
        // النتائج المخزّنة من آخر فحص ناجح.
        accessPoints = await scanner.getScannedResults();
      }
    } on TimeoutException {
      throw const WifiScanException('انتهت مهلة فحص الشبكات، أعد المحاولة');
    } catch (error) {
      throw WifiScanException('تعذّر فحص الشبكات: $error');
    } finally {
      await subscription?.cancel();
    }

    final List<WifiNetworkItem> items = <WifiNetworkItem>[];
    for (final WiFiAccessPoint network in accessPoints) {
      items.add(
        WifiNetworkItem(
          ssid: network.ssid,
          bssid: network.bssid,
          level: network.level,
          frequency: network.frequency,
          security: resolveSecurity(network.capabilities),
        ),
      );
    }

    // إزالة التكرار حسب BSSID ثم الترتيب حسب قوة الإشارة.
    final Map<String, WifiNetworkItem> unique = <String, WifiNetworkItem>{};
    for (final WifiNetworkItem item in items) {
      final String key = item.bssid.isEmpty ? item.ssid : item.bssid;
      final WifiNetworkItem? existing = unique[key];
      if (existing == null || item.level > existing.level) {
        unique[key] = item;
      }
    }

    final List<WifiNetworkItem> sorted = unique.values.toList()
      ..sort((WifiNetworkItem a, WifiNetworkItem b) => b.level.compareTo(a.level));

    return sorted;
  }

  /// يستنتج نوع الحماية من نص قدرات نقطة الوصول،
  /// مثل `[WPA2-PSK-CCMP][ESS][WPS]` أو `[WPA3-SAE-CCMP][ESS]`.
  static SecurityType resolveSecurity(String capabilities) {
    final String text = capabilities.toUpperCase();
    if (text.isEmpty) return SecurityType.unknown;

    final bool enterprise =
        text.contains('802.1X') || text.contains('EAP') || text.contains('8021X');

    if (text.contains('WPA3') || text.contains('SAE')) {
      return enterprise ? SecurityType.wpa3Enterprise : SecurityType.wpa3;
    }
    if (text.contains('WPA2') || text.contains('RSN')) {
      return enterprise ? SecurityType.wpa2Enterprise : SecurityType.wpa2;
    }
    if (text.contains('WPA')) {
      return enterprise ? SecurityType.wpa2Enterprise : SecurityType.wpa;
    }
    if (text.contains('WEP')) return SecurityType.wep;
    if (text.contains('NOPASS') || text == '[ESS]' || text.contains('OPEN')) {
      return SecurityType.open;
    }
    return SecurityType.unknown;
  }
}
