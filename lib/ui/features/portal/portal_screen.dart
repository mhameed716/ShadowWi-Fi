import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/attempt_log.dart';
import '../../../data/models/gateway_info.dart';
import '../../../data/models/login_outcome.dart';
import '../../../state/portal_controller.dart';
import '../../widgets/section_card.dart';
import '../../widgets/status_chip.dart';

/// تبويب «البوابة»: اكتشاف البوابة، الدخول اليدوي، والتشغيل التلقائي.
class PortalScreen extends StatefulWidget {
  const PortalScreen({super.key});

  @override
  State<PortalScreen> createState() => _PortalScreenState();
}

class _PortalScreenState extends State<PortalScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _destinationController =
      TextEditingController(text: AppConstants.defaultDestination);

  /// مرجع محفوظ للمتحكم لتفادي قراءة السياق أثناء الإغلاق.
  PortalController? _controller;

  @override
  void initState() {
    super.initState();
    final PortalController controller = context.read<PortalController>();
    _controller = controller;
    _usernameController.text = controller.username;
    _passwordController.text = controller.password;
    _destinationController.text = controller.destination;
    controller.addListener(_handleControllerChange);
  }

  @override
  void dispose() {
    _controller?.removeListener(_handleControllerChange);
    _controller = null;
    _usernameController.dispose();
    _passwordController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  void _handleControllerChange() {
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
    final PortalController controller = context.watch<PortalController>();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: <Widget>[
        _GatewayCard(controller: controller),
        const SizedBox(height: 14),
        _ManualLoginCard(
          controller: controller,
          usernameController: _usernameController,
          passwordController: _passwordController,
          destinationController: _destinationController,
        ),
        const SizedBox(height: 14),
        _AutoFillCard(controller: controller),
        const SizedBox(height: 14),
        _SessionLogCard(controller: controller),
      ],
    );
  }
}

/// بطاقة اكتشاف البوابة الافتراضية.
class _GatewayCard extends StatelessWidget {
  const _GatewayCard({required this.controller});

  final PortalController controller;

  @override
  Widget build(BuildContext context) {
    final GatewayInfo? gateway = controller.gateway;

    return SectionCard(
      title: 'البوابة الافتراضية',
      subtitle: 'الجهاز الذي يمرّ عبره الإنترنت قبل المصادقة',
      icon: Icons.router,
      trailing: controller.detecting
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : IconButton(
              tooltip: 'إعادة الاكتشاف',
              onPressed: controller.detectGateway,
              icon: const Icon(Icons.refresh, size: 20),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (gateway == null)
            const Text(
              'لم يتم اكتشاف البوابة بعد.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            )
          else ...<Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    gateway.baseUrl,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                StatusChip(
                  label: gateway.sourceLabel,
                  color: gateway.responded ? AppColors.success : AppColors.warning,
                  dense: true,
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (gateway.pageTitle != null)
              Text(
                'عنوان الصفحة: ${gateway.pageTitle}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            if (gateway.statusCode != null)
              Text(
                'رمز الاستجابة: ${gateway.statusCode}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: controller.detecting ? null : controller.detectGateway,
              icon: const Icon(Icons.search, size: 18),
              label: const Text('اكتشاف البوابة'),
            ),
          ],
        ],
      ),
    );
  }
}

/// بطاقة الدخول اليدوي.
class _ManualLoginCard extends StatelessWidget {
  const _ManualLoginCard({
    required this.controller,
    required this.usernameController,
    required this.passwordController,
    required this.destinationController,
  });

  final PortalController controller;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final TextEditingController destinationController;

  @override
  Widget build(BuildContext context) {
    final LoginOutcome? outcome = controller.lastOutcome;

    return SectionCard(
      title: 'الدخول اليدوي',
      subtitle: 'أدخل بيانات الجهاز أو الكرت للاتصال بالبوابة',
      icon: Icons.badge_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            controller: usernameController,
            onChanged: controller.setUsername,
            textInputAction: TextInputAction.next,
            keyboardType: TextInputType.text,
            decoration: const InputDecoration(
              labelText: 'اسم المستخدم أو رقم الجهاز',
              hintText: 'مثال: 12345678',
              prefixIcon: Icon(Icons.person_outline, size: 20),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: passwordController,
            onChanged: controller.setPassword,
            obscureText: true,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'كلمة المرور أو الرمز',
              hintText: 'أدخل الرمز',
              prefixIcon: Icon(Icons.key_outlined, size: 20),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: destinationController,
            onChanged: controller.setDestination,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'وجهة الاتصال',
              hintText: AppConstants.defaultDestination,
              prefixIcon: Icon(Icons.public, size: 20),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed:
                controller.submitting ? null : () => controller.submitManual(),
            icon: controller.submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.login, size: 18),
            label: Text(controller.submitting ? 'جارٍ الإرسال...' : 'تسجيل الدخول'),
          ),
          if (outcome != null) ...<Widget>[
            const SizedBox(height: 14),
            _OutcomeBox(outcome: outcome),
          ],
        ],
      ),
    );
  }
}

