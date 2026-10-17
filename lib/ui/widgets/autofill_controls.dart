import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// لوحة تقدم وأزرار حلقة التجربة التلقائية.
///
/// تُستخدم في تبويب «البوابة» وفي نافذة الشبكة بنفس الشكل.
class AutoFillControls extends StatelessWidget {
  const AutoFillControls({
    super.key,
    required this.running,
    required this.paused,
    required this.completed,
    required this.total,
    required this.successCount,
    this.currentCode,
    this.onStart,
    this.onPauseResume,
    this.onCancel,
    this.statusLabel,
  });

  /// هل الحلقة تعمل؟
  final bool running;

  /// هل الحلقة متوقفة مؤقتاً؟
  final bool paused;

  /// المحاولات المكتملة.
  final int completed;

  /// إجمالي الرموز.
  final int total;

  /// عدد المحاولات الناجحة.
  final int successCount;

  /// الرمز الحالي.
  final String? currentCode;

  /// بدء التشغيل.
  final VoidCallback? onStart;

  /// إيقاف مؤقت / استئناف.
  final VoidCallback? onPauseResume;

  /// إلغاء.
  final VoidCallback? onCancel;

  /// تسمية حالة بديلة تظهر مكان «متوقف».
  final String? statusLabel;

  @override
  Widget build(BuildContext context) {
    final String status = statusLabel ??
        (running ? (paused ? 'متوقف' : 'يعمل') : 'متوقف');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: total == 0 ? 0 : (completed / total).clamp(0.0, 1.0),
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            _Metric(label: 'المحاولات', value: '$completed / $total'),
            _Metric(label: 'الناجحة', value: '$successCount', color: AppColors.success),
            _Metric(
              label: 'الحالة',
              value: status,
              color: running && !paused ? AppColors.primary : AppColors.textSecondary,
            ),
          ],
        ),
        if (currentCode != null && currentCode!.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            'الرمز الحالي: $currentCode',
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
              fontFamily: 'monospace',
            ),
          ),
        ],
        const SizedBox(height: 14),
        Row(
          children: <Widget>[
            Expanded(
              child: FilledButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: const Text('بدء'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onPauseResume,
                icon: Icon(
                  paused ? Icons.play_circle_outline : Icons.pause_circle_outline,
                  size: 18,
                ),
                label: Text(paused ? 'استئناف' : 'إيقاف مؤقت'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onCancel,
                icon: const Icon(Icons.stop_circle_outlined, size: 18),
                label: const Text('إلغاء'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryLight,
                  side: BorderSide(color: AppColors.primary.withOpacity(0.5)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// مؤشر رقمي صغير.
class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: color ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
