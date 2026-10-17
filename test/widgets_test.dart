import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadow_wifi/core/theme/app_theme.dart';
import 'package:shadow_wifi/ui/widgets/section_card.dart';
import 'package:shadow_wifi/ui/widgets/signal_bars.dart';
import 'package:shadow_wifi/ui/widgets/status_chip.dart';

void main() {
  testWidgets('بطاقة القسم تعرض العنوان والمحتوى', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SectionCard(
            title: 'البوابة الافتراضية',
            subtitle: 'وصف',
            icon: Icons.router,
            child: Text('المحتوى'),
          ),
        ),
      ),
    );

    expect(find.text('البوابة الافتراضية'), findsOneWidget);
    expect(find.text('وصف'), findsOneWidget);
    expect(find.text('المحتوى'), findsOneWidget);
    expect(find.byIcon(Icons.router), findsOneWidget);
  });

  testWidgets('شارة الحالة تعرض النص واللون', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatusChip(
            label: 'متصل',
            color: AppColors.success,
          ),
        ),
      ),
    );

    expect(find.text('متصل'), findsOneWidget);
  });

  testWidgets('مؤشر الإشارة يرسم أربعة أعمدة', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SignalBars(ratio: 0.75),
        ),
      ),
    );

    final Finder container = find.descendant(
      of: find.byType(SignalBars),
      matching: find.byType(Container),
    );
    expect(container, findsNWidgets(4));
  });
}
