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
      // لا استجابة = غير حاسم (الشبكة تراوغ) — يستحق إعادة المحاولة
      // بدل الحكم بالفشل زوراً.
      return LoginOutcome(
        success: false,
        inconclusive: true,
        message: result.error ?? 'لا استجابة من البوابة — ستعاد المحاولة',
        durationMs: stopwatch.elapsedMilliseconds,
      );
    }

    final http.Response response = result.response!;

    stopwatch.stop();
    final String body = response.body;
    final String? title = extractTitle(body);
    final String lowered = body.toLowerCase();

    // ═══ معيار الحكم: استجابة الراوتر نفسها (لا إنترنت ولا DNS) ═══
    // يعمل مع الروترات المتصلة بالإنترنت ذات صفحات الدخول — حيث يكون
    // فحص الإنترنت عاجزاً لأنه كان مفتوحاً أصلاً قبل إدخال الرمز.

    // 1) رفض صريح بعلامة مؤكدة.
    if (_containsAny(lowered, _failureMarkers)) {
      return LoginOutcome(
        success: false,
        message: 'رُفض الرمز — أعادت البوابة رسالة رفض صريحة',
        statusCode: response.statusCode,
        finalUrl: response.request?.url.toString(),
        pageTitle: title,
        durationMs: stopwatch.elapsedMilliseconds,
      );
    }

    // 2) قبول صريح بعلامة تحوّل حقيقية.
    if (_containsAny(lowered, _successMarkers)) {
      return LoginOutcome(
        success: true,
        message: 'أكدت البوابة قبول الرمز',
        statusCode: response.statusCode,
        finalUrl: response.request?.url.toString(),
        pageTitle: title,
        durationMs: stopwatch.elapsedMilliseconds,
      );
    }

    // 3) عادت صفحة الدخول نفسها = رفض قاطع (سلوك البوابات الموحد).
    if (looksLikeLoginPage(body) ||
        (title != null && title.toLowerCase().contains('login'))) {
      return LoginOutcome(
        success: false,
        message: 'أعادت البوابة صفحة الدخول — الرمز مرفوض',
        statusCode: response.statusCode,
        finalUrl: response.request?.url.toString(),
        pageTitle: title,
        durationMs: stopwatch.elapsedMilliseconds,
      );
    }

    // 4) الصفحة تغيّرت: نستشير صفحة حالة الراوتر للحسم النهائي.
    final bool? statusOpen = await probeStatusOpen(base);
    if (statusOpen == true) {
      return LoginOutcome(
        success: true,
        message: 'صفحة حالة الراوتر فُتحت — قبول مؤكد',
        statusCode: response.statusCode,
        finalUrl: response.request?.url.toString(),
        pageTitle: title,
        durationMs: stopwatch.elapsedMilliseconds,
      );
    }
    if (statusOpen == false) {
      return LoginOutcome(
        success: false,
        message: 'صفحة الحالة ما زالت مقفلة — الرمز مرفوض',
        statusCode: response.statusCode,
        finalUrl: response.request?.url.toString(),
        pageTitle: title,
        durationMs: stopwatch.elapsedMilliseconds,
      );
    }

    // 5) لا دليل قطعي من صفحة الحالة: تغيّرت الاستجابة بعد الرمز —
    // قبول مرجّح (الرفض المعروف يعيد صفحة الدخول ولم يُعد).
    return LoginOutcome(
      success: true,
      message: 'تغيّرت استجابة البوابة بعد الرمز — قبول مرجّح',
      statusCode: response.statusCode,
      finalUrl: response.request?.url.toString(),
      pageTitle: title,
      durationMs: stopwatch.elapsedMilliseconds,
    );
  }

  /// هل يشبه النص صفحة تسجيل دخول (نموذج + حقل كلمة مرور)؟
  static bool looksLikeLoginPage(String body) {
    final String lowered = body.toLowerCase();
    final bool hasPassword = lowered.contains('type="password"') ||
        lowered.contains("type='password'") ||
        lowered.contains('name="password"') ||
        lowered.contains("name='password'");
    if (!hasPassword) return false;
    return lowered.contains('<form') || lowered.contains('login');
  }

  /// مسارات صفحات حالة الروترات الشائعة.
  static const List<String> _statusPaths = <String>[
    '/status',
    '/status.html',
    '/user/status.html',
    '/logout.html',
    '/info.html',
  ];

  /// يفحص هل صفحة حالة الراوتر مفتوحة (دليل جلسة نشطة بعد قبول الرمز).
  /// true = فُتحت بلا نموذج دخول، false = ما زالت مقفلة، null = لا دليل.
  Future<bool?> probeStatusOpen(String baseUrl) async {
    final String base = normalizeBase(baseUrl);
    if (base.isEmpty) return null;
    for (final String path in _statusPaths) {
      try {
        final http.Request request = http.Request(
          'GET',
          Uri.parse('$base$path'),
        )..followRedirects = false;
        final http.StreamedResponse streamed =
            await request.send().timeout(const Duration(seconds: 4));
        final http.Response response =
            await http.Response.fromStream(streamed);
        final int code = response.statusCode;
        if (code >= 300 && code < 400) {
          final String location =
              (response.headers['location'] ?? '').toLowerCase();
          if (location.contains('login')) {
            return false;
          }
          continue;
        }
        if (code >= 200 && code < 300) {
          if (looksLikeLoginPage(response.body)) {
            return false;
          }
          return true;
        }
      } catch (_) {
        continue;
      }
    }
    return null;
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

  /// علامات قبول صريحة فقط — بلا كلمات فضفاضة تظهر في صفحات الدخول
  /// نفسها (حُذفت logout وerror لأنهما تلتفان على الحكم).
  static const List<String> _successMarkers = <String>[
    'logged in',
    'login success',
    'status=1',
    'you are logged in',
    'تم الاتصال',
    'تم تسجيل الدخول',
    'session active',
    'you are connected',
  ];

  static const List<String> _failureMarkers = <String>[
    'invalid',
    'incorrect',
    'wrong',
    'failed',
    'denied',
    'not authorized',
    'unauthorized',
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
