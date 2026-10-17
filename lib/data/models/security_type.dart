/// أنواع الحماية المدعومة في شبكات الواي فاي القريبة.
enum SecurityType {
  open,
  wep,
  wpa,
  wpa2,
  wpa2Enterprise,
  wpa3,
  wpa3Enterprise,
  unknown,
}

extension SecurityTypeX on SecurityType {
  /// الاسم العربي المعروض.
  String get label {
    switch (this) {
      case SecurityType.open:
        return 'مفتوحة';
      case SecurityType.wep:
        return 'WEP';
      case SecurityType.wpa:
        return 'WPA';
      case SecurityType.wpa2:
        return 'WPA2';
      case SecurityType.wpa2Enterprise:
        return 'WPA2 مؤسسي';
      case SecurityType.wpa3:
        return 'WPA3';
      case SecurityType.wpa3Enterprise:
        return 'WPA3 مؤسسي';
      case SecurityType.unknown:
        return 'غير معروف';
    }
  }

  /// هل الشبكة مشفّرة؟
  bool get isSecure => this != SecurityType.open && this != SecurityType.unknown;

  /// لوّن الحالة حسب درجة الحماية.
  String get colorHex {
    switch (this) {
      case SecurityType.wpa3:
      case SecurityType.wpa3Enterprise:
        return '#22C55E';
      case SecurityType.wpa2:
      case SecurityType.wpa2Enterprise:
      case SecurityType.wpa:
        return '#38BDF8';
      case SecurityType.wep:
        return '#F59E0B';
      case SecurityType.open:
        return '#EF4444';
      case SecurityType.unknown:
        return '#94A3B8';
    }
  }
}
