import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/attempt_log.dart';
import '../../../data/models/gateway_info.dart';
import '../../../data/models/security_type.dart';
import '../../../data/models/wifi_network_item.dart';
import '../../../state/network_attempts_controller.dart';
import '../../../state/networks_controller.dart';
import '../../../state/portal_controller.dart';
import '../../widgets/autofill_controls.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/section_card.dart';
import '../../widgets/signal_bars.dart';
import '../../widgets/status_chip.dart';

/// تبويب «الشبكات»: شبكات الواي فاي القريبة مع سحب للتحديث.
///
/// الضغط على أي شبكة آمنة يفتح نافذة إدخال رمز/كلمة مرور لتجربتها
/// تلقائياً على بوابة الشبكة (داخل Isolate) بدون اسم مستخدم.
class NetworksScreen extends StatefulWidget {
  const NetworksScreen({super.key});

  @override
  State<NetworksScreen> createState() => _NetworksScreenState();
}

class _NetworksScreenState extends State<NetworksScreen>
    with WidgetsBindingObserver {
  /// مراجع محفوظة للمتحكمات لتفادي قراءة السياق أثناء الإغلاق.
  NetworksController? _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final NetworksController controller = context.read<NetworksController>();
    _controller = controller;
    controller.addListener(_handleChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.refreshPermissionState();
      if (controller.networks.isEmpty && !controller.scanning) {
        controller.scan();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.removeListener(_handleChange);
    _controller = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // عند العودة من إعدادات النظام نعيد قراءة حالة الإذن فوراً.
    if (state == AppLifecycleState.resumed) {
      _controller?.refreshPermissionState();
    }
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

  Future<void> _openNetworkSheet(WifiNetworkItem network) async {
    final NetworkAttemptsController attempts =
        context.read<NetworkAttemptsController>();
    final GatewayInfo? gateway = context.read<PortalController>().gateway;

    final bool accepted =
        attempts.setTarget(network, gateway?.baseUrl ?? '');
    if (!accepted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(attempts.error ?? '')));
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) => ChangeNotifierProvider<
          NetworkAttemptsController>.value(
        value: attempts,
        child: const _NetworkSheet(),
      ),
    ).whenComplete(attempts.resetIfIdle);
  }

  @override
  Widget build(BuildContext context) {
    final NetworksController controller = context.watch<NetworksController>();
    final NetworkAttemptsController attempts =
        context.watch<NetworkAttemptsController>();

    return Stack(
      children: <Widget>[
        RefreshIndicator(
          onRefresh: controller.scan,
          color: AppColors.primary,
          backgroundColor: AppColors.surface,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: <Widget>[
              const _PermissionBanner(),
              if (controller.permission !=
                  LocationPermissionState.permanentlyDenied)
                const SizedBox(height: 12),
              if (controller.scanning && controller.networks.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (controller.networks.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: EmptyState(
                    icon: Icons.wifi_tethering,
                    title: 'لا توجد شبكات',
                    message:
                        'اسحب للأسفل لإعادة الفحص. إن استمرت المشكلة تأكد من '
                        'تفعيل الواي فاي وخدمة الموقع في الجهاز ثم أعد المحاولة.',
                    action: FilledButton.icon(
                      onPressed: controller.scan,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('إعادة الفحص'),
                    ),
                  ),
                )
              else ...<Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      'تم العثور على ${controller.networks.length} شبكة — '
                      'اضغط على أي شبكة آمنة لإدخال الرمز',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    if (controller.scanning)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                for (final WifiNetworkItem network in controller.networks)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _NetworkTile(
                      network: network,
                      onTap: network.security.isSecure
                          ? () => _openNetworkSheet(network)
                          : null,
                    ),
                  ),
              ],
            ],
          ),
        ),
        // شريط حالة العملية الجارية فوق القائمة.
        if (attempts.running ||
            (attempts.target != null && attempts.total > 0))
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: _RunningBanner(
              attempts: attempts,
              onOpen: () => _openNetworkSheet(attempts.target!),
            ),
          ),
      ],
    );
  }
}

/// لافتة أذونات الموقع.
class _PermissionBanner extends StatelessWidget {
  const _PermissionBanner();

