import 'package:flutter_test/flutter_test.dart';
import 'package:shadow_wifi/data/models/security_type.dart';
import 'package:shadow_wifi/data/models/wifi_network_item.dart';

void main() {
  group('نموذج شبكة الواي فاي', () {
    test('الشبكة المخفية تحصل على اسم بديل', () {
      const WifiNetworkItem item = WifiNetworkItem(
        ssid: '   ',
        bssid: 'aa:bb:cc:dd:ee:ff',
        level: -60,
        frequency: 2412,
        security: SecurityType.wpa2,
      );
      expect(item.displayName, 'شبكة مخفية');
    });

    test('نسبة القوة محصورة بين 0 و1', () {
      WifiNetworkItem build(int level) => WifiNetworkItem(
            ssid: 'Test',
            bssid: 'x',
            level: level,
            frequency: 2412,
            security: SecurityType.wpa2,
          );

      expect(build(-30).strengthRatio, 1.0);
      expect(build(-100).strengthRatio, 0.0);
      expect(build(-65).strengthRatio, inExclusiveRange(0.0, 1.0));
    });

    test('وصف القوة بالعربية', () {
      WifiNetworkItem build(int level) => WifiNetworkItem(
            ssid: 'Test',
            bssid: 'x',
            level: level,
            frequency: 2412,
            security: SecurityType.wpa2,
          );

      expect(build(-40).strengthLabel, 'ممتازة');
      expect(build(-55).strengthLabel, 'جيدة');
      expect(build(-70).strengthLabel, 'متوسطة');
      expect(build(-85).strengthLabel, 'ضعيفة');
      expect(build(-95).strengthLabel, 'ضعيفة');
    });

    test('نطاق التردد', () {
      WifiNetworkItem build(int frequency) => WifiNetworkItem(
            ssid: 'Test',
            bssid: 'x',
            level: -50,
            frequency: frequency,
            security: SecurityType.wpa3,
          );

      expect(build(2412).bandLabel, '2.4 جيجاهرتز');
      expect(build(5180).bandLabel, '5 جيجاهرتز');
      expect(build(6105).bandLabel, '6 جيجاهرتز');
    });
  });

  group('أنواع الحماية', () {
    test('الشبكات المفتوحة والمجهولة غير مشفّرة', () {
      expect(SecurityType.open.isSecure, isFalse);
      expect(SecurityType.unknown.isSecure, isFalse);
      expect(SecurityType.wpa2.isSecure, isTrue);
      expect(SecurityType.wpa3.isSecure, isTrue);
    });

    test('لكل نوع تسمية عربية', () {
      for (final SecurityType type in SecurityType.values) {
        expect(type.label, isNotEmpty);
      }
    });
  });
}
