import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/security_type.dart';
import '../../../data/models/wifi_network_item.dart';
import '../../../data/services/wifi_connect_service.dart';
import '../../../data/services/wifi_scan_service.dart';
import '../../../state/networks_controller.dart';
import '../../../state/wifi_connect_controller.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/section_card.dart';
import '../../widgets/signal_bars.dart';
import '../../widgets/status_chip.dart';

/// تبويب «الشبكات» — مثل شاشة إعدادات الواي فاي في أندرويد:
///
/// - الشبكة الحالية في الأعلى بحالة «متصل».
/// - قائمة الشبكات المتاحة مع قوة الإشارة ونوع التشفير.
/// - الضغط على أي شبكة محمية يفتح نافذة كلمة المرور — ويحاول الاتصال
///   الحقيقي بالشبكة؛ وعند نجاح الرمز يتصل ويظهر «متصل».
/// - زر «تجربة تلقائية» يجرّب رموز ملف TXT عبر محاولات اتصال حقيقية
///   متتالية مع إيقاف مؤقت/استئناف/إلغاء.
/// - سحب للتحديث لإعادة الفحص (عملية محلية بلا إنترنت).
class NetworksScreen extends StatefulWidget {
  const NetworksScreen({super.key});

  @override
  State<NetworksScreen> createState() => _NetworksScreenState();
}

class _NetworksScreenState extends State<NetworksScreen>
    with WidgetsBindingObserver {
  /// مراجع محفوظة للمتحكمات لتفادي قراءة السياق أثناء الإغلاق.
  NetworksController? _controller;
  WifiConnectController? _wifi;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final NetworksController controller = context.read<NetworksController>();
    final WifiConnectController wifi = context.read<WifiConnectController>();
    _controller = controller;
    _wifi = wifi;
    controller.addListener(_handleChange);
    wifi.addListener(_handleWifiChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.refreshPermissionState();
      controller.refreshCurrentWifi();
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
    _wifi?.removeListener(_handleWifiChange);
    _wifi = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // عند العودة من إعدادات النظام: قراءة الأذونات، وإعادة الفحص تلقائياً
    // إذا كان العائق مرفوعاً، وتحديث الشبكة المتصلة.
    if (state == AppLifecycleState.resumed) {
      final NetworksController? controller = _controller;
      if (controller == null) return;
      controller.refreshPermissionState().then((_) {
        controller.refreshCurrentWifi();
        if (!mounted) return;
        if (controller.blocker != null &&
            controller.permission == LocationPermissionState.granted &&
            !controller.scanning) {
          controller.scan();
        }
      });
    }
  }

  void _handleChange() {
    if (!mounted) return;
    final String? error = _controller?.takeError();
    if (error == null) return;
    _showError(error);
  }

  void _handleWifiChange() {
    if (!mounted) return;
    final WifiConnectController? wifi = _wifi;
    if (wifi == null) return;
    final String? error = wifi.takeError();
    if (error != null) _showError(error);

    // عند النجاح: تحديث بطاقة «الشبكة الحالية» فوراً مثل أندرويد.
    if (wifi.connected && wifi.connectedSsid != null) {
      _controller?.refreshCurrentWifi();
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: <Widget>[
              const Icon(Icons.error_outline, color: AppColors.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(message)),
            ],
          ),
          duration: const Duration(seconds: 4),
        ),
      );
  }

  Future<void> _openNetworkDialog(WifiNetworkItem network) async {
    final WifiConnectController wifi = context.read<WifiConnectController>();
    wifi.setTarget(
      network.displayName,
      isWpa3: WifiConnectService.isWpa3(network.security),
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) => ChangeNotifierProvider<
          WifiConnectController>.value(
        value: wifi,
        child: const _ConnectSheet(),
      ),
    ).whenComplete(wifi.resetIfIdle);
  }

  @override
  Widget build(BuildContext context) {
    final NetworksController controller = context.watch<NetworksController>();
    final WifiConnectController wifi = context.watch<WifiConnectController>();

    final bool showBlocker = controller.blocker != null ||
        controller.permission != LocationPermissionState.granted;

    return Stack(
      children: <Widget>[
        RefreshIndicator(
          onRefresh: () async {
            await controller.scan();
            await controller.refreshCurrentWifi();
          },
          color: AppColors.primary,
          backgroundColor: AppColors.surface,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: <Widget>[
              // الشبكة المتصلة حالياً — مثل أعلى شاشة إعدادات الواي فاي.
              _CurrentNetworkCard(controller: controller),
              const SizedBox(height: 12),

              // عند نقص الإذن أو وجود عائق: بطاقة معالجة السبب فقط —
              // لا نعرض «لا توجد شبكات» لأن القائمة الفارغة مضللة.
              if (showBlocker) ...<Widget>[
                _PermissionBanner(controller: controller),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed:
                      controller.scanning ? null : () => controller.scan(),
                  icon: controller.scanning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 18),
                  label: const Text('إعادة المحاولة'),
                ),
              ]
              // الفحص يعمل فعلياً من هنا فصاعداً.
              else if (controller.scanning && controller.networks.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (controller.networks.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: EmptyState(
                    icon: Icons.wifi_tethering,
                    title: 'لا نتائج فحص',
                    message:
                        'اكتمل الفحص دون نتائج — تأكد من تفعيل الواي فاي '
                        'وأنك داخل نطاق شبكات، ثم اسحب للأسفل لإعادة الفحص.',
                    action: FilledButton.icon(
                      onPressed: controller.scan,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('إعادة الفحص'),
                    ),
                  ),
                )
              else ...<Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'الشبكات المتاحة — ${controller.networks.length}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                for (final WifiNetworkItem network in controller.networks)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _NetworkTile(
                      network: network,
                      connectedTo: controller.currentWifi['ssid']?.toString(),
                      onTap: network.security == SecurityType.open
                          ? null
                          : () => _openNetworkDialog(network),
                    ),
                  ),
              ],
            ],
          ),
        ),
        // شريط تقدم عائم أثناء الحلقة التلقائية.
        if (wifi.running)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: _RunningBanner(
              wifi: wifi,
              onOpen: wifi.ssid.isEmpty
                  ? null
                  : () {
                      final WifiNetworkItem? match = controller.networks
                          .cast<WifiNetworkItem?>()
                          .firstWhere(
                            (WifiNetworkItem? item) =>
                                item?.displayName == wifi.ssid,
                            orElse: () => null,
                          );
                      if (match != null) {
                        _openNetworkDialog(match);
                      }
                    },
            ),
          ),
      ],
    );
  }
}

