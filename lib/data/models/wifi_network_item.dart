import 'security_type.dart';

/// عنصر شبكة واي فاي قريبة.
class WifiNetworkItem {
  const WifiNetworkItem({
    required this.ssid,
    required this.bssid,
    required this.level,
    required this.frequency,
    required this.security,
    this.isConnected = false,
  });

  /// اسم الشبكة.
  final String ssid;

  /// عنوان MAC الخاص بواجهة الشبكة.
  final String bssid;

  /// قوة الإشارة بوحدة dBm.
  final int level;

  /// التردد بالميغاهرتز.
  final int frequency;

  /// نوع الحماية.
  final SecurityType security;

  /// هل هي الشبكة المتصلة حالياً.
  final bool isConnected;

  /// اسم معروض: اسم الشبكة أو "شبكة مخفية".
  String get displayName {
    final String trimmed = ssid.trim();
    if (trimmed.isEmpty) return 'شبكة مخفية';
    return trimmed;
  }

  /// نسبة القوة من 0 إلى 1.
  double get strengthRatio {
    const int min = -100;
    const int max = -30;
    if (level >= max) return 1;
    if (level <= min) return 0;
    return ((level - min) / (max - min)).clamp(0.0, 1.0).toDouble();
  }

  /// وصف عربي لقوة الإشارة.
  String get strengthLabel {
    final double ratio = strengthRatio;
    if (ratio >= 0.85) return 'ممتازة';
    if (ratio >= 0.6) return 'جيدة';
    if (ratio >= 0.35) return 'متوسطة';
    if (ratio > 0) return 'ضعيفة';
    return 'غير متاحة';
  }

  /// نطاق التردد.
  String get bandLabel {
    if (frequency >= 5925) return '6 جيجاهرتز';
    if (frequency >= 4900) return '5 جيجاهرتز';
    if (frequency >= 2400) return '2.4 جيجاهرتز';
    return 'غير معروف';
  }

  @override
  String toString() =>
      'WifiNetworkItem(ssid: $ssid, level: $level, security: ${security.name})';
}