  @override
  Widget build(BuildContext context) {
    final NetworksController controller = context.watch<NetworksController>();
    if (controller.permission == LocationPermissionState.granted) {
      return const SizedBox.shrink();
    }

    final bool permanently =
        controller.permission == LocationPermissionState.permanentlyDenied;

    return SectionCard(
      title: permanently ? 'الإذن ممنوع نهائياً' : 'إذن الموقع مطلوب',
      subtitle: permanently
          ? 'فعّل إذن الوصول إلى الموقع من إعدادات التطبيق ثم أعد الفحص'
          : 'يحتاج فحص الشبكات القريبة إلى إذن الوصول إلى الموقع على أندرويد',
      icon: Icons.location_on_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          FilledButton.icon(
            onPressed: () => permanently
                ? controller.openSettings()
                : controller.requestPermission(),
            icon: Icon(
              permanently ? Icons.settings : Icons.my_location,
              size: 18,
            ),
            label: Text(permanently ? 'فتح إعدادات التطبيق' : 'السماح بالوصول'),
          ),
        ],
      ),
    );
  }
}

/// عنصر شبكة واحدة — قابل للضغط إذا كانت الشبكة آمنة.
class _NetworkTile extends StatelessWidget {
  const _NetworkTile({required this.network, this.onTap});

  final WifiNetworkItem network;

