import 'package:flutter_test/flutter_test.dart';
import 'package:shadow_wifi/state/wifi_connect_controller.dart';
import 'package:shadow_wifi/data/services/wifi_connect_service.dart';
import 'package:shadow_wifi/data/services/system_channel.dart';
import 'package:shadow_wifi/data/models/security_type.dart';

void main() {
  WifiConnectController build() => WifiConnectController(
        service: WifiConnectService(SystemChannel.instance),
      );

  group('isWpa3', () {
    test('يحدد WPA3 من نوع الحماية', () {
      expect(WifiConnectService.isWpa3(SecurityType.wpa3), isTrue);
    });
  });

  group('WifiConnectController — منطق الحالة', () {
    test('setTarget يضبط الشبكة ويصفّر النتيجة', () {
      final controller = build();
      controller.setTarget('CafeWiFi', isWpa3: true);
      expect(controller.ssid, 'CafeWiFi');
      expect(controller.wpa3, isTrue);
      expect(controller.connected, isFalse);
      expect(controller.canConnect, isFalse);
    });

    test('canConnect يتطلب شبكة وكلمة مرور معاً', () {
      final controller = build();
      controller.setTarget('Net1');
      controller.setPassword('secret');
      expect(controller.canConnect, isTrue);
      controller.setPassword('   ');
      expect(controller.canConnect, isFalse);
    });

    test('effectiveCodes: يدوي واحد أو ملف كامل', () {
      final controller = build();
      expect(controller.effectiveCodes, isEmpty);
      controller.setPassword('111');
      expect(controller.effectiveCodes, ['111']);
    });

    test('canStartLoop يمنع الحلقة برمز يدوي واحد', () {
      final controller = build();
      controller.setTarget('Net1');
      controller.setPassword('111');
      // رمز واحد يدوياً = محاولة واحدة، لا داعي لحلقة
      expect(controller.canStartLoop, isFalse);
    });

    test('الإيقاف/الاستئناف/الإلغاء خارج التشغيل لا يغيّرون الحالة', () {
      final controller = build();
      controller.pause();
      expect(controller.paused, isFalse);
      controller.resume();
      expect(controller.running, isFalse);
      controller.cancel();
      expect(controller.running, isFalse);
    });

    test('resetIfIdle يصفّر كل شيء', () {
      final controller = build();
      controller.setTarget('Net1');
      controller.setPassword('xyz');
      controller.resetIfIdle();
      expect(controller.ssid, isEmpty);
      expect(controller.manualPassword, isEmpty);
      expect(controller.total, 0);
      expect(controller.sessionLogs, isEmpty);
    });

    test('progress صفر بلا رموز', () {
      final controller = build();
      expect(controller.progress, 0);
    });
  });
}
