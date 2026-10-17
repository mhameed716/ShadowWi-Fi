import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/security_type.dart';
import '../../../data/models/wifi_network_item.dart';
import '../../../state/networks_controller.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/section_card.dart';
import '../../widgets/signal_bars.dart';
import '../../widgets/status_chip.dart';

/// تبويب «الشبكات»: عرض شبكات الواي فاي القريبة مع سحب للتحديث.
class NetworksScreen extends StatefulWidget {
  const NetworksScreen({super.key});

  @override
  State<NetworksScreen> createState() => _NetworksScreenState();
}

class _NetworksScreenState extends State<NetworksScreen> {
  /// مرجع محفوظ للمتحكم لتفادي قراءة السياق أثناء الإغلاق.
  NetworksController? _controller;

  @override
  void initState() {
    super.initState();
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
    final NetworksController controller = context.watch<NetworksController>();

    return RefreshIndicator(
      onRefresh: controller.scan,
      color: AppColors.primary,
      backgroundColor: AppColors.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: <Widget>[
          _PermissionBanner(controller: controller),
          if (controller.permission != LocationPermissionState.permanentlyDenied)
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
                    'اسحب للأسفل لإعادة الفحص، أو تحقق من تفعيل الواي فاي في الجهاز.',
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
                  'تم العثور على ${controller.networks.length} شبكة',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
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
                child: _NetworkTile(network: network),
              ),
          ],
        ],
      ),
    );
  }
}

/// لافتة أذونات الموقع.
class _PermissionBanner extends StatelessWidget {
  const _PermissionBanner({required this.controller});

  final NetworksController controller;

  @override
  Widget build(BuildContext context) {
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

/// عنصر شبكة واحدة.
class _NetworkTile extends StatelessWidget {
  const _NetworkTile({required this.network});

  final WifiNetworkItem network;

  @override
  Widget build(BuildContext context) {
    final Color securityColor = _colorFromHex(network.security.colorHex);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: securityColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: securityColor.withOpacity(0.35)),
            ),
            child: Icon(_iconFor(network.security), color: securityColor, size: 20),
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
        ],
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