  /// يُمرَّر فقط للشبكات الآمنة.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color securityColor = _colorFromHex(network.security.colorHex);
    final bool tappable = onTap != null;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: tappable
              ? securityColor.withOpacity(0.25)
              : AppColors.border,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: securityColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: securityColor.withOpacity(0.35)),
                ),
                child: Icon(_iconFor(network.security),
                    color: securityColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      network.displayName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: <Widget>[
                        StatusChip(
                          label: network.security.label,
                          color: securityColor,
                          dense: true,
                        ),
                        StatusChip(
                          label: network.bandLabel,
                          color: AppColors.textSecondary,
                          dense: true,
                        ),
                        if (tappable)
                          StatusChip(
                            label: 'اضغط لإدخال الرمز',
                            color: AppColors.primary,
                            icon: Icons.key,
                            dense: true,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  SignalBars(
                    ratio: network.strengthRatio,
                    color: network.strengthRatio > 0.6
                        ? AppColors.success
                        : AppColors.primary,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${network.level} dBm',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              if (tappable)
                const Icon(
                  Icons.chevron_left,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _iconFor(SecurityType type) {
    switch (type) {
      case SecurityType.open:
        return Icons.lock_open;
      case SecurityType.wep:
        return Icons.lock_outline;
      case SecurityType.wpa:
      case SecurityType.wpa2:
      case SecurityType.wpa2Enterprise:
        return Icons.lock;
      case SecurityType.wpa3:
      case SecurityType.wpa3Enterprise:
        return Icons.verified_user;
      case SecurityType.unknown:
        return Icons.help_outline;
    }
  }

  static Color _colorFromHex(String hex) {
    final String cleaned = hex.replaceFirst('#', '');
    final int? value = int.tryParse(cleaned, radix: 16);
    if (value == null) return AppColors.textSecondary;
    return Color(0xFF000000 | value);
  }
}

/// نافذة إدخال رمز/كلمة مرور الشبكة وتشغيل التجربة التلقائية.
class _NetworkSheet extends StatefulWidget {
  const _NetworkSheet();

  @override
  State<_NetworkSheet> createState() => _NetworkSheetState();
}

class _NetworkSheetState extends State<_NetworkSheet> {
  final TextEditingController _codeController = TextEditingController();
  bool _obscure = true;

  /// مرجع محفوظ للمتحكم لتفادي قراءة السياق أثناء الإغلاق.
  NetworkAttemptsController? _attempts;

  @override
  void initState() {
    super.initState();
    final NetworkAttemptsController controller =
        context.read<NetworkAttemptsController>();
    _attempts = controller;
    controller.addListener(_handleChange);
  }

  @override
  void dispose() {
    _attempts?.removeListener(_handleChange);
    _attempts = null;
    _codeController.dispose();
    super.dispose();
  }

  void _handleChange() {
    if (!mounted) return;
    final String? error = _attempts?.takeError();
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
    final NetworkAttemptsController attempts =
        context.watch<NetworkAttemptsController>();
    final WifiNetworkItem? network = attempts.target;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // مقبض السحب + زر الإغلاق.
                Row(
                  children: <Widget>[
                    const SizedBox(width: 8),
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'إغلاق',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, size: 20),
                    ),
                  ],
                ),
                if (network != null) ...<Widget>[
                  Row(
                    children: <Widget>[
                      const Icon(Icons.wifi, color: AppColors.primary, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          network.displayName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: <Widget>[
                      StatusChip(
                        label: network.security.label,
                        color: AppColors.primary,
                        dense: true,
                      ),
                      StatusChip(
                        label: network.bandLabel,
                        color: AppColors.textSecondary,
                        dense: true,
                      ),
                      StatusChip(
                        label: '${network.level} dBm',
                        color: AppColors.textSecondary,
                        dense: true,
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),

                // بوابة البوابة المستهدفة.
                if (attempts.gatewayUrl.isNotEmpty)
                  Text(
                    'بوابة التجربة: ${attempts.gatewayUrl}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      fontFamily: 'monospace',
                    ),
                  )
                else
                  const Text(
                    'لم يتم اكتشاف بوابة — افتح تبويب «البوابة» أولاً',
                    style: TextStyle(fontSize: 12, color: AppColors.warning),
                  ),
                const SizedBox(height: 16),

                if (attempts.running || attempts.total > 0) ...<Widget>[
                  // حالة التشغيل: نفس لوحة تبويب البوابة.
                  AutoFillControls(
                    running: attempts.running,
                    paused: attempts.paused,
                    completed: attempts.completed,
                    total: attempts.total,
                    successCount: attempts.sessionLogs
                        .where((AttemptLog e) => e.success)
                        .length,
                    currentCode: attempts.currentCode,
                    onStart: attempts.canStart
                        ? () => attempts.start()
                        : null,
                    onPauseResume: !attempts.running
                        ? null
                        : (attempts.paused
                            ? attempts.resume
                            : attempts.pause),
                    onCancel:
                        attempts.running ? () => attempts.cancel() : null,
                    statusLabel: attempts.connected ? 'نجح الاتصال' : null,
                  ),
                  if (attempts.connected) ...<Widget>[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppColors.success.withOpacity(0.4)),
                      ),
                      child: const Row(
                        children: <Widget>[
                          Icon(Icons.check_circle,
                              color: AppColors.success, size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'نجح الاتصال بالبوابة — الرمز الصحيح ظاهر في الأعلى',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ] else ...<Widget>[
                  // إدخال الرمز يدوياً.
                  TextField(
                    controller: _codeController,
                    onChanged: attempts.setManualCode,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: 'كلمة مرور الشبكة أو الرمز',
                      hintText: 'أدخل الرمز أو اختر ملف TXT',
                      prefixIcon:
                          const Icon(Icons.key_outlined, size: 20),
                      suffixIcon: IconButton(
                        tooltip: _obscure ? 'إظهار' : 'إخفاء',
                        onPressed: () =>
                            setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      const Expanded(child: Divider()),
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'أو',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: attempts.pickingFile
                        ? null
                        : () => attempts.pickFile(),
                    icon: attempts.pickingFile
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.attach_file, size: 18),
                    label: Text(
                      attempts.selectedFile == null
                          ? 'اختيار ملف TXT للرموز'
                          : 'الملف: ${attempts.selectedFile!.name} '
                              '(${attempts.selectedFile!.count} رمز)',
                    ),
                  ),
                  if (attempts.selectedFile != null &&
                      !attempts.running)
                    TextButton.icon(
                      onPressed: attempts.clearFile,
                      icon: const Icon(Icons.close, size: 14),
                      label: const Text('إزالة الملف'),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'سيُجرَّب كل رمز ككلمة مرور على بوابة الشبكة تباعاً '
                    'داخل الخلفية — بدون اسم مستخدم — مع إمكانية الإيقاف في أي لحظة.',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.6,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: attempts.canStart
                        ? () => attempts.start()
                        : null,
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('بدء التجربة التلقائية'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// شريط عائم يعرض حالة العملية الجارية أثناء تصفح القائمة.
class _RunningBanner extends StatelessWidget {
  const _RunningBanner({required this.attempts, required this.onOpen});

  final NetworkAttemptsController attempts;

  /// يفتح نافذة الشبكة مجدداً لمتابعة التقدم.
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final String name = attempts.target?.displayName ?? 'الشبكة';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withOpacity(0.5)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  attempts.running
                      ? 'جارٍ تجربة رموز «$name» — ${attempts.completed}/${attempts.total}'
                      : 'انتهت عملية «$name»',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              TextButton(
                onPressed: onOpen,
                child: const Text('فتح', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: attempts.progress,
              minHeight: 5,
            ),
          ),
        ],
      ),
    );
  }
}
