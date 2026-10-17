import 'package:permission_handler/permission_handler.dart';

/// غلاف حول إدارة أذونات النظام أثناء التشغيل.
class PermissionService {
  PermissionService._();

  /// النسخة الوحيدة.
  static final PermissionService instance = PermissionService._();

  /// حالة إذن الموقع الحالي.
  Future<PermissionStatus> locationStatus() async {
    return Permission.locationWhenInUse.status;
  }

  /// هل الإذن ممنوع نهائياً؟
  Future<bool> isPermanentlyDenied() async {
    final PermissionStatus status = await locationStatus();
    return status.isPermanentlyDenied;
  }

  /// هل الإذن ممنوع؟
  Future<bool> isDenied() async {
    final PermissionStatus status = await locationStatus();
    return status.isDenied || status.isPermanentlyDenied || status.isRestricted;
  }

  /// يطلب إذن الموقع، ويعيد true عند الموافقة.
  Future<bool> requestLocation() async {
    final PermissionStatus status =
        await Permission.locationWhenInUse.request();
    return status.isGranted;
  }

  /// يطلب أذونات فحص الشبكات: الموقع + الأجهزة القريبة (أندرويد 13+).
  Future<bool> requestScanPermissions() async {
    final Map<Permission, PermissionStatus> results =
        await <Permission>[
          Permission.locationWhenInUse,
          Permission.nearbyWifiDevices,
        ].request();

    final PermissionStatus location =
        results[Permission.locationWhenInUse] ?? PermissionStatus.denied;
    if (location.isGranted) return true;

    // على أندرويد 13+ مع neverForLocation يكفي إذن الأجهزة القريبة.
    final PermissionStatus nearby =
        results[Permission.nearbyWifiDevices] ?? PermissionStatus.denied;
    return nearby.isGranted;
  }

  /// يفتح إعدادات التطبيق Allow للمستخدم مراجعة الأذونات.
  Future<bool> openSettings() => openAppSettings();
}
