import 'dart:async';

import 'package:wifi_scan/wifi_scan.dart';

import '../models/security_type.dart';
import '../models/wifi_network_item.dart';
import 'permission_service.dart';

/// سبب حجب الفحص — يحدد واجهة الشرح المناسبة للمستخدم.
enum WifiScanBlocker {
  /// أذونات الموقع/الأجهزة القريبة غير ممنوحة.
  permissions,

  /// خدمة الموقع في النظام مغلقة (شرط لنتائج الفحص على أندرويد).
  locationService,
}

/// خطأ مخصص أثناء فحص الشبكات مع سببه الجذري.
class WifiScanException implements Exception {
  const WifiScanException(this.message, {this.blocker});

  /// الرسالة العربية.
  final String message;

  /// سبب الحجب إن كان قابلاً للمعالجة من المستخدم.
  final WifiScanBlocker? blocker;

  @override
  String toString() => message;
}

/// خدمة فحص شبكات الواي فاي القريبة الحقيقية عبر حزمة wifi_scan.
///
/// تعمل بالكامل دون إنترنت: قراءة نتائج الفحص عملية محلية على الجهاز.
class WifiScanService {
  WifiScanService(this._permissions);

  final PermissionService _permissions;

  /// مهلة انتظار وصول نتائج الفحص عبر البث.
  static const Duration _resultsTimeout = Duration(seconds: 8);

  /// يفحص الشبكات القريبة فعلياً ويعيد قائمتها مرتبة بالقوة.
  ///
  /// يرمي [WifiScanException] مع [WifiScanBlocker] واضح عند وجود عائق
  /// (أذونات ناقصة أو خدمة موقع مغلقة) بدلاً من إعادة قائمة فارغة.
  Future<List<WifiNetworkItem>> scan() async {
    // 1) طلب الأذونات أولاً (الموقع + الأجهزة القريبة على أندرويد 13+).
    await _permissions.requestScanPermissions();

    // 2) سؤال الحزمة نفسها: هل يمكن الحصول على النتائج الآن؟ ولماذا لا؟
    final CanGetScannedResults can = await WiFiScan.instance
        .canGetScannedResults(askPermissions: false);

    switch (can) {
      case CanGetScannedResults.yes:
        break;

      case CanGetScannedResults.noLocationPermissionRequired:
      case CanGetScannedResults.noLocationPermissionDenied:
      case CanGetScannedResults.noLocationPermissionUpgradeAccuracy:
        throw const WifiScanException(
          'إذن الوصول إلى الموقع مطلوب لعرض الشبكات القريبة',
          blocker: WifiScanBlocker.permissions,
        );

      case CanGetScannedResults.noLocationServiceDisabled:
        throw const WifiScanException(
          'خدمة الموقع مغلقة — فعّلها من إعدادات النظام لعرض الشبكات',
          blocker: WifiScanBlocker.locationService,
        );

      case CanGetScannedResults.notSupported:
        throw const WifiScanException(
          'هذا الجهاز لا يدعم فحص شبكات الواي فاي',
        );

      default:
        // أي سبب آخر غير مذكور صراحة (مثل failed في إصدارات أحدث).
        throw const WifiScanException(
          'تعذّر بدء الفحص — أعد المحاولة بعد لحظات',
        );
    }

    // 3) الاستماع للبث قبل تفعيل الفحص حتى لا نفوّت أول دفعة نتائج.
    final Completer<List<WiFiAccessPoint>> completer =
        Completer<List<WiFiAccessPoint>>();
    StreamSubscription<List<WiFiAccessPoint>>? subscription;
    try {
      subscription = WiFiScan.instance.onScannedResultsAvailable.listen(
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
      // قد يفشل التفعيل بسبب حد الفحص (4 مرات/30 ثانية في أندرويد) —
      // عندها نكتفي بالنتائج المخزّنة من آخر فحص ناجح.
      await WiFiScan.instance.startScan();
      try {
        accessPoints = await completer.future.timeout(_resultsTimeout);
      } on TimeoutException {
        accessPoints = await WiFiScan.instance.getScannedResults();
      }
    } on TimeoutException {
      throw const WifiScanException(
        'انتهت مهلة الفحص — اسحب للأسفل لإعادة المحاولة',
      );
    } catch (error) {
      throw WifiScanException('تعذّر فحص الشبكات: $error');
    } finally {
      await subscription?.cancel();
    }

    return _mapAccessPoints(accessPoints);
  }

  /// يحول نتائج الحزمة إلى نماذج التطبيق مع إزالة التكرار والترتيب بالقوة.
  static List<WifiNetworkItem> _mapAccessPoints(
    List<WiFiAccessPoint> accessPoints,
  ) {
    final Map<String, WifiNetworkItem> unique = <String, WifiNetworkItem>{};
    for (final WiFiAccessPoint network in accessPoints) {
      final WifiNetworkItem item = WifiNetworkItem(
        ssid: network.ssid,
        bssid: network.bssid,
        level: network.level,
        frequency: network.frequency,
        security: resolveSecurity(network.capabilities),
      );
      final String key = item.bssid.isEmpty ? item.ssid : item.bssid;
      final WifiNetworkItem? existing = unique[key];
      if (existing == null || item.level > existing.level) {
        unique[key] = item;
      }
    }

    final List<WifiNetworkItem> sorted = unique.values.toList()
      ..sort(
        (WifiNetworkItem a, WifiNetworkItem b) => b.level.compareTo(a.level),
      );
    return sorted;
  }

  /// يستنتج نوع الحماية من نص قدرات نقطة الوصول،
  /// مثل `[WPA2-PSK-CCMP][ESS][WPS]` أو `[WPA3-SAE-CCMP][ESS]`.
  static SecurityType resolveSecurity(String capabilities) {
    final String text = capabilities.toUpperCase();
    if (text.isEmpty) return SecurityType.unknown;

    final bool enterprise = text.contains('802.1X') ||
        text.contains('EAP') ||
        text.contains('8021X');

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
