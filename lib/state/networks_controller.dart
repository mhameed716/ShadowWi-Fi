import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../data/models/wifi_network_item.dart';
import '../data/services/permission_service.dart';
import '../data/services/wifi_scan_service.dart';

/// حالات أذون الموقع.
enum LocationPermissionState {
  unknown,
  granted,
  denied,
  permanentlyDenied,
}

/// manages تبويب الشبكات وفحصها.
class NetworksController extends ChangeNotifier {
  NetworksController(this._scanService);

  final WifiScanService _scanService;

  /// الشبكات المكتشفة.
  List<WifiNetworkItem> networks = <WifiNetworkItem>[];

  /// هل جارٍ الفحص؟
  bool scanning = false;

  /// حالة إذن الموقع.
  LocationPermissionState permission = LocationPermissionState.unknown;

  /// رسالة خطأ آنية.
  String? error;

  /// آخر وقت تم فيه الفحص.
  DateTime? lastScanAt;

  /// يحدّث حالة إذن الموقع.
  Future<void> refreshPermissionState() async {
    final PermissionService permissions = PermissionService.instance;
    final PermissionStatus status = await permissions.locationStatus();
    permission = _mapStatus(status);
    notifyListeners();
  }

  /// يفحص الشبكات القريبة (مع السحب للتحديث).
  Future<void> scan() async {
    if (scanning) return;
    scanning = true;
    error = null;
    notifyListeners();

    try {
      await refreshPermissionState();
      networks = await _scanService.scan();
      lastScanAt = DateTime.now();
      permission = LocationPermissionState.granted;
    } on WifiScanException catch (e) {
      error = e.message;
      await refreshPermissionState();
    } catch (e) {
      error = 'تعذّر فحص الشبكات: $e';
    } finally {
      scanning = false;
      notifyListeners();
    }
  }

  /// يطلب الأذونات مرة أخرى.
  Future<bool> requestPermission() async {
    final bool granted =
        await PermissionService.instance.requestScanPermissions();
    await refreshPermissionState();
    if (granted) {
      await scan();
    }
    return granted;
  }

  /// يفتح إعدادات التطبيق.
  Future<void> openSettings() async {
    await PermissionService.instance.openSettings();
  }

  /// هل نحتاج إلى شرح سبب طلب الإذن؟
  bool get needsRationale => permission == LocationPermissionState.denied;

  /// هل الإذن ممنوع نهائياً؟
  bool get isPermanentlyDenied =>
      permission == LocationPermissionState.permanentlyDenied;

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
