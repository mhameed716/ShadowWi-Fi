import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../../core/app_constants.dart';
import '../models/diagnostics_snapshot.dart';
import '../models/internet_check_result.dart';
import '../models/login_outcome.dart';
import 'portal_client.dart';
import 'system_channel.dart';

/// خدمة جمع تفاصيل الاتصال لعرضها في تبويب «التشخيص».
class DiagnosticsService {
  DiagnosticsService(this._system, {PortalClient client = const PortalClient()})
      : _client = client;

  final SystemChannel _system;
  final PortalClient _client;

  /// ينفّذ فحصاً شاملاً ويعيد لقطة النتائج.
  Future<DiagnosticsSnapshot> run({String? gatewayHost}) async {
    DateTime now = DateTime.now();
    String? connectionType;
    List<String> addresses = <String>[];
    String? gateway;
    List<String> dns = <String>[];
    String? error;

    try {
      final List<ConnectivityResult> connectivity =
          await Connectivity().checkConnectivity();
      if (connectivity.isNotEmpty) {
        connectionType = connectivity.first.name;
      }
    } catch (e) {
      error = 'تعذّر قراءة نوع الاتصال: $e';
    }

    try {
      final Map<String, dynamic> device = await _system.deviceInfo();
      final dynamic deviceAddresses = device['addresses'];
      if (deviceAddresses is List) {
        addresses = deviceAddresses.map((dynamic e) => e.toString()).toList();
      }
    } catch (_) {
      // تُكمل القيم الأخرى.
    }

    if (addresses.isEmpty) {
      try {
        final List<NetworkInterface> interfaces =
            await NetworkInterface.list(type: InternetAddressType.IPv4);
        for (final NetworkInterface item in interfaces) {
          for (final InternetAddress address in item.addresses) {
            final String value = address.address;
            if (!value.startsWith('127.') && !addresses.contains(value)) {
              addresses.add(value);
            }
          }
        }
      } catch (_) {
        // تجاهُل.
      }
    }

    try {
      gateway = await _system.gateway();
    } catch (_) {
      // تجاهُل.
    }

    try {
      dns = await _system.dnsServers();
    } catch (_) {
      // تجاهُل.
    }

    String? portalTitle;
    int? portalStatus;
    String? portalUrl;

    final String host = (gatewayHost ?? gateway ?? '').trim();
    if (host.isNotEmpty) {
      final LoginOutcome probe = await _client.probe(host);
      portalTitle = probe.pageTitle;
      portalStatus = probe.statusCode;
      portalUrl = probe.finalUrl;
    }

    final InternetCheckResult internet = await _client.checkInternet();

    now = DateTime.now();

    return DiagnosticsSnapshot(
      takenAt: now,
      connectionType: connectionType,
      deviceAddresses: addresses,
      gateway: gateway ?? (host.isEmpty ? null : host),
      dnsServers: dns,
      hasInternet: internet.online,
      internetLatencyMs: internet.latencyMs,
      internetStatusCode: internet.statusCode,
      portalTitle: portalTitle,
      portalStatusCode: portalStatus,
      portalUrl: portalUrl,
      error: error,
    );
  }

  /// يفحص الإنترنت فقط (سريع).
  Future<bool> quickInternetCheck() async {
    final InternetCheckResult result = await _client.checkInternet();
    return result.online;
  }

  /// عنوان فحص الاتصال المستخدم.
  static String get checkUrl => AppConstants.internetCheckUrl;
}
