import 'package:flutter_test/flutter_test.dart';
import 'package:shadow_wifi/data/models/attempt_log.dart';

void main() {
  group('ترميز سجل المحاولات', () {
    final AttemptLog log = AttemptLog(
      id: '1',
      timestamp: DateTime.utc(2024, 5, 1, 12),
      gateway: 'http://192.168.1.1',
      username: 'user01',
      success: true,
      message: 'تم الاتصال بالإنترنت بنجاح',
      durationMs: 120,
      source: AttemptSource.manual,
      statusCode: 302,
    );

    test('التحويل إلى JSON ثم الاستعادة يحافظان على القيم', () {
      final List<AttemptLog> restored = AttemptLogCodec.decode(
        AttemptLogCodec.encode(<AttemptLog>[log]),
      );
      expect(restored, hasLength(1));
      expect(restored.first.id, log.id);
      expect(restored.first.gateway, log.gateway);
      expect(restored.first.username, log.username);
      expect(restored.first.success, isTrue);
      expect(restored.first.durationMs, 120);
      expect(restored.first.statusCode, 302);
      expect(restored.first.source, AttemptSource.manual);
    });

    test('النص الفارغ يعطي قائمة فارغة', () {
      expect(AttemptLogCodec.decode(''), isEmpty);
      expect(AttemptLogCodec.decode('   '), isEmpty);
    });

    test('نص غير صالح لا يرمي استثناء', () {
      expect(AttemptLogCodec.decode('ليس JSON'), isEmpty);
    });

    test('التصدير النصي يحتوي على النتيجة والرمز', () {
      final String text = AttemptLogCodec.exportText(<AttemptLog>[log]);
      expect(text, contains('ShadowWi-Fi'));
      expect(text, contains('نجاح'));
      expect(text, contains('user01'));
      expect(text, contains('HTTP 302'));
    });
  });
}