/// بطاقة الشبكة المتصلة حالياً (أعلى الشاشة مثل أندرويد).
class _CurrentNetworkCard extends StatelessWidget {
  const _CurrentNetworkCard({required this.controller});

  final NetworksController controller;

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> info = controller.currentWifi;
    final String? ssid = info['ssid']?.toString();

    if (ssid == null || ssid.isEmpty) {
      return SectionCard(
        title: 'غير متصل',
        subtitle: 'لا يوجد اتصال واي فاي حالياً',
        icon: Icons.wifi_off_outlined,
        child: const SizedBox.shrink(),
      );
    }

    final int? level = info['level'] is int ? info['level'] as int : null;
    final double ratio = level == null
        ? 0.5
        : ((level + 100) / 70).clamp(0.0, 1.0).toDouble();

    return SectionCard(
      title: ssid,
      subtitle: 'متصل — إشارة ${level ?? '?'} dBm',
      icon: Icons.wifi,
      trailing: StatusChip(
        label: 'متصل',
        color: AppColors.success,
        icon: Icons.check_circle,
      ),
      child: Row(
        children: <Widget>[
          SignalBars(ratio: ratio, color: AppColors.success),
          const SizedBox(width: 10),
          if (info['bssid'] != null)
            Expanded(
              child: Text(
                '${info['bssid']}'
                '${info['frequency'] != null ? ' • ${info['frequency']}MHz' : ''}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                  fontFamily: 'monospace',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// بطاقة معالجة عائق الفحص: أذونات ناقصة، رفض نهائي، أو خدمة موقع مغلقة.
class _PermissionBanner extends StatelessWidget {
  const _PermissionBanner({required this.controller});

  final NetworksController controller;

  @override
  Widget build(BuildContext context) {
    final WifiScanBlocker? blocker = controller.blocker;
    final bool permanently =
        controller.permission == LocationPermissionState.permanentlyDenied;

    final String title;
    final String subtitle;
    final IconData icon;
    final String buttonLabel;
    final VoidCallback onPressed;

    if (blocker == WifiScanBlocker.locationService) {
      title = 'خدمة الموقع مغلقة';
      subtitle = 'نتائج فحص الواي فاي على أندرويد مرتبطة بخدمة الموقع — '
          'فعّلها من إعدادات النظام ثم اضغط إعادة المحاولة';
      icon = Icons.location_disabled_outlined;
      buttonLabel = 'فتح إعدادات الموقع';
      onPressed = controller.openLocationSettings;
    } else if (permanently) {
      title = 'الإذن ممنوع نهائياً';
      subtitle = 'فعّل إذن الموقع من إعدادات التطبيق ثم عُد واضغط إعادة المحاولة';
      icon = Icons.block_outlined;
      buttonLabel = 'فتح إعدادات التطبيق';
      onPressed = controller.openSettings;
    } else {
      title = 'إذن الموقع مطلوب';
      subtitle = 'يحتاج فحص الشبكات القريبة إلى إذن الموقع — '
          'ستظهر نافذة السماح عند الضغط على الزر';
      icon = Icons.location_on_outlined;
      buttonLabel = 'السماح بالوصول';
      onPressed = controller.requestPermission;
    }

    return SectionCard(
      title: title,
      subtitle: subtitle,
      icon: icon,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(
              blocker == WifiScanBlocker.locationService
                  ? Icons.settings_input_antenna
                  : (permanently ? Icons.settings : Icons.my_location),
              size: 18,
            ),
            label: Text(buttonLabel),
          ),
        ],
      ),
    );
  }
}

/// عنصر شبكة واحدة — مثل صفوف قائمة أندرويد.
class _NetworkTile extends StatelessWidget {
  const _NetworkTile({
    required this.network,
    required this.connectedTo,
    this.onTap,
  });

  final WifiNetworkItem network;

  /// اسم الشبكة المتصلة حالياً (إن طابقت يظهر «متصل»).
  final String? connectedTo;

  /// يُمرَّر فقط للشبكات المحمية.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color securityColor = _colorFromHex(network.security.colorHex);
    final bool tappable = onTap != null;
    final bool connected =
        connectedTo != null && connectedTo == network.displayName;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: connected
              ? AppColors.success.withOpacity(0.5)
              : (tappable ? securityColor.withOpacity(0.25) : AppColors.border),
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
                  color: (connected ? AppColors.success : securityColor)
                      .withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: (connected ? AppColors.success : securityColor)
                        .withOpacity(0.35),
                  ),
                ),
                child: Icon(
                  connected ? Icons.wifi : _iconFor(network.security),
                  color: connected ? AppColors.success : securityColor,
                  size: 20,
                ),
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
                        if (connected)
                          const StatusChip(
                            label: 'متصل',
                            color: AppColors.success,
                            dense: true,
                          ),
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
                            label: 'اضغط للاتصال',
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

/// نافذة الاتصال — مثل نافذة كلمة المرور في أندرويد:
/// حقل واحد + زر «اتصال» بمحاولة حقيقية، وخيار تجربة تلقائية من ملف TXT.
class _ConnectSheet extends StatefulWidget {
  const _ConnectSheet();

  @override
  State<_ConnectSheet> createState() => _ConnectSheetState();
}

class _ConnectSheetState extends State<_ConnectSheet> {
  final TextEditingController _passwordController = TextEditingController();
  bool _obscure = true;

  /// مرجع محفوظ للمتحكم لتفادي قراءة السياق أثناء الإغلاق.
  WifiConnectController? _wifi;

  @override
  void initState() {
    super.initState();
    final WifiConnectController controller =
        context.read<WifiConnectController>();
    _wifi = controller;
    controller.addListener(_handleChange);
  }

  @override
  void dispose() {
    _wifi?.removeListener(_handleChange);
    _wifi = null;
    _passwordController.dispose();
    super.dispose();
  }

  void _handleChange() {
    if (!mounted) return;
    final String? error = _wifi?.takeError();
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
    final WifiConnectController wifi = context.watch<WifiConnectController>();

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

                // عنوان الشبكة.
                Row(
                  children: <Widget>[
                    const Icon(Icons.wifi, color: AppColors.primary, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        wifi.ssid,
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
                const SizedBox(height: 16),

                // نتيجة/حالة الاتصال.
                if (wifi.connected) ...<Widget>[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(14),
                      border:
                          Border.all(color: AppColors.success.withOpacity(0.45)),
                    ),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.check_circle,
                            color: AppColors.success, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'تم الاتصال بـ ${wifi.connectedSsid} بنجاح',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('تم'),
                        ),
                      ],
                    ),
                  ),
                ] else if (wifi.running && wifi.total > 1) ...<Widget>[
                  // الحلقة التلقائية جارية — عرض التقدم داخل النافذة.
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(
                          'تجربة رموز «${wifi.ssid}» — ${wifi.completed}/${wifi.total}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: wifi.progress,
                            minHeight: 6,
                          ),
                        ),
                        if (wifi.currentCode != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'الرمز الحالي: ${wifi.currentCode}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: wifi.paused
                                    ? wifi.resume
                                    : wifi.pause,
                                icon: Icon(
                                  wifi.paused
                                      ? Icons.play_circle_outline
                                      : Icons.pause_circle_outline,
                                  size: 16,
                                ),
                                label: Text(
                                  wifi.paused ? 'استئناف' : 'إيقاف مؤقت',
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: wifi.cancel,
                                icon: const Icon(Icons.stop_circle_outlined,
                                    size: 16),
                                label: const Text('إلغاء'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ] else if (wifi.running && wifi.total <= 1) ...<Widget>[
                  // محاولة يدوية جارية.
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: <Widget>[
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            wifi.total <= 1
                                ? 'جارٍ الاقتران بـ ${wifi.ssid}...'
                                    '\nستظهر نافذة النظام «اختيار جهاز» — '
                                    'اضغط على اسم شبكتك داخلها ثم اقبل'
                                : 'جارٍ التجربة التلقائية على ${wifi.ssid}...'
                                    '\nاقتراحات صامتة — دون نوافذ لكل رمز',
                            style: const TextStyle(
                              fontSize: 12,
                              height: 1.5,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        OutlinedButton(
                          onPressed: wifi.cancel,
                          child: const Text('إلغاء'),
                        ),
                      ],
                    ),
                  ),
                ] else if (!wifi.running) ...<Widget>[
                  // إدخال كلمة المرور — مثل نافذة أندرويد.
                  TextField(
                    controller: _passwordController,
                    onChanged: wifi.setPassword,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: 'كلمة مرور الشبكة',
                      hintText: 'أدخل كلمة المرور أو الرمز',
                      prefixIcon: const Icon(Icons.key_outlined, size: 20),
                      suffixIcon: IconButton(
                        tooltip: _obscure ? 'إظهار' : 'إخفاء',
                        onPressed: () => setState(() => _obscure = !_obscure),
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
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'عند الاتصال ستنبثق نافذة النظام «اختيار جهاز» — '
                      'اضغط على اسم الشبكة داخلها للموافقة',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.4,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed:
                        wifi.canConnect ? () => wifi.connectOnce() : null,
                    icon: const Icon(Icons.wifi, size: 18),
                    label: const Text('اتصال'),
                  ),
                  OutlinedButton.icon(
                    onPressed: wifi.openWifiPanel,
                    icon: const Icon(Icons.tune, size: 18),
                    label: const Text('الاتصال عبر النظام (مضمون)'),
                  ),

                  const SizedBox(height: 6),
                  Row(
                    children: <Widget>[
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'أو تجربة تلقائية',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 6),

                  OutlinedButton.icon(
                    onPressed: wifi.pickingFile ? null : wifi.pickFile,
                    icon: wifi.pickingFile
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.attach_file, size: 18),
                    label: Text(
                      wifi.selectedFile == null
                          ? 'اختيار ملف TXT للرموز'
                          : 'الملف: ${wifi.selectedFile!.name} '
                              '(${wifi.selectedFile!.count} رمز)',
                    ),
                  ),
                  if (wifi.selectedFile != null)
                    TextButton.icon(
                      onPressed: wifi.clearFile,
                      icon: const Icon(Icons.close, size: 14),
                      label: const Text('إزالة الملف'),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'ستجرب الحلقة كل رمز عبر محاولة اتصال حقيقية بالشبكة '
                    'تباعاً — أول رمز صحيح يتصل به الجهاز فعلياً ويظهر «متصل».',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.6,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed:
                        wifi.canStartLoop ? () => wifi.startLoop() : null,
                    icon: const Icon(Icons.auto_mode, size: 18),
                    label: const Text('بدء التجربة التلقائية'),
                  ),
                  if (wifi.exhausted) ...<Widget>[
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        'فشل الاقتران بالرموز المُجرَّبة — الكلمة غير موجودة '
                        'في الملف أو الشبكة خارج النطاق الآن',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: AppColors.primaryLight,
                        ),
                      ),
                    ),
                  ],
                  if (wifi.needsSystemFix) ...<Widget>[
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        wifi.error ?? 'هناك مانع يمنع الاقتران الآن',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: AppColors.warning,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: wifi.openLocationSettings,
                      icon: const Icon(Icons.location_on_outlined, size: 18),
                      label: const Text('فتح إعدادات الموقع'),
                    ),
                    OutlinedButton.icon(
                      onPressed: wifi.openWifiPanel,
                      icon: const Icon(Icons.wifi, size: 18),
                      label: const Text('الاتصال عبر النظام (مضمون)'),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// شريط عائم يعرض تقدم الحلقة التلقائية أثناء تصفح القائمة.
class _RunningBanner extends StatelessWidget {
  const _RunningBanner({required this.wifi, this.onOpen});

  final WifiConnectController wifi;

  /// يفتح نافذة الشبكة لمتابعة التقدم.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
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
                  'تجربة رموز «${wifi.ssid}» — ${wifi.completed}/${wifi.total}'
                  '${wifi.paused ? ' (متوقف)' : ''}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (onOpen != null)
                TextButton(
                  onPressed: onOpen,
                  child: const Text('فتح', style: TextStyle(fontSize: 12)),
                ),
              TextButton(
                onPressed: wifi.cancel,
                child: const Text('إلغاء', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: wifi.progress,
              minHeight: 5,
            ),
          ),
          if (wifi.currentCode != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'الرمز الحالي: ${wifi.currentCode}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                  fontFamily: 'monospace',
                ),
              ),
            ),
        ],
      ),
    );
  }
}
