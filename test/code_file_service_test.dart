import 'package:flutter_test/flutter_test.dart';
import 'package:shadow_wifi/data/services/code_file_service.dart';

void main() {
  group('تحليل ملف الرموز', () {
    test('يتجاهل الأسطر الفارغة والتعليقات', () {
      const String content = '''
# تعليقات
12345

67890
   00011   
''';
      final List<String> codes = CodeFileService.parseCodes(content);
      expect(codes, <String>['12345', '67890', '00011']);
    });

    test('يتعامل مع نهايات الأسطر CRLF', () {
      const String content = '111\r\n222\r\n';
      expect(
        CodeFileService.parseCodes(content),
        <String>['111', '222'],
      );
    });

    test('يتجاهل الأسطر الطويلة جداً', () {
      final String long = 'x' * 200;
      final List<String> codes = CodeFileService.parseCodes('$long\n42');
      expect(codes, <String>['42']);
    });

    test('ملف فارغ يعطي قائمة فارغة', () {
      expect(CodeFileService.parseCodes(''), isEmpty);
    });
  });
}
