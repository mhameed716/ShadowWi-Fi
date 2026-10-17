import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/diagnostics_snapshot.dart';
import '../../../state/diagnostics_controller.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/info_row.dart';
import '../../widgets/section_card.dart';
import '../../widgets/status_chip.dart';

/// تبويب «التشخيص»: تفاصيل الاتصال ونتائج الفحص.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  /// مرجع محفوظ للمتحكم لتفادي قراءة السياق أثناء الإغلاق.
  DiagnosticsController? _controller;

  @override
  void initState() {
    super.initState();
    final DiagnosticsController controller = context.read<DiagnosticsController>();
    _controller = controller;
    controller.addListener(_handleChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (controller.snapshot == null) {
        controller.run();
      }
    });
  }

  @override
  void dispose() {
    _controller?.removeListener(_handleChange);
    _controller = null;
    super.dispose();
  }

  void _handleChange() {
    if (!mounted) return;
    final String? error = _controller?.takeError();
    if (error == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: <Widget>[
              const Icon(Icons.error_outline, color: AppColors.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(error)),
            ],
          ),
          duration: const Duration(seconds: 4),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final DiagnosticsController controller =
        context.watch<DiagnosticsController>();
    final DiagnosticsSnapshot? snapshot = controller.snapshot;

    if (snapshot == null && controller.running) {
      return const Center(child: CircularProgressIndicator());
    }

    if (snapshot == null) {
      return EmptyState(
        icon: Icons.troubleshoot,
        title: 'لا توجد نتائج تشخيص',
        message: 'اضغط «تشغيل الفحص» لجمع تفاصيل الاتصال الحالية.',
        action: FilledButton.icon(
          onPressed: () => controller.run(),
          icon: const Icon(Icons.play_arrow, size: 18),
          label: const Text('تشغيل الفحص'),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => controller.run(),
      color: AppColors.primary,
      backgroundColor: AppColors.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: <Widget>[
          SectionCard(
            title: 'حالة الاتصال',
            subtitle: 'آخر فحص: ${_formatTime(snapshot.takenAt)}',
            icon: Icons.network_check,
            trailing: controller.running
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    tooltip: 'تحديث',
                    onPressed: () => controller.run(),
                    icon: const Icon(Icons.refresh, size: 20),
                  ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    StatusChip(
                      label: snapshot.hasInternet
                          ? 'متصل بالإنترنت'
                          : 'غير متصل بالإنترنت',
                      color: snapshot.hasInternet
                          ? AppColors.success
                          : AppColors.primary,
                      icon: snapshot.hasInternet
                          ? Icons.check_circle
                          : Icons.cloud_off,
                    ),
                    const SizedBox(width: 8),
                    StatusChip(
                      label: snapshot.connectionLabel,
                      color: AppColors.info,
                      icon: Icons.settings_ethernet,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                InfoRow(
                  label: 'زمن استجابة الإنترنت',
                  value: snapshot.internetLatencyMs == null
                      ? '-'
                      : '${snapshot.internetLatencyMs} ms',
                  icon: Icons.speed,
                ),
                InfoRow(
                  label: 'رمز فحص الإنترنت',
                  value: snapshot.internetStatusCode?.toString() ?? '-',
                  icon: Icons.tag,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'الجهاز والشبكة',
            icon: Icons.devices,
            child: Column(
              children: <Widget>[
                InfoRow(
                  label: 'البوابة الافتراضية',
                  value: snapshot.gateway ?? 'غير معروفة',
                  icon: Icons.router,
                  monospace: true,
                ),
                InfoRow(
                  label: 'عناوين الجهاز',
                  value: snapshot.deviceAddresses.isEmpty
                      ? 'غير متاحة'
                      : snapshot.deviceAddresses.join('\n'),
                  icon: Icons.lan_outlined,
                  monospace: true,
                ),
                InfoRow(
                  label: 'خوادم DNS',
                  value: snapshot.dnsServers.isEmpty
                      ? 'غير متاحة'
                      : snapshot.dnsServers.join('\n'),
                  icon: Icons.dns_outlined,
                  monospace: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SectionCard(
            title: 'صفحة البوابة',
            icon: Icons.web_asset,
            child: Column(
              children: <Widget>[
                InfoRow(
                  label: 'عنوان الصفحة',
                  value: snapshot.portalTitle ?? 'لم يتم العثور على عنوان',
                  icon: Icons.title,
                ),
                InfoRow(
                  label: 'رمز الاستجابة',
                  value: snapshot.portalStatusCode?.toString() ?? '-',
                  icon: Icons.tag,
                ),
                InfoRow(
                  label: 'الرابط',
                  value: snapshot.portalUrl ?? '-',
                  icon: Icons.link,
                  monospace: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatTime(DateTime value) {
    final String hour = value.hour.toString().padLeft(2, '0');
    final String minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
