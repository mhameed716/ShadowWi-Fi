import 'dart:async';

import 'package:http/http.dart' as http;

import 'system_channel.dart';

/// نتيجة كشف البوابة الإجبارية.
class CaptivePortalInfo {
  const CaptivePortalInfo({
    required this.detected,
    required this.validated,
    required this.method,
    this.portalUrl,
    this.gateway,
  });

  /// هل وُجدت شبكة مقيدة ببوابة تسجيل؟
  final bool detected;

  /// هل تحقّق النظام من فتح الإنترنت؟ (null = غير معروف)
  final bool? validated;

  /// رابط البوابة الملتقط (هدف المحاولات).
  final String? portalUrl;

  /// بوابة الشبكة الافتراضية.
  final String? gateway;

  /// طريقة الاكتشاف (للعرض).
  final String method;
}

/// كاشف البوابة الإجبارية: علم النظام (ConnectivityManager) + فحص HTTP خفيف
/// يلتقط رابط التحويل (Redirect URL) تلقائياً.
class CaptivePortalDetector {
  CaptivePortalDetector(this._system);

  final SystemChannel _system;

  /// مهلة الفحص الخفيف.
  static const Duration probeTimeout = Duration(seconds: 5);

  /// رابط الفحص القياسي (204 = إنترنت مفتوح).
  static const String _probeUrl =
      'http://connectivitycheck.gstatic.com/generate_204';

  /// يشعّر بالبوابة ويلتقط رابطها إن وُجدت.
  Future<CaptivePortalInfo> detect() async {
    final String? gateway = await _system.gateway();
    final Map<String, dynamic> state = await _system.captiveState();
    final bool? validated =
        state['validated'] is bool ? state['validated'] as bool : null;
    final bool systemFlag = state['captivePortal'] == true;

    // فحص خفيف بدون متابعة التحويلات — لالتقاط رابط البوابة.
    final String? redirect = await _probe(_probeUrl) ?? await _probeGateway(gateway);
    final bool intercepted = redirect != null;

    final bool detected = systemFlag || intercepted;
    String? url = redirect;
    if (url == null && detected && gateway != null && gateway.isNotEmpty) {
      url = 'http://$gateway';
    }

    String method;
    if (systemFlag && intercepted) {
      method = 'علم النظام + تحويل HTTP';
    } else if (systemFlag) {
      method = 'علم النظام (CAPTIVE_PORTAL)';
    } else if (intercepted) {
      method = 'تحويل HTTP مُلتقط';
    } else {
      method = 'لا بوابة مقيدة حالياً';
    }

    return CaptivePortalInfo(
      detected: detected,
      validated: validated,
      method: method,
      portalUrl: url,
      gateway: gateway,
    );
  }

  /// يفحص رابطاً ويلتقط ترويسة التحويل دون متابعته.
  Future<String?> _probe(String url) async {
    try {
      final http.Request request =
          http.Request('GET', Uri.parse(url))..followRedirects = false;
      final http.StreamedResponse streamed =
          await request.send().timeout(probeTimeout);
      final http.Response response = await http.Response.fromStream(streamed);
      if (response.statusCode >= 300 && response.statusCode < 400) {
        final String? location = response.headers['location'];
        if (location != null && location.isNotEmpty) {
          return _resolve(url, location);
        }
        // استجابة غير 204 على رابط الفحص = اعتراض بدون ترويسة.
        if (url == _probeUrl && response.statusCode != 204) {
          return '';
        }
      }
      if (url == _probeUrl && response.statusCode != 204) {
        return '';
      }
    } catch (_) {
      // الشبكة غير جاهزة — يعاد الفحص في الدورة التالية.
    }
    return null;
  }

  /// فحص بوابة الراوتر مباشرة (يُلتقط تحويل صفحة تسجيل الدخول).
  Future<String?> _probeGateway(String? gateway) async {
    if (gateway == null || gateway.isEmpty) return null;
    final String? result = await _probe('http://$gateway/');
    if (result != null && result.isNotEmpty) return result;
    return null;
  }

  /// يحوّل مساراً نسبياً إلى رابط كامل.
  String _resolve(String base, String location) {
    try {
      return Uri.parse(base).resolve(location).toString();
    } catch (_) {
      return location;
    }
  }
}
