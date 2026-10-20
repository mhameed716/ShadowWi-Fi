import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shadow_wifi/data/services/captive_portal_detector.dart';
import 'package:shadow_wifi/data/services/system_channel.dart';
import 'package:shadow_wifi/data/services/state_store.dart';
import 'package:shadow_wifi/state/auto_portal_controller.dart';

void main() {
  group('تنسيق وتحليل الواجهة التلقائية', () {
    test('formatCode يضمن عشر خانات بأصفار يسارية', () {
      expect(AutoPortalController.formatCode(1), '0000000001');
      expect(AutoPortalController.formatCode(123456), '0000123456');
      expect(AutoPortalController.formatCode(9999999999), '9999999999');
    });

    test('parseStart: فارغ أو غير صالح ⇒ 1', () {
      expect(AutoPortalController.parseStart(''), 1);
      expect(AutoPortalController.parseStart('   '), 1);
      expect(AutoPortalController.parseStart('abc'), 1);
      expect(AutoPortalController.parseStart('0'), 1);
      expect(AutoPortalController.parseStart('-5'), 1);
      expect(AutoPortalController.parseStart('42'), 42);
      expect(AutoPortalController.parseStart(' 0000000007 '), 7);
    });

    test('clampDelay يقيّد التأخير بين 500 و1000', () {
      expect(AutoPortalController.clampDelay(499), 500);
      expect(AutoPortalController.clampDelay(500), 500);
      expect(AutoPortalController.clampDelay(750), 750);
      expect(AutoPortalController.clampDelay(1000), 1000);
      expect(AutoPortalController.clampDelay(2000), 1000);
    });
  });

  group('الحفظ والاستعادة', () {
    test('StateStore يكتب ويقرأ حالة كاملة (مجلد مؤقت)', () async {
      final Directory temp = await Directory.systemTemp.createTemp('ap_test');
      try {
        final StateStore store = StateStore(directory: temp);
        final DateTime time = DateTime(2026, 1, 2, 3, 4, 5);
        await store.save(AutoPortalState(
          lastNumber: 123456,
          portalUrl: 'http://10.0.0.1/login',
          foundCodes: <FoundCode>[FoundCode(code: '0000000042', discoveredAt: time)],
        ));
        final AutoPortalState loaded = await store.load();
        expect(loaded.lastNumber, 123456);
        expect(loaded.portalUrl, 'http://10.0.0.1/login');
        expect(loaded.foundCodes.length, 1);
        expect(loaded.foundCodes.first.code, '0000000042');
        expect(loaded.foundCodes.first.discoveredAt, time);
      } finally {
        await temp.delete(recursive: true);
      }
    });

    test('قراءة بلا ملف سابق تعيد حالة فارغة', () async {
      final Directory temp = await Directory.systemTemp.createTemp('ap_test2');
      try {
        final AutoPortalState state =
            await StateStore(directory: temp).load();
        expect(state.lastNumber, 0);
        expect(state.foundCodes, isEmpty);
      } finally {
        await temp.delete(recursive: true);
      }
    });
  });

  group('محرّك المحاولات (حقيقي بلا شبكة — دالة محاولة مزيفة)', () {
    test('توقف ذكي عند أول رمز صحيح + استئناف يتجاوزه', () async {
      final Directory temp = await Directory.systemTemp.createTemp('ap_test3');
      final StateStore store = StateStore(directory: temp);
      final AutoPortalController controller = AutoPortalController(
        detector: CaptivePortalDetector(SystemChannel.instance),
        store: store,
        attemptFn: (String url, String code) async => code == '0000000003',
        delayPickFn: () => 500,
      );
      controller.setPortalUrl('http://portal.test/login');
      await controller.start();

      // انتظار التوقف الذكي عند الرمز الثالث.
      final DateTime deadline = DateTime.now().add(const Duration(seconds: 20));
      while (!controller.smartPaused && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(controller.smartPaused, isTrue);
      expect(controller.attempts, 3);
      expect(controller.lastFound!.code, '0000000003');
      expect(controller.foundCodes.first.code, '0000000003');

      // الحفظ التلقائي: آخر رقم = الرمز المكتشف.
      final AutoPortalState saved = await store.load();
      expect(saved.lastNumber, 3);

      // الاستئناف: يتجاوز الرمز المكتشف ويواصل البحث.
      controller.resumeEngine();
      await Future<void>.delayed(const Duration(milliseconds: 700));
      await controller.stop();
      expect(controller.currentNumber, greaterThan(3));
      expect(controller.attempts, greaterThan(3));
      await temp.delete(recursive: true);
    });

    test('الإيقاف المؤقت يوقف المحاولات والاستئناف يعيدها', () async {
      final Directory temp = await Directory.systemTemp.createTemp('ap_test4');
      final AutoPortalController controller = AutoPortalController(
        detector: CaptivePortalDetector(SystemChannel.instance),
        store: StateStore(directory: temp),
        attemptFn: (String url, String code) async => false,
        delayPickFn: () => 500,
      );
      controller.setPortalUrl('http://portal.test/x');
      await controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 800));
      controller.pause();
      final int frozen = controller.attempts;
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(controller.attempts, frozen);
      controller.resumeEngine();
      await Future<void>.delayed(const Duration(milliseconds: 800));
      await controller.stop();
      expect(controller.attempts, greaterThan(frozen));
      await temp.delete(recursive: true);
    });

    test('إعادة الضبط تبدأ من رقم البداية المكتوب', () async {
      final Directory temp = await Directory.systemTemp.createTemp('ap_test5');
      final AutoPortalController controller = AutoPortalController(
        detector: CaptivePortalDetector(SystemChannel.instance),
        store: StateStore(directory: temp),
        attemptFn: (String url, String code) async => false,
      );
      controller.setStartInput('777');
      await controller.reset();
      expect(controller.currentNumber, 777);
      expect(AutoPortalController.formatCode(controller.currentNumber),
          '0000000777');
      await temp.delete(recursive: true);
    });

    test('التجربة اليدوية: نجاح يضيف للقائمة ويسجل كمصدر يدوي', () async {
      final Directory temp = await Directory.systemTemp.createTemp('ap_test7');
      final AutoPortalController controller = AutoPortalController(
        detector: CaptivePortalDetector(SystemChannel.instance),
        store: StateStore(directory: temp),
        attemptFn: (String url, String code) async => code == 'test123',
      );
      controller.setPortalUrl('http://portal.test/m');
      controller.setManualCode(' test123 ');
      expect(controller.manualTesting, isFalse);
      await controller.tryManualCode();
      expect(controller.manualSuccess, isTrue);
      expect(controller.manualResult, contains('صحيح'));
      expect(controller.foundCodes.first.code, 'test123');
      expect(controller.lastFound!.code, 'test123');
      // عدّاد التوليد التلقائي لم يُمَس.
      expect(controller.currentNumber, 1);
      await temp.delete(recursive: true);
    });

    test('التجربة اليدوية: فشل يعرض رسالة دون إضافة', () async {
      final Directory temp = await Directory.systemTemp.createTemp('ap_test8');
      final AutoPortalController controller = AutoPortalController(
        detector: CaptivePortalDetector(SystemChannel.instance),
        store: StateStore(directory: temp),
        attemptFn: (String url, String code) async => false,
      );
      controller.setPortalUrl('http://portal.test/m');
      controller.setManualCode('wrong');
      await controller.tryManualCode();
      expect(controller.manualSuccess, isFalse);
      expect(controller.manualResult, contains('غير صحيح'));
      expect(controller.foundCodes, isEmpty);
      await temp.delete(recursive: true);
    });

    test('التجربة اليدوية: حواجز الرمز الفارغ والرابط الغائب', () async {
      final Directory temp = await Directory.systemTemp.createTemp('ap_test9');
      final AutoPortalController controller = AutoPortalController(
        detector: CaptivePortalDetector(SystemChannel.instance),
        store: StateStore(directory: temp),
        attemptFn: (String url, String code) async => true,
      );
      await controller.tryManualCode();
      expect(controller.manualResult, contains('أدخل رمزاً'));
      controller.setManualCode('x');
      await controller.tryManualCode();
      expect(controller.manualResult, contains('اكشف البوابة'));
      await temp.delete(recursive: true);
    });

    test('الكشف المُحقن يملأ الرابط ويوسم الاكتشاف', () async {
      final Directory temp = await Directory.systemTemp.createTemp('ap_test6');
      final AutoPortalController controller = AutoPortalController(
        detector: CaptivePortalDetector(SystemChannel.instance),
        store: StateStore(directory: temp),
        detectFn: () async => const CaptivePortalInfo(
          detected: true,
          validated: false,
          portalUrl: 'http://gw.test/login',
          method: 'تحويل HTTP مُلتقط',
        ),
        attemptFn: (String url, String code) async => false,
      );
      await controller.detectPortal();
      expect(controller.portalDetected, isTrue);
      expect(controller.portalUrl, 'http://gw.test/login');
      await temp.delete(recursive: true);
    });
  });
}
