import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/attempt_log.dart';
import '../../../state/logs_controller.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/status_chip.dart';

/// تبويب «السجل»: سجل المحاولات السابقة مع المسح والتصدير.
class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    final LogsController controller = context.read<LogsController>();
    if (controller.logs.isEmpty) {
      controller.load();
    }
  }

  Future<void> _confirmClear() async {
    final LogsController controller = context.read<LogsController>();
    if (controller.logs.isEmpty) return;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('مسح السجل'),
        content: const Text(
          'سيتم حذف جميع المحاولات المسجّلة نهائياً. هل تريد المتابعة؟',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('مسح'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await controller.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('تم مسح السجل بالكامل')),
        );
    }
  }

  Future<void> _export() async {
    final LogsController controller = context.read<LogsController>();
    if (controller.logs.isEmpty) return;

    setState(() => _sharing = true);
    try {
      final String? path = await controller.export();
      if (path == null || !mounted) return;
      await Share.shareXFiles(
        <XFile>[XFile(path)],
        subject: 'سجل ShadowWi-Fi',
        text: 'سجل محاولات ShadowWi-Fi',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('تعذّر تصدير السجل: $e')),
        );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final LogsController controller = context.watch<LogsController>();

    if (controller.loading && controller.logs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (controller.logs.isEmpty) {
      return EmptyState(
        icon: Icons.receipt_long,
        title: 'السجل فارغ',
        message:
            'ستظهر هنا كل محاولات الدخول التي تجريها من تبويب «البوابة».',
        action: FilledButton.icon(
          onPressed: () => controller.load(),
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('تحديث'),
        ),
      );
    }

    return Column(
      children: <Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          color: AppColors.surface.withOpacity(0.6),
          child: Row(
            children: <Widget>[
              StatusChip(
                label: '${controller.logs.length} محاولة',
                color: AppColors.info,
                icon: Icons.list_alt,
                dense: true,
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _sharing ? null : _export,
                icon: _sharing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.ios_share, size: 16),
                label: const Text('تصدير'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  textStyle: const TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: controller.clearing ? null : _confirmClear,
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('مسح'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  foregroundColor: AppColors.primaryLight,
                  side: BorderSide(color: AppColors.primary.withOpacity(0.5)),
                  textStyle: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            itemCount: controller.logs.length,
            separatorBuilder: (BuildContext context, int index) =>
                const SizedBox(height: 10),
            itemBuilder: (BuildContext context, int index) {
              final AttemptLog log = controller.logs[index];
              return _LogTile(log: log);
            },
          ),
        ),
      ],
    );
  }
}

/// عنصر سجل واحد.
class _LogTile extends StatelessWidget {
  const _LogTile({required this.log});

  final AttemptLog log;

  @override
  Widget build(BuildContext context) {
    final Color color = log.success ? AppColors.success : AppColors.primary;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                log.success ? Icons.check_circle : Icons.cancel,
                color: color,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  log.success ? 'محاولة ناجحة' : 'محاولة فاشلة',
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                _formatDate(log.timestamp),
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              const Text(
                'الكلمة: ',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              Expanded(
                child: Text(
                  log.username.isEmpty ? '—' : log.username,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              if (log.username.isNotEmpty)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'نسخ الكلمة',
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: log.username),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('تم نسخ الكلمة'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy, size: 16),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            log.message,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: <Widget>[
              StatusChip(
                label: log.source.label,
                color: AppColors.info,
                dense: true,
              ),
              StatusChip(
                label: '${log.durationMs} ms',
                color: AppColors.textSecondary,
                dense: true,
              ),
              if (log.statusCode != null)
                StatusChip(
                  label: 'HTTP ${log.statusCode}',
                  color: AppColors.textSecondary,
                  dense: true,
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime value) {
    final String day = value.day.toString().padLeft(2, '0');
    final String month = value.month.toString().padLeft(2, '0');
    final String hour = value.hour.toString().padLeft(2, '0');
    final String minute = value.minute.toString().padLeft(2, '0');
    return '$day/$month $hour:$minute';
  }
}
