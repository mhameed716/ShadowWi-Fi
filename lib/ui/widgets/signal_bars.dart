import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// مؤشر قوة الإشارة (أربعة أعمدة).
class SignalBars extends StatelessWidget {
  const SignalBars({
    super.key,
    required this.ratio,
    this.color = AppColors.primary,
    this.size = 18,
  });

  /// النسبة بين 0 و1.
  final double ratio;

  /// اللون.
  final Color color;

  /// الحجم الكلي.
  final double size;

  @override
  Widget build(BuildContext context) {
    const int bars = 4;
    final double barWidth = size / 6;
    final double gap = size / 12;
    final int active = (ratio * bars).ceil().clamp(0, bars).toInt();

    return SizedBox(
      width: barWidth * bars + gap * (bars - 1),
      height: size,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int index = 0; index < bars; index++)
            Padding(
              padding: EdgeInsets.only(left: index == 0 ? 0 : gap),
              child: Container(
                width: barWidth,
                height: size * (0.35 + 0.216 * index),
                decoration: BoxDecoration(
                  color: index < active ? color : AppColors.border,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
