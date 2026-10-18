import 'package:flutter_test/flutter_test.dart';
import 'package:shadow_wifi/state/wifi_connect_controller.dart';
import 'package:shadow_wifi/data/services/wifi_connect_service.dart';
import 'package:shadow_wifi/data/services/code_file_service.dart';
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

  group('رسائل فشل الاقتران الحاسم', () {
    test('واي فاي مغلق', () {
      final message = WifiConnectService.specifierFailureMessage('wifi_off');
      expect(message, contains('الواي فاي مغلق'));
      expect(message, contains('فعّله'));
    });

    test('خدمة الموقع مغلقة', () {
      final message =
          WifiConnectService.specifierFailureMessage('location_off');
      expect(message, contains('الموقع'));
    });

    test('انتهاء المهلة', () {
      final message = WifiConnectService.specifierFailureMessage('timeout');
      expect(message, contains('المهلة'));
    });

    test('إلغاء نافذة اختيار جهاز يشرح ما حدث', () {
      final message = WifiConnectService.specifierFailureMessage('declined');
      expect(message, contains('اختيار جهاز'));
      expect(message, contains('أعد المحاولة'));
    });

    test('السبب المجهول يشرح نافذة تأكيد النظام', () {
      final message =
          WifiConnectService.specifierFailureMessage('unavailable');
      expect(message, contains('نافذة تأكيد'));
      expect(message, contains('كلمة المرور'));
    });

    test('needsSystemFix يميّز الأسباب النظامية', () {
      const wifiOff =
          SpecifierConnectResult(connected: false, reason: 'wifi_off');
      const locationOff =
          SpecifierConnectResult(connected: false, reason: 'location_off');
      const plain =
          SpecifierConnectResult(connected: false, reason: 'unavailable');
      expect(wifiOff.needsSystemFix, isTrue);
      expect(locationOff.needsSystemFix, isTrue);
      expect(plain.needsSystemFix, isFalse);
    });
  });

  group('كشف الفشل المبكر: ارتباط ثم انفصال', () {
    test('الارتباط يشمل ASSOCIATED — الإصلاح الجوهري', () {
      expect(WifiConnectService.isLinkState('ASSOCIATED'), isTrue);
      expect(WifiConnectService.isLinkState('FOUR_WAY_HANDSHAKE'), isTrue);
      expect(WifiConnectService.isLinkState('GROUP_HANDSHAKE'), isTrue);
      expect(WifiConnectService.isLinkState('COMPLETED'), isTrue);
      expect(WifiConnectService.isLinkState('SCANNING'), isFalse);
    });

    test('ارتباط ثم انفصال = كلمة خاطئة (دون شرط رؤية المصادقة)', () {
      expect(
        WifiConnectService.authRegressionObserved(
          state: 'SCANNING',
          sawLink: true,
        ),
        isTrue,
      );
      expect(
        WifiConnectService.authRegressionObserved(
          state: 'DISCONNECTED',
          sawLink: true,
        ),
        isTrue,
      );
      expect(
        WifiConnectService.authRegressionObserved(
          state: 'DORMANT',
          sawLink: true,
        ),
        isTrue,
      );
    });

    test('بلا ارتباط سابق لا يُعتبر الانفصال دليلاً', () {
      expect(
        WifiConnectService.authRegressionObserved(
          state: 'SCANNING',
          sawLink: false,
        ),
        isFalse,
      );
    });

    test('حالات الارتباط نفسها ليست انفصالاً', () {
      expect(
        WifiConnectService.authRegressionObserved(
          state: 'FOUR_WAY_HANDSHAKE',
          sawLink: true,
        ),
        isFalse,
      );
      expect(
        WifiConnectService.authRegressionObserved(
          state: 'COMPLETED',
          sawLink: true,
        ),
        isFalse,
      );
    });
  });

  group('فلتر الكلمات المكررة', () {
    test('يعدّ المكرر بالضبط ويحذفه بإبقاء نسخة واحدة', () {
      final controller = build();
      controller.selectedFile = const CodeFile(
        path: '/tmp/t.txt',
        name: 't.txt',
        codes: <String>['111', '222', '111', ' 111 ', '333', '', '   '],
      );
      expect(controller.duplicateCount, 2);
      controller.dedupeCodes();
      expect(controller.selectedFile!.codes, <String>['111', '222', '333']);
      expect(controller.duplicateCount, 0);
    });

    test('الكلمات المختلفة حروفاً تبقى كلها', () {
      final controller = build();
      controller.selectedFile = const CodeFile(
        path: '/tmp/t.txt',
        name: 't.txt',
        codes: <String>['12345678', '12345679', 'aA1', 'aa1'],
      );
      expect(controller.duplicateCount, 0);
      controller.dedupeCodes();
      expect(controller.selectedFile!.codes.length, 4);
    });

    test('بلا ملف: العدد صفر والحذف آمن', () {
      final controller = build();
      expect(controller.duplicateCount, 0);
      controller.dedupeCodes();
      expect(controller.selectedFile, isNull);
    });
  });
}
