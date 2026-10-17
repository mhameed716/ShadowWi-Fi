import 'package:flutter_test/flutter_test.dart';
import 'package:shadow_wifi/data/models/security_type.dart';
import 'package:shadow_wifi/data/models/wifi_network_item.dart';
import 'package:shadow_wifi/state/network_attempts_controller.dart';

void main() {
  const WifiNetworkItem network = WifiNetworkItem(
    ssid: 'CafeWiFi',
    bssid: 'aa:bb:cc:dd:ee:ff',
    level: -55,
    frequency: 5180,
    security: SecurityType.wpa2,
  );

  group('NetworkAttemptsController', () {
    test('setTarget يحفظ الشبكة والبوابة', () {
      final NetworkAttemptsController controller = NetworkAttemptsController();
      final bool accepted = controller.setTarget(network, 'http://192.168.1.1');
      expect(accepted, isTrue);
      expect(controller.target?.displayName, 'CafeWiFi');
      expect(controller.gatewayUrl, 'http://192.168.1.1');
    });

    test('start بدون بوابة يعطي خطأ ولا يبدأ التشغيل', () async {
      final NetworkAttemptsController controller = NetworkAttemptsController();
      controller.setTarget(network, '');
      await controller.start();
      expect(controller.running, isFalse);
      expect(controller.takeError(), isNotNull);
    });

    test('start بدون رموز يعطي خطأ ولا يبدأ التشغيل', () async {
      final NetworkAttemptsController controller = NetworkAttemptsController();
      controller.setTarget(network, 'http://192.168.1.1');
      await controller.start();
      expect(controller.running, isFalse);
      expect(controller.takeError(), isNotNull);
    });

    test('canStart يتطلب بوابة ورمزاً معاً', () {
      final NetworkAttemptsController controller = NetworkAttemptsController();
      expect(controller.canStart, isFalse);

      controller.setTarget(network, 'http://192.168.1.1');
      expect(controller.canStart, isFalse);

      controller.setManualCode('12345');
      expect(controller.canStart, isTrue);
    });

    test('الرمز اليدوي يُستخدم عندما لا يوجد ملف', () {
      final NetworkAttemptsController controller = NetworkAttemptsController();
      expect(controller.effectiveCodes, isEmpty);
      controller.setManualCode('abc');
      expect(controller.effectiveCodes, <String>['abc']);
    });

    test('resetIfIdle يصفّر الحالة عند عدم التشغيل', () {
      final NetworkAttemptsController controller = NetworkAttemptsController();
      controller.setTarget(network, 'http://192.168.1.1');
      controller.setManualCode('xyz');
      controller.resetIfIdle();
      expect(controller.target, isNull);
      expect(controller.manualCode, isEmpty);
      expect(controller.total, 0);
    });

    test('setGateway يحدّث البوابة يدوياً للاستقلال عن الاكتشاف', () {
      final NetworkAttemptsController controller = NetworkAttemptsController();
      controller.setTarget(network, '');
      expect(controller.gatewayUrl, isEmpty);

      controller.setGateway('http://10.0.0.1');
      expect(controller.gatewayUrl, 'http://10.0.0.1');

      // setTarget ببوابة فارغة لا يمسح المدخل اليدوي.
      controller.setTarget(network, '');
      expect(controller.gatewayUrl, 'http://10.0.0.1');
    });

    test('الإيقاف المؤقت والاستئناف خارج التشغيل لا يغيّران الحالة', () {
      final NetworkAttemptsController controller = NetworkAttemptsController();
      controller.pause();
      expect(controller.paused, isFalse);
      controller.resume();
      expect(controller.running, isFalse);
    });
  });
}
