import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../state/portal_controller.dart';
import 'features/diagnostics/diagnostics_screen.dart';
import 'features/logs/logs_screen.dart';
import 'features/networks/networks_screen.dart';
import 'features/portal/portal_screen.dart';

/// الهيكل الرئيسي: شريط علوي + تنقل سفلي بأربعة أقسام.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const List<Widget> _screens = <Widget>[
    PortalScreen(),
    DiagnosticsScreen(),
    LogsScreen(),
    NetworksScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 16,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              AppConstants.appTitle,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: 0.4,
              ),
            ),
            Text(
              AppConstants.appSubtitle,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        actions: const <Widget>[
          Padding(
            padding: EdgeInsets.only(left: 12, right: 16),
            child: _SecurityStatusIcon(),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: IndexedStack(index: _index, children: _screens),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int value) => setState(() => _index = value),
        backgroundColor: AppColors.background,
        indicatorColor: AppColors.primary.withOpacity(0.18),
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.router_outlined),
            selectedIcon: Icon(Icons.router),
            label: 'البوابة',
          ),
          NavigationDestination(
            icon: Icon(Icons.troubleshoot_outlined),
            selectedIcon: Icon(Icons.troubleshoot),
            label: 'التشخيص',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'السجل',
          ),
          NavigationDestination(
            icon: Icon(Icons.wifi_tethering_outlined),
            selectedIcon: Icon(Icons.wifi_tethering),
            label: 'الشبكات',
          ),
        ],
      ),
    );
  }
}

/// أيقونة حالة الأمان في زاوية شريط العنوان.
class _SecurityStatusIcon extends StatelessWidget {
  const _SecurityStatusIcon();

  @override
  Widget build(BuildContext context) {
    final PortalController controller = context.watch<PortalController>();

    Color color = AppColors.textSecondary;
    IconData icon = Icons.shield_outlined;
    String label = 'غير محدد';

    if (controller.connected) {
      color = AppColors.success;
      icon = Icons.verified_user;
      label = 'متصل';
    } else if (controller.gateway?.responded ?? false) {
      color = AppColors.primary;
      icon = Icons.shield;
      label = 'بوابة نشطة';
    } else if (controller.gateway != null) {
      color = AppColors.warning;
      icon = Icons.shield_outlined;
      label = 'بوابة غير مستجيبة';
    }

    return Tooltip(
      message: 'حالة الأمان: $label',
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }
}