/// عرض نتيجة المحاولة.
class _OutcomeBox extends StatelessWidget {
  const _OutcomeBox({required this.outcome});

  final LoginOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final Color color =
        outcome.success ? AppColors.success : AppColors.primary;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                outcome.success ? Icons.check_circle : Icons.cancel,
                color: color,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  outcome.success ? 'نجحت المحاولة' : 'فشلت المحاولة',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              if (outcome.statusCode != null)
                Text(
                  'HTTP ${outcome.statusCode}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            outcome.message,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// بطاقة التشغيل التلقائي من ملف الرموز.
class _AutoFillCard extends StatelessWidget {
  const _AutoFillCard({required this.controller});

  final PortalController controller;

  @override
  Widget build(BuildContext context) {
    final int total = controller.total;
    final int completed = controller.completed;
    final int successCount =
        controller.sessionLogs.where((AttemptLog e) => e.success).length;

    return SectionCard(
      title: 'التشغيل التلقائي',
      subtitle: 'قراءة الرموز من ملف TXT وتجربتها تباعاً في الخلفية',
      icon: Icons.auto_awesome_motion,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          OutlinedButton.icon(
            onPressed:
                controller.running ? null : () => controller.pickFile(),
            icon: controller.pickingFile
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.attach_file, size: 18),
            label: Text(
              controller.selectedFile == null
                  ? 'اختيار ملف TXT'
                  : 'تغيير الملف (${controller.selectedFile!.count} رمز)',
            ),
          ),
          if (controller.selectedFile != null) ...<Widget>[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.inputFill,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.description_outlined,
                      size: 18, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      controller.selectedFile!.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (!controller.running)
                    IconButton(
                      tooltip: 'إزالة الملف',
                      onPressed: controller.clearFile,
                      icon: const Icon(Icons.close, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: controller.useCodeAsUsername,
            onChanged: controller.running ? null : controller.setUseCodeAsUsername,
            title: const Text(
              'استخدام الرمز كاسم مستخدم',
              style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
            ),
            subtitle: const Text(
              'عند التفعيل يُجرَّب كل رمز باسم المستخدم مع كلمة المرور المدخلة',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 8),
          if (controller.running || total > 0) ...<Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : controller.progress,
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                _Metric(
                  label: 'المحاولات',
                  value: '$completed / $total',
                  color: AppColors.textPrimary,
                ),
                _Metric(
                  label: 'الناجحة',
                  value: '$successCount',
                  color: AppColors.success,
                ),
                _Metric(
                  label: 'الحالة',
                  value: controller.running
                      ? (controller.paused ? 'متوقف' : 'يعمل')
                      : 'متوقف',
                  color: controller.running && !controller.paused
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
              ],
            ),
            if (controller.currentCode != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'الرمز الحالي: ${controller.currentCode}',
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
                    onPressed: controller.running
                        ? null
                        : () => controller.startAutoFill(),
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('بدء'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: !controller.running
                        ? null
                        : (controller.paused
                            ? controller.resumeAutoFill
                            : controller.pauseAutoFill),
                    icon: Icon(
                      controller.paused
                          ? Icons.play_circle_outline
                          : Icons.pause_circle_outline,
                      size: 18,
                    ),
                    label: Text(controller.paused ? 'استئناف' : 'إيقاف مؤقت'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        controller.running ? () => controller.cancelAutoFill() : null,
                    icon: const Icon(Icons.stop_circle_outlined, size: 18),
                    label: const Text('إلغاء'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryLight,
                      side: BorderSide(
                        color: AppColors.primary.withOpacity(0.5),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...<Widget>[
            const SizedBox(height: 4),
            const Text(
              'اختر ملف TXT لعرض خيارات التشغيل.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// مؤشر رقمي صغير.
class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

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
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// بطاقة محاولات الجلسة.
class _SessionLogCard extends StatelessWidget {
  const _SessionLogCard({required this.controller});

  final PortalController controller;

  @override
  Widget build(BuildContext context) {
    final List<AttemptLog> logs = controller.sessionLogs.take(6).toList();

    return SectionCard(
      title: 'محاولات الجلسة',
      subtitle: 'آخر النتائج المباشرة',
      icon: Icons.list_alt,
      child: logs.isEmpty
          ? const Text(
              'لا توجد محاولات بعد.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            )
          : Column(
              children: <Widget>[
                for (final AttemptLog log in logs)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          log.success
                              ? Icons.check_circle_outline
                              : Icons.remove_circle_outline,
                          size: 16,
                          color: log.success
                              ? AppColors.success
                              : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            log.username,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textPrimary,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        Text(
                          '${log.durationMs}ms',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
