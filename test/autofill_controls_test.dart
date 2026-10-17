import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadow_wifi/ui/widgets/autofill_controls.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('الحالة المتوقفة تعرض الأرقام وزر البدء', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        AutoFillControls(
          running: false,
          paused: false,
          completed: 3,
          total: 10,
          successCount: 1,
          currentCode: '555',
          onStart: () {},
        ),
      ),
    );

    expect(find.text('3 / 10'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('متوقف'), findsOneWidget);
    expect(find.text('الرمز الحالي: 555'), findsOneWidget);
    expect(find.text('بدء'), findsOneWidget);
    expect(find.text('إيقاف مؤقت'), findsOneWidget);
    expect(find.text('إلغاء'), findsOneWidget);
  });

  testWidgets('الإيقاف المؤقت يبدّل الزر إلى استئناف', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const AutoFillControls(
          running: true,
          paused: true,
          completed: 0,
          total: 5,
          successCount: 0,
        ),
      ),
    );

    expect(find.text('استئناف'), findsOneWidget);
    expect(find.text('0 / 5'), findsOneWidget);
  });

  testWidgets('أثناء التشغيل يكون زر البدء معطلاً', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const AutoFillControls(
          running: true,
          paused: false,
          completed: 1,
          total: 5,
          successCount: 0,
        ),
      ),
    );

    // ملاحظة: find.widgetWithText(FilledButton, ...) يفشل هنا لأن
    // FilledButton.icon ينشئ _FilledButtonWithIcon (صفاً فرعياً) والفاحص
    // يطابق النوع الحرفي فقط — لذا نستخدم byWidgetPredicate مع `is`.
    final Finder startButton = find.ancestor(
      of: find.text('بدء'),
      matching: find.byWidgetPredicate((Widget widget) => widget is FilledButton),
    );
    expect(startButton, findsOneWidget);
    final FilledButton button = tester.widget<FilledButton>(startButton);
    expect(button.onPressed, isNull);
  });
}
