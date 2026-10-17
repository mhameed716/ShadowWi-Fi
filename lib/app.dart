import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'data/services/diagnostics_service.dart';
import 'data/services/gateway_service.dart';
import 'data/services/log_service.dart';
import 'data/services/permission_service.dart';
import 'data/services/system_channel.dart';
import 'data/services/wifi_scan_service.dart';
import 'state/diagnostics_controller.dart';
import 'state/logs_controller.dart';
import 'state/networks_controller.dart';
import 'state/portal_controller.dart';
import 'ui/home_shell.dart';

/// جذر التطبيق: يوفّر مزوّدي الحالة ويضبط الثيم واتجاه اللغة.
class ShadowWifiApp extends StatelessWidget {
  const ShadowWifiApp({super.key});

  @override
  Widget build(BuildContext context) {
    // سجل واحد مشترك بين تبويب السجل وتبويب البوابة.
    final LogsController logsController = LogsController(LogService());

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LogsController>(
          create: (BuildContext context) => logsController..load(),
        ),
        ChangeNotifierProvider<PortalController>(
          create: (BuildContext context) => PortalController(
            gatewayService: GatewayService(SystemChannel.instance),
            logsController: logsController,
          )..bootstrap(),
        ),
        ChangeNotifierProvider<DiagnosticsController>(
          create: (BuildContext context) => DiagnosticsController(
            DiagnosticsService(SystemChannel.instance),
          ),
        ),
        ChangeNotifierProvider<NetworksController>(
          create: (BuildContext context) =>
              NetworksController(WifiScanService(PermissionService.instance)),
        ),
      ],
      child: MaterialApp(
        title: 'ShadowWi-Fi',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.dark,
        locale: const Locale('ar'),
        supportedLocales: const <Locale>[Locale('ar'), Locale('en')],
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (BuildContext context, Widget? child) {
          final MediaQueryData media = MediaQuery.of(context);
          final double scale = media.textScaler.scale(1).clamp(0.9, 1.25).toDouble();
          return Directionality(
            textDirection: TextDirection.rtl,
            child: MediaQuery(
              data: media.copyWith(textScaler: TextScaler.linear(scale)),
              child: child ?? const SizedBox.shrink(),
            ),
          );
        },
        home: const HomeShell(),
      ),
    );
  }
}
