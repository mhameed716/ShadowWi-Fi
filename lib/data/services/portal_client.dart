import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/app_constants.dart';
import '../models/internet_check_result.dart';
import '../models/login_outcome.dart';

/// عميل HTTP نقي (بدون أي إضافات نظام) يمكن تشغيله داخل Isolate منفصل.
class PortalClient {
  const PortalClient();

  /// يضيف http:// عند عدم وجود بروتوكول.
  static String normalizeBase(String raw) {
    final String value = raw.trim();
    if (value.isEmpty) return '';
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value.endsWith('/')
          ? value.substring(0, value.length - 1)
          : value;
    }
    return 'http://$value';
  }

  /// يستخرج عنوان الصفحة من HTML.
  static String? extractTitle(String body) {
    if (body.isEmpty) return null;
    final RegExpMatch? match =
        RegExp(r'<title[^>]*>([\s\S]*?)</title>', caseSensitive: false)
            .firstMatch(body);
    if (match == null) return null;
    final String title = match.group(1) ?? '';
    final String cleaned = title
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('&nbsp;', ' ')
        .trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  /// يفحص البوابة ويجيب رمز HTTP وعنوان الصفحة.
  Future<LoginOutcome> probe(String baseUrl) async {
    final String base = normalizeBase(baseUrl);
    if (base.isEmpty) {
      return const LoginOutcome(
        success: false,
        message: 'عنوان البوابة غير صالح',
      );
    }
    final Stopwatch stopwatch = Stopwatch()..start();
    try {
      final http.Response response = await http
          .get(Uri.parse('$base/'))
          .timeout(AppConstants.probeTimeout);
      stopwatch.stop();
      return LoginOutcome(
        success: true,
        message: 'استجابت البوابة',
        statusCode: response.statusCode,
        finalUrl: response.request?.url.toString(),
        pageTitle: extractTitle(response.body),
        durationMs: stopwatch.elapsedMilliseconds,
      );
    } on TimeoutException {
      stopwatch.stop();
      return LoginOutcome(
        success: false,
        message: 'انتهت مهلة الفحص',
        durationMs: stopwatch.elapsedMilliseconds,
      );
    } on SocketException catch (error) {
      stopwatch.stop();
      return LoginOutcome(
        success: false,
        message: 'تعذّر الوصول إلى البوابة: ${error.message}',
        durationMs: stopwatch.elapsedMilliseconds,
      );
    } catch (error) {
      stopwatch.stop();
      return LoginOutcome(
        success: false,
        message: 'خطأ غير متوقع: $error',
        durationMs: stopwatch.elapsedMilliseconds,
      );
    }
  }

  /// يتحقق من توفر الإنترنت عبر فحص 204.
  Future<bool> hasInternet({Duration? timeout}) async {
    try {
      final http.Response response = await http
          .get(Uri.parse(AppConstants.internetCheckUrl))
          .timeout(timeout ?? AppConstants.internetTimeout);
      return response.statusCode == 204;
    } catch (_) {
      return false;
    }
  }

  /// يختبر فحص الإنترنت ويعيد الرمز وزمن الاستجابة.
  Future<InternetCheckResult> checkInternet() async {
    final Stopwatch stopwatch = Stopwatch()..start();
    try {
      final http.Response response = await http
          .get(Uri.parse(AppConstants.internetCheckUrl))
          .timeout(AppConstants.internetTimeout);
      stopwatch.stop();
      return InternetCheckResult(
        online: response.statusCode == 204,
        statusCode: response.statusCode,
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    } catch (_) {
      stopwatch.stop();
      return InternetCheckResult(
        online: false,
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    }
  }

  /// يحاول تسجيل الدخول إلى البوابة باستخدام بيانات المستخدم.
  ///
  /// ترسل الحقول `username` و`password` و`dst` كما تتوقع بوابات الشبكة
  /// الشائعة. بعدها يتم التحقق من الإنترنت، ثم تحليل محتوى الصفحة عند تعذّر
  /// ذلك.
  Future<LoginOutcome> attempt({
    required String baseUrl,
    required String username,
    required String password,
    required String destination,
    bool verifyInternet = true,
    bool allowEmptyUsername = false,
  }) async {
    final String base = normalizeBase(baseUrl);
    if (base.isEmpty) {
      return const LoginOutcome(
        success: false,
        message: 'عنوان البوابة غير صالح',
      );
    }
    if (username.trim().isEmpty && !allowEmptyUsername) {
      return const LoginOutcome(
        success: false,
        message: 'أدخل اسم المستخدم أو رقم الجهاز',
      );
    }

    final Stopwatch stopwatch = Stopwatch()..start();
    final _HttpResult result = await _post(
      Uri.parse('$base/'),
      <String, String>{
        'username': username.trim(),
        'password': password,
        'dst': destination,
      },
    );

    if (result.response == null) {
      stopwatch.stop();
      return LoginOutcome(
        success: false,
        message: result.error ?? 'فشل الاتصال بالبوابة',
        durationMs: stopwatch.elapsedMilliseconds,
      );
    }

    final http.Response response = result.response!;

    stopwatch.stop();
    final String body = response.body;
    final String? title = extractTitle(body);
    final String lowered = body.toLowerCase();

    bool success = false;
    bool internetVerified = false;
    String message = 'لم يرد تأكيد واضح من البوابة';

    if (verifyInternet) {
      final bool online = await hasInternet();
      internetVerified = online;
      if (online) {
        success = true;
        message = 'تم الاتصال بالإنترنت بنجاح';
      }
    }

    if (!success) {
      if (_containsAny(lowered, _successMarkers)) {
        success = true;
        message = 'رُحّب بدخول المستخدم (تحقق من الإنترنت غير متاح)';
      } else if (_containsAny(lowered, _failureMarkers)) {
        success = false;
        message = 'رُفضت البيانات: اسم المستخدم أو الرمز غير صحيح';
      } else if (title != null &&
          title.toLowerCase().contains('login')) {
        success = false;
        message = 'ما زالت صفحة الدخول معروضة — لم تنجح المصادقة';
      } else {
        success = false;
        message = 'لم يرد تأكيد واضح من البوابة';
      }
    }

    return LoginOutcome(
      success: success,
      message: message,
      statusCode: response.statusCode,
      finalUrl: response.request?.url.toString(),
      pageTitle: title,
      durationMs: stopwatch.elapsedMilliseconds,
      internetVerified: internetVerified,
    );
  }

  /// يرسل طلب POST ويعيد النتيجة أو رسالة الخطأ.
  Future<_HttpResult> _post(
    Uri uri,
    Map<String, String> body,
  ) async {
    try {
      final http.Response response = await http
          .post(
            uri,
            body: body,
            headers: const <String, String>{
              'Content-Type': 'application/x-www-form-urlencoded',
            },
          )
          .timeout(AppConstants.loginTimeout);
      return _HttpResult(response);
    } on TimeoutException {
      return const _HttpResult(null, 'انتهت مهلة تسجيل الدخول');
    } on SocketException catch (error) {
      return _HttpResult(null, 'تعذّر الاتصال بالبوابة: ${error.message}');
    } catch (error) {
      return _HttpResult(null, 'فشل الطلب: $error');
    }
  }

  static const List<String> _successMarkers = <String>[
    'logged in',
    'login success',
    'status=1',
    'you are logged in',
    'logout',
    'تم الاتصال',
  ];

  static const List<String> _failureMarkers = <String>[
    'invalid',
    'incorrect',
    'wrong',
    'failed',
    'denied',
    'error',
    'not authorized',
    'unauthorized',
    'invalid username or password',
  ];

  static bool _containsAny(String haystack, List<String> needles) {
    for (final String needle in needles) {
      if (haystack.contains(needle)) return true;
    }
    return false;
  }
}

/// نتيجة طلب HTTP: الاستجابة أو رسالة الخطأ.
class _HttpResult {
  const _HttpResult(this.response, [this.error]);

  /// الاستجابة إن وُجدت.
  final http.Response? response;

  /// رسالة الخطأ عند الفشل.
  final String? error;
}
