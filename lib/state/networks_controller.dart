import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../data/models/wifi_network_item.dart';
import '../data/services/permission_service.dart';
import '../data/services/system_channel.dart';
import '../data/services/wifi_scan_service.dart';

/// معلومات الشبكة المتصلة حالياً ( ssid/bssid/قوة/تردد).
Map<String, dynamic> _emptyWifi() => <String, dynamic>{};

/// حالة أذون الموقع.
enum LocationPermissionState {
  unknown,
  granted,
  denied,
  permanentlyDenied,
}

/// يدير تبويب الشبكات: الفحص الحقيقي، الأذونات، وحالة العوائق.
class NetworksController extends ChangeNotifier {
  NetworksController(this._scanService);

  final WifiScanService _scanService;

  /// الشبكات المكتشفة.
  List<WifiNetworkItem> networks = <WifiNetworkItem>[];

  /// هل جارٍ الفحص؟
  bool scanning = false;

  /// حالة إذن الموقع.
  LocationPermissionState permission = LocationPermissionState.unknown;

  /// عائق حالي يمنع الفحص (أذونات أو خدمة الموقع) — null عند سماح الفحص.
  ///
  /// عندما لا يكون null تعرض الواجهة بطاقة المعالجة **بدلاً** من حالة
  /// «لا توجد شبكات»، إذ إن القائمة الفارغة هنا مضللة.
  WifiScanBlocker? blocker;

  /// رسالة خطأ آنية.
  String? error;

  /// آخر وقت تم فيه الفحص.
  DateTime? lastScanAt;

  /// معلومات الشبكة المتصلة حالياً (فارغة إن لم يكن هناك اتصال).
  Map<String, dynamic> currentWifi = _emptyWifi();

  /// يعيد قراءة بيانات الشبكة المتصلة من النظام.
  Future<void> refreshCurrentWifi() async {
    try {
      final Map<String, dynamic> info =
          await SystemChannel.instance.wifiInfo();
      currentWifi = info;
      notifyListeners();
    } catch (_) {
      currentWifi = _emptyWifi();
    }
  }

  /// يحدّث حالة إذن الموقع.
  Future<void> refreshPermissionState() async {
    final PermissionService permissions = PermissionService.instance;
    final PermissionStatus status = await permissions.locationStatus();
    permission = _mapStatus(status);
    notifyListeners();
  }

  /// يفحص الشبكات القريبة فعلياً (يعمل دون إنترنت).
  Future<void> scan() async {
    if (scanning) return;
    scanning = true;
    error = null;
    blocker = null;
    notifyListeners();

    try {
      networks = await _scanService.scan();
      lastScanAt = DateTime.now();
      permission = LocationPermissionState.granted;
      await refreshCurrentWifi();
    } on WifiScanException catch (e) {
      blocker = e.blocker;
      error = e.message;
      await refreshPermissionState();
    } catch (e) {
      error = 'تعذّر فحص الشبكات: $e';
      await refreshPermissionState();
    } finally {
      scanning = false;
      notifyListeners();
    }
  }

  /// يطلب الأذونات من المستخدم، وعند المنح يبدأ الفحص تلقائياً.
  Future<bool> requestPermission() async {
    final bool granted =
        await PermissionService.instance.requestScanPermissions();
    await refreshPermissionState();
    if (granted) {
      blocker = null;
      await scan();
    }
    return granted;
  }

  /// يفتح إعدادات التطبيق (للمنح بعد رفض نهائي).
  Future<void> openSettings() async {
    await PermissionService.instance.openSettings();
  }

  /// يفتح إعدادات الموقع في النظام لتفعيل خدمة الموقع.
  Future<void> openLocationSettings() async {
    await SystemChannel.instance.openLocationSettings();
  }

  /// رسالة خطأ آنية (تُستهلك مرة واحدة).
  String? takeError() {
    final String? value = error;
    error = null;
    return value;
  }

  static LocationPermissionState _mapStatus(PermissionStatus status) {
    if (status.isGranted || status.isLimited) {
      return LocationPermissionState.granted;
    }
    if (status.isPermanentlyDenied) {
      return LocationPermissionState.permanentlyDenied;
    }
    if (status.isDenied || status.isRestricted) {
      return LocationPermissionState.denied;
    }
    return LocationPermissionState.unknown;
  }
}
