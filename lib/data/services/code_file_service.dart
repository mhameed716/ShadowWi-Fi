import 'dart:io';

import 'package:file_picker/file_picker.dart';

/// ملف رموز جاهز للتشغيل التلقائي.
class CodeFile {
  const CodeFile({
    required this.path,
    required this.name,
    required this.codes,
  });

  /// مسار الملف على الجهاز.
  final String path;

  /// اسم الملف.
  final String name;

  /// الرموز المقروءة من الملف.
  final List<String> codes;

  /// عدد الرموز.
  int get count => codes.length;
}

/// خدمة اختيار ملف TXT وقراءة الرموز منه.
class CodeFileService {
  const CodeFileService();

  /// يفتح منتقي الملفات ويعيد الملف المختار بعد تحليله.
  Future<CodeFile?> pickTxtFile() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['txt'],
      withData: false,
    );

    if (result == null || result.files.isEmpty) return null;

    final PlatformFile file = result.files.first;
    final String? path = file.path;
    if (path == null || path.isEmpty) {
      throw const FormatException('تعذّر الوصول إلى مسار الملف المختار');
    }

    final String content = await File(path).readAsString();
    final List<String> codes = parseCodes(content);

    return CodeFile(
      path: path,
      name: file.name,
      codes: codes,
    );
  }

  /// يحوّل محتوى الملف إلى قائمة رموز.
  ///
  /// يتجاهل الأسطر الفارغة والأسطر التي تبدأ بعلامة `#` (تعليقات).
  static List<String> parseCodes(String content) {
    final List<String> codes = <String>[];
    for (final String rawLine in content.split(RegExp(r'\r?\n'))) {
      final String line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#')) continue;
      if (line.length > 128) continue;
      codes.add(line);
    }
    return codes;
  }
}
