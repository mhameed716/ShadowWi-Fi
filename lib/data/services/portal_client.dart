import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../core/app_constants.dart';
import '../models/internet_check_result.dart';
import '../models/login_outcome.dart';
import 'md5_util.dart';

/// نتيجة «فاحص البوابة» — تقرير تشخيصي بالعربية للعرض في الواجهة.
class PortalInspection {
  const PortalInspection({
    required this.lines,
    this.formFound = false,
    this.chap = false,
  });

  /// أسطر التقرير.
  final List<String> lines;

  /// هل وُجد نموذج دخول؟
  final bool formFound;

  /// هل البوابة تستخدم تشفير CHAP/MD5؟
  final bool chap;
}

/// شكل نموذج مستخرج من HTML (قبل إضافة بيانات التشفير).
class _FormShape {
  _FormShape({
    required this.action,
    required this.isPost,
    required this.hidden,
    required this.usernameField,
    required this.passwordField,
    required this.submitName,
    required this.submitValue,
  });

  final Uri action;
  final bool isPost;
  final List<MapEntry<String, String>> hidden;
  final String? usernameField;
  final String? passwordField;
  final String? submitName;
  final String? submitValue;
}

/// خطة نموذج دخول مستخرجة من صفحة البوابة الحقيقية.
class _FormPlan {
  _FormPlan({
    required this.action,
    required this.isPost,
    required this.hidden,
    required this.usernameField,
    required this.passwordField,
    required this.submitName,
    required this.submitValue,
    required this.chapPrefix,
    required this.chapChallenge,
    required this.plainChap,
    required this.sourcePath,
    required this.noCache,
  });

  /// وجهة الإرسال (مطلقة).
  final Uri action;

  /// الطريقة: POST وإلا GET.
  final bool isPost;

  /// الحقول المخفية كما وردت في النموذج (تُرسل كما هي كالمتصفح).
  final List<MapEntry<String, String>> hidden;

  /// اسم حقل اسم المستخدم (إن وجد).
  final String? usernameField;

  /// اسم حقل كلمة المرور (إن وجد).
  final String? passwordField;

  /// زر الإرسال الأول (بعض البوابات تشترطه).
  final String? submitName;
  final String? submitValue;

  /// بادئة CHAP (حرف من الصفحة) — null إن لم يوجد تشفير.
  final String? chapPrefix;

  /// تحدي CHAP من الصفحة.
  final String? chapChallenge;

  /// تشفير بسيط: MD5(كلمة المرور) فقط.
  final bool plainChap;

  /// المسار الذي وُجد فيه النموذج.
  final String sourcePath;

  /// لا يُخزَّن في الكاش (CHAP: التحدي يتغير كل مرة).
  final bool noCache;

  bool get chap => chapPrefix != null || plainChap;
}

/// نتيجة إرسال النموذج مع متابعة التحويلات يدوياً.
class _SendResult {
  _SendResult({
    required this.response,
    required this.redirected,
    required this.finalUri,
    required this.cookies,
    this.error,
  });

  /// الاستجابة النهائية (null = لا استجابة).
  final http.Response? response;

  /// هل حدث تحويل 3xx في السلسلة؟
  final bool redirected;

  /// الرابط النهائي.
  final Uri finalUri;

  /// جرة الكوكيز المرجعية (تُملأ من Set-Cookie في كل خطوة).
  final Map<String, String> cookies;

  /// رسالة الخطأ إن لم تكن هناك استجابة.
  final String? error;
}

/// عميل HTTP نقي (بدون أي إضافات نظام) — محرك تسجيل الدخول الحقيقي:
/// يقرأ نموذج الصفحة، يرسل كالمتصفح (الحقول المخفية + CHAP/MD5 + الكوكيز)،
/// ويحكم من ردّ الراوتر نفسه بدليل إيجابي فقط — بلا إنترنت ولا DNS.
class PortalClient {
  const PortalClient();

  /// عميل HTTP مشترك يقبل الشهادات الذاتية — صفحات بوابات الروترات
  /// كثيراً ما تتحول إلى HTTPS بشهادة محلية يرفضها العميل الافتراضي.
  static final http.Client _httpClient = IOClient(
    HttpClient()
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true,
  );

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

  /// يتحقق من توفر الإنترنت عبر فحص 204 (خارج مسار الحكم نهائياً).
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

  // ═════════════════════════════════════════════════ تسجيل الدخول الحقيقي

  /// محاولة دخول حقيقية: قراءة نموذج الصفحة → إرسال مطابق للمتصفح →
  /// حكم من ردّ الراوتر نفسه بدليل إيجابي فقط. أي شك = غير حاسم.
  Future<LoginOutcome> attempt({
    required String baseUrl,
    required String username,
    required String password,
    required String destination,
    bool verifyInternet = false,
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
    final _FormPlan? plan = await _fetchFormPlan(base);
    if (plan == null) {
      stopwatch.stop();
      return LoginOutcome(
        success: false,
        inconclusive: true,
        message: 'تعذّر الوصول إلى نموذج الدخول — ستعاد المحاولة',
        durationMs: stopwatch.elapsedMilliseconds,
      );
    }

    final _SendResult sent =
        await _submit(plan, username.trim(), password, destination);
    stopwatch.stop();

    if (sent.response == null) {
      // لا استجابة = غير حاسم (الشبكة تراوغ) — يستحق إعادة المحاولة.
      return LoginOutcome(
        success: false,
        inconclusive: true,
        message: sent.error ?? 'لا استجابة من البوابة — ستعاد المحاولة',
        durationMs: stopwatch.elapsedMilliseconds,
      );
    }

    final http.Response response = sent.response!;
    final String body = response.body;
    final String? title = extractTitle(body);
    final String visible = _visibleText(body).toLowerCase();
    final String code = username.trim().toLowerCase();

    // ═══ سُلّم الحكم: دليل إيجابي فقط، من ردّ الراوتر نفسه ═══

    // 1) رفض صريح في النص الظاهر (بعد تجريد الشيفرة والوسوم).
    if (_containsAny(visible, _failureMarkers)) {
      return _verdict(
        success: false,
        message: 'رُفض الرمز — أعادت البوابة رسالة رفض صريحة',
        response: response,
        sent: sent,
        title: title,
        ms: stopwatch.elapsedMilliseconds,
      );
    }

    // 2) عادت صفحة الدخول نفسها = رفض قاطع (سلوك البوابات الموحد).
    final bool loginPage = looksLikeLoginPage(body) ||
        (title != null && title.toLowerCase().contains('login'));
    if (loginPage) {
      return _verdict(
        success: false,
        message: 'أعادت البوابة صفحة الدخول — الرمز مرفوض',
        response: response,
        sent: sent,
        title: title,
        ms: stopwatch.elapsedMilliseconds,
      );
    }

    // 3) قبول صريح في النص الظاهر.
    if (_containsAny(visible, _successMarkers)) {
      return _verdict(
        success: true,
        message: 'أكدت البوابة القبول صراحة',
        response: response,
        sent: sent,
        title: title,
        ms: stopwatch.elapsedMilliseconds,
      );
    }

    // 4) صفحة غير الدخول تعرض الرمز نفسه (كما تفعل صفحات الحالة).
    if (code.length >= 4 && visible.contains(code)) {
      return _verdict(
        success: true,
        message: 'صفحة الجلسة تعرض الرمز نفسه — قبول مؤكد',
        response: response,
        sent: sent,
        title: title,
        ms: stopwatch.elapsedMilliseconds,
      );
    }

    // 5) حوّلت البوابة طلب الدخول إلى صفحة أخرى (سلوك القبول المعروف).
    if (sent.redirected) {
      return _verdict(
        success: true,
        message: 'حوّلت البوابة الطلب إلى صفحة جلسة — قبول مؤكد',
        response: response,
        sent: sent,
        title: title,
        ms: stopwatch.elapsedMilliseconds,
      );
    }

    // 6) دليل الجلسة: صفحة حالة مقفلة بلا جلسة وتُفتح بكوكيز المحاولة.
    final bool? session =
        await _statusSessionEvidence(base, sent.cookies, code);
    if (session == true) {
      return _verdict(
        success: true,
        message: 'صفحة الحالة فُتحت بكوكيز الجلسة — قبول مؤكد',
        response: response,
        sent: sent,
        title: title,
        ms: stopwatch.elapsedMilliseconds,
      );
    }
    if (session == false) {
      return _verdict(
        success: false,
        message: 'صفحة الحالة ترفض كوكيز الجلسة — الرمز مرفوض',
        response: response,
        sent: sent,
        title: title,
        ms: stopwatch.elapsedMilliseconds,
      );
    }

    // 7) لا دليل قطعي — غير حاسم (لا نجاح بلا دليل أبداً).
    return LoginOutcome(
      success: false,
      inconclusive: true,
      message: 'لا دليل حاسم من البوابة — ستعاد المحاولة',
      statusCode: response.statusCode,
      finalUrl: sent.finalUri.toString(),
      pageTitle: title,
      durationMs: stopwatch.elapsedMilliseconds,
    );
  }

  LoginOutcome _verdict({
    required bool success,
    required String message,
    required http.Response response,
    required _SendResult sent,
    required String? title,
    required int ms,
  }) {
    return LoginOutcome(
      success: success,
      message: message,
      statusCode: response.statusCode,
      finalUrl: sent.finalUri.toString(),
      pageTitle: title,
      durationMs: ms,
    );
  }

  /// فاحص البوابة: تقرير تشخيصي عربي صادق — هل وصلنا للراوتر أصلاً؟
  /// وماذا ردّ كل مسار حرفياً؟ وأين النموذج إن وُجد (بعد ملاحقة
  /// التحويلات المضمّنة)؟ ثم سلوك الرفض الحقيقي برمز تمييز وهمي.
  Future<PortalInspection> inspect(String baseUrl) async {
    final String base = normalizeBase(baseUrl);
    final List<String> lines = <String>[];
    if (base.isEmpty) {
      lines.add('✗ عنوان البوابة غير صالح');
      return PortalInspection(lines: lines);
    }
    lines.add('الهدف: $base');
    bool reached = false;
    for (final String path in _formPaths) {
      final _SendResult result = await _sendWithRedirects(
        http.Request('GET', Uri.parse('$base/').resolve(path))
          ..followRedirects = false,
        <String, String>{},
        timeout: AppConstants.probeTimeout,
      );
      final http.Response? response = result.response;
      if (response == null) {
        lines.add('✗ $path : لا استجابة — ${result.error ?? 'تعذّر الاتصال'}');
        continue;
      }
      reached = true;
      final String? title = extractTitle(response.body);
      final _FormPlan? plan =
          _parseForm(response.body, result.finalUri, path);
      if (plan != null) {
        return _formReport(lines, plan, base);
      }
      lines.add('• $path : ردّ ${response.statusCode} بحجم '
          '${response.body.length} بلا نموذج دخول '
          '(العنوان: ${title ?? '—'})');
      final Uri? soft = _softRedirect(response.body, result.finalUri);
      if (soft != null) {
        lines.add('  ↳ الصفحة تحوّل بامر مضمّن إلى: $soft — أتابع...');
        final _SendResult softResult = await _sendWithRedirects(
          http.Request('GET', soft)..followRedirects = false,
          <String, String>{},
          timeout: AppConstants.probeTimeout,
        );
        final http.Response? softResponse = softResult.response;
        if (softResponse == null) {
          lines.add('  ✗ الوجهة: لا استجابة — ${softResult.error ?? ''}');
          continue;
        }
        final _FormPlan? softPlan =
            _parseForm(softResponse.body, softResult.finalUri, soft.path);
        if (softPlan != null) {
          return _formReport(lines, softPlan, base);
        }
        lines.add('  • الوجهة: ردّ ${softResponse.statusCode} بحجم '
            '${softResponse.body.length} بلا نموذج');
      }
    }
    if (!reached) {
      lines.add('══ لم يصل الاتصال إلى الراوتر نهائياً — تأكد من: ══');
      lines.add('1) الواي فاي متصل بشبكة الراوتر نفسها');
      lines.add('2) باقة الجوال (البيانات الخلوية) موقوفة أثناء الفحص');
      lines.add('3) افتح http://mobile.router في متصفح الهاتف للتأكد');
    } else {
      lines.add('══ وصلنا للبوابة لكن لا نموذج دخول مفهوم في الصفحات أعلاه ══');
      lines.add('صوّر هذه الشاشة وأرسلها — سنضيف نمط بوابتك للمعمل');
    }
    return PortalInspection(lines: lines);
  }

  /// تقرير نموذج مكتشف: تفاصيله كاملة + تجربة رفض حية برمز وهمي.
  Future<PortalInspection> _formReport(
    List<String> lines,
    _FormPlan plan,
    String base,
  ) async {
    lines.add('✓ نموذج الدخول وُجد في: ${plan.sourcePath}');
    lines.add('وجهة الإرسال: ${plan.action}');
    lines.add('الطريقة: ${plan.isPost ? 'POST' : 'GET'}');
    lines.add('حقل اسم المستخدم: ${plan.usernameField ?? '— لا يوجد'}');
    lines.add('حقل كلمة المرور: ${plan.passwordField ?? '— لا يوجد'}');
    if (plan.hidden.isNotEmpty) {
      final String hiddenList = plan.hidden
          .map((MapEntry<String, String> e) =>
              '${e.key}=${e.value.isEmpty ? '(فارغ)' : e.value}')
          .join('، ');
      lines.add('حقول مخفية تُرسل معه: $hiddenList');
    }
    if (plan.chap) {
      lines.add('✓ البوابة مشفّرة CHAP/MD5 — تُرسل بصمة الكلمة كالمتصفح تماماً');
    } else {
      lines.add('الإرسال صريح (بدون CHAP) — مثل نموذج المتصفح حرفياً');
    }
    // تجربة حية برمز تمييز وهمي لعرض سلوك الرفض الفعلي.
    final LoginOutcome outcome = await attempt(
      baseUrl: base,
      username: 'zz-inspect-9999',
      password: 'zz-inspect-9999',
      destination: '',
      allowEmptyUsername: true,
    );
    if (outcome.success) {
      lines.add('⚠ تنبيه: البوابة قَبِلَت رمزاً وهمياً — تقبل أي شيء!');
    } else if (outcome.inconclusive) {
      lines.add('⚠ سلوك الرفض غير واضح: ${outcome.message}');
    } else {
      lines.add('✓ سلوك الرفض سليم: ${outcome.message}');
    }
    return PortalInspection(lines: lines, formFound: true, chap: plan.chap);
  }

  // ------------------------------------------------------------ النموذج

  /// كاش خطط النماذج (البنية نادراً ما تتغير) — CHAP لا يُخزَّن.
  static final Map<String, _FormPlan> _planCache = <String, _FormPlan>{};

  /// مسارات البحث عن نموذج الدخول.
  static const List<String> _formPaths = <String>[
    '/',
    '/login',
    '/login.html',
  ];

  /// يكتشف تحويلاً مضمّناً في الصفحة (meta refresh أو JS location)
  /// ويعيد الهدف — كثير من صفحات البوابات تحوّل بهذه الطريقة.
  /// الاقتباسات في الأصناف تُكتب بترميز سداسي لتجنب كسر السلاسل.
  static Uri? _softRedirect(String body, Uri base) {
    final RegExpMatch? meta = RegExp(
      r'http-equiv\s*=\s*[\x22\x27]?refresh[\x22\x27]?[^>]*url\s*=\s*([^\x22\x27>\s]+)',
      caseSensitive: false,
    ).firstMatch(body);
    String? target = meta?.group(1);
    target ??= RegExp(
      r'location\.(?:href|assign|replace)\s*[(=]\s*[\x22\x27]([^\x22\x27]+)[\x22\x27]',
      caseSensitive: false,
    ).firstMatch(body)?.group(1);
    if (target == null || target.trim().isEmpty) return null;
    return base.resolve(target.trim());
  }

  /// يكتشف نموذج الدخول الحقيقي في البوابة.
  Future<_FormPlan?> _fetchFormPlan(String base) async {
    final String key = normalizeBase(base);
    if (_planCache.containsKey(key)) {
      return _planCache[key];
    }
    final Uri root = Uri.parse('$key/');
    final Map<String, String> jar = <String, String>{};
    for (final String path in _formPaths) {
      final _SendResult result = await _sendWithRedirects(
        http.Request('GET', root.resolve(path))..followRedirects = false,
        jar,
        timeout: AppConstants.probeTimeout,
      );
      final http.Response? response = result.response;
      if (response == null) continue;
      final _FormPlan? plan =
          _parseForm(response.body, result.finalUri, path);
      if (plan != null) {
        if (!plan.noCache) {
          _planCache[key] = plan;
        }
        return plan;
      }
      // الصفحة تحوّل بامر مضمّن؟ نتابع الهدف بحثاً عن النموذج.
      final Uri? soft = _softRedirect(response.body, result.finalUri);
      if (soft == null) continue;
      final _SendResult softResult = await _sendWithRedirects(
        http.Request('GET', soft)..followRedirects = false,
        jar,
        timeout: AppConstants.probeTimeout,
      );
      final http.Response? softResponse = softResult.response;
      if (softResponse == null) continue;
      final _FormPlan? softPlan =
          _parseForm(softResponse.body, softResult.finalUri, soft.path);
      if (softPlan != null) {
        if (!softPlan.noCache) {
          _planCache[key] = softPlan;
        }
        return softPlan;
      }
    }
    return null;
  }

  /// يحلل HTML ويستخرج خطة النموذج (الوجهة والحقول والتشفير).
  ///
  /// بعض البوابات (مثل قالب CHAP في ميكروتك) تحتوي نموذجاً مخفياً
  /// إضافياً كل حقوله hidden — نقيم كل النماذج ونختار الأفضل: النموذج
  /// الذي فيه حقول إدخال فعلية (نص/كلمة مرور) يغلب النموذج الميت.
  static _FormPlan? _parseForm(String html, Uri pageUri, String sourcePath) {
    final RegExp formRx =
        RegExp(r'<form\b([^>]*)>([\s\S]*?)</form>', caseSensitive: false);
    final List<RegExpMatch> forms = formRx.allMatches(html).toList();
    _FormShape? best;
    int bestScore = -1;
    for (final RegExpMatch m in forms) {
      final _FormShape? shape =
          _parseFormShape(m.group(1) ?? '', m.group(2) ?? '', pageUri);
      if (shape == null) continue;
      final int score = (shape.passwordField != null ? 2 : 0) +
          (shape.usernameField != null ? 1 : 0);
      if (score > bestScore) {
        best = shape;
        bestScore = score;
      }
    }
    if (best == null) {
      best = _parseOpenForm(html, pageUri);
    }
    // فحص مباشر قبل النسخ — إسنادات الحلقة تُسقط ترقية غير-الصفري.
    if (best == null) {
      return null;
    }
    _FormShape chosen = best;

    String? chapPrefix;
    String? chapChallenge;
    bool plainChap = false;
    final RegExp chapRx = RegExp(
      r"hexMD5\(\s*'((?:\\.|[^'])*?)'\s*\+\s*[\w.$\[\]]{0,80}password"
      r"[\w.$\[\]]{0,80}\s*\+\s*'((?:\\.|[^'])*?)'\s*\)",
      caseSensitive: false,
    );
    final RegExpMatch? chapMatch = chapRx.firstMatch(html);
    if (chapMatch != null) {
      chapPrefix = _decodeJsLiteral(chapMatch.group(1) ?? '');
      chapChallenge = _decodeJsLiteral(chapMatch.group(2) ?? '');
    } else {
      final RegExp plainRx = RegExp(
        r"hexMD5\(\s*[\w.$\[\]]{0,80}password[\w.$\[\]]{0,80}\s*\)",
        caseSensitive: false,
      );
      if (plainRx.hasMatch(html)) {
        plainChap = true;
      }
    }

    // في قوالب CHAP (ميكروتك) النموذج المرئي action="#" وعنصر نائب —
    // الإرسال الفعلي عبر نموذج مخفي تستدعيه الشيفرة document.sendin.submit().
    // نتبع نداء الإرسال إلى نموذجه ونستخدم وجهته وحقوله الحقيقية.
    if (chapPrefix != null || plainChap) {
      final RegExpMatch? submitCall =
          RegExp(r'document\.(\w+)\.submit\(\)').firstMatch(html);
      if (submitCall != null) {
        final String senderName = submitCall.group(1) ?? '';
        for (final RegExpMatch m in forms) {
          final String attrs = m.group(1) ?? '';
          if (_attr(attrs, 'name').trim().toLowerCase() ==
              senderName.toLowerCase()) {
            final _FormShape? senderShape = _parseSenderShape(
              attrs,
              m.group(2) ?? '',
              pageUri,
            );
            if (senderShape != null) {
              chosen = senderShape;
            }
            break;
          }
        }
      }
    }

    return _FormPlan(
      action: chosen.action,
      isPost: chosen.isPost,
      hidden: chosen.hidden,
      usernameField: chosen.usernameField,
      passwordField: chosen.passwordField,
      submitName: chosen.submitName,
      submitValue: chosen.submitValue,
      chapPrefix: chapPrefix,
      chapChallenge: chapChallenge,
      plainChap: plainChap,
      sourcePath: sourcePath,
      noCache: chapPrefix != null || plainChap,
    );
  }

  /// استخراج شكل نموذج واحد من سماته وداخله — null إن لم يكن صالحاً.
  static _FormShape? _parseFormShape(
    String attrs,
    String inner,
    Uri pageUri,
  ) {
    final String actionRaw = _attr(attrs, 'action').trim();
    final Uri action =
        actionRaw.isEmpty ? pageUri : pageUri.resolve(actionRaw);
    final String method = _attr(attrs, 'method').trim().toLowerCase();
    final bool isPost = method != 'get';

    final List<MapEntry<String, String>> hidden = <MapEntry<String, String>>[];
    String? passwordField;
    final List<String> textCandidates = <String>[];
    String? submitName;
    String? submitValue;

    final RegExp inputRx =
        RegExp(r'<input\b([^>]*?)/?>', caseSensitive: false);
    for (final RegExpMatch m in inputRx.allMatches(inner)) {
      final String tag = m.group(1) ?? '';
      final String type = _attr(tag, 'type').trim().toLowerCase();
      final String name = _attr(tag, 'name').trim();
      if (name.isEmpty) continue;
      final String value = _attr(tag, 'value');
      if (type == 'hidden') {
        hidden.add(MapEntry<String, String>(name, value));
      } else if (type == 'password') {
        passwordField ??= name;
      } else if (type == 'submit') {
        submitName ??= name;
        if (submitName == name) {
          submitValue = value;
        }
      } else if (type == 'text' ||
          type == 'tel' ||
          type == 'number' ||
          type == 'search' ||
          type == 'email' ||
          type.isEmpty) {
        textCandidates.add(name);
      }
    }
    final String? usernameField = _pickUsernameField(textCandidates);
    if (usernameField == null && passwordField == null) {
      return null; // نموذج ميت — بلا حقول إدخال فعلية
    }
    return _FormShape(
      action: action,
      isPost: isPost,
      hidden: hidden,
      usernameField: usernameField,
      passwordField: passwordField,
      submitName: submitName,
      submitValue: submitValue,
    );
  }

  /// احتياط: صفحة فيها وسم form بلا إغلاق — نعامل ما بعده كنموذج واحد.
  static _FormShape? _parseOpenForm(String html, Uri pageUri) {
    final RegExpMatch? open =
        RegExp(r'<form\b([^>]*)>', caseSensitive: false).firstMatch(html);
    if (open == null) return null;
    return _parseFormShape(
      open.group(1) ?? '',
      html.substring(open.end),
      pageUri,
    );
  }

  /// نموذج الإرسال المخفي في CHAP: حقوله hidden بطبيعته، والحقلان
  /// username/password يكتب فيهما المتصفح القيم قبل الإرسال.
  static _FormShape? _parseSenderShape(
    String attrs,
    String inner,
    Uri pageUri,
  ) {
    final String actionRaw = _attr(attrs, 'action').trim();
    final Uri action =
        actionRaw.isEmpty ? pageUri : pageUri.resolve(actionRaw);
    final String method = _attr(attrs, 'method').trim().toLowerCase();
    final bool isPost = method != 'get';

    final List<MapEntry<String, String>> hidden = <MapEntry<String, String>>[];
    String? usernameField;
    String? passwordField;

    final RegExp inputRx =
        RegExp(r'<input\b([^>]*?)/?>', caseSensitive: false);
    for (final RegExpMatch m in inputRx.allMatches(inner)) {
      final String tag = m.group(1) ?? '';
      final String type = _attr(tag, 'type').trim().toLowerCase();
      final String name = _attr(tag, 'name').trim();
      if (name.isEmpty) continue;
      final String value = _attr(tag, 'value');
      if (type == 'hidden' || type.isEmpty) {
        final String lowered = name.toLowerCase();
        if (lowered == 'username') {
          usernameField ??= name;
        } else if (lowered == 'password') {
          passwordField ??= name;
        } else {
          hidden.add(MapEntry<String, String>(name, value));
        }
      } else {
        hidden.add(MapEntry<String, String>(name, value));
      }
    }
    return _FormShape(
      action: action,
      isPost: isPost,
      hidden: hidden,
      usernameField: usernameField,
      passwordField: passwordField,
      submitName: null,
      submitValue: null,
    );
  }

  /// هل يشبه النص صفحة تسجيل دخول (نموذج + حقل كلمة مرور)؟
  static bool _looksPasswordField(String inner) {
    final String lowered = inner.toLowerCase();
    return lowered.contains('type="password"') ||
        lowered.contains("type='password'") ||
        lowered.contains('name="password"') ||
        lowered.contains("name='password'");
  }

  /// هل يشبه النص صفحة تسجيل دخول (نموذج + حقل كلمة مرور)؟
  static bool looksLikeLoginPage(String body) {
    if (!_looksPasswordField(body)) return false;
    final String lowered = body.toLowerCase();
    return lowered.contains('<form') || lowered.contains('login');
  }

  /// اختيار حقل اسم المستخدم بأولوية أسماء شائعة.
  static const List<String> _userHints = <String>[
    'user',
    'code',
    'login',
    'voucher',
    'auth',
    'account',
    'name',
    'card',
  ];

  static String? _pickUsernameField(List<String> candidates) {
    for (final String hint in _userHints) {
      for (final String candidate in candidates) {
        if (candidate.toLowerCase().contains(hint)) {
          return candidate;
        }
      }
    }
    return candidates.isEmpty ? null : candidates.first;
  }

  /// قراءة قيمة خاصية من وسم/سمات نموذج.
  static String _attr(String tag, String name) {
    final RegExp rx = RegExp(
      '$name\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\'|([^\\s>]+))',
      caseSensitive: false,
    );
    final RegExpMatch? m = rx.firstMatch(tag);
    if (m == null) return '';
    return (m.group(1) ?? m.group(2) ?? m.group(3) ?? '').trim();
  }

  /// فك سلسلة JS حرفية: \\310 ثماني، \\xNN سداسي، \\n و\\t وغيرها.
  static String _decodeJsLiteral(String raw) {
    final StringBuffer out = StringBuffer();
    int i = 0;
    while (i < raw.length) {
      final String ch = raw[i];
      if (ch == r'\' && i + 1 < raw.length) {
        final String next = raw[i + 1];
        if (next == 'x' && i + 3 < raw.length) {
          final int? value =
              int.tryParse(raw.substring(i + 2, i + 4), radix: 16);
          if (value != null) {
            out.writeCharCode(value);
            i += 4;
            continue;
          }
        }
        final RegExpMatch? oct =
            RegExp(r'^([0-7]{1,3})').firstMatch(raw.substring(i + 1));
        if (oct != null) {
          out.writeCharCode(int.parse(oct.group(1)!, radix: 8));
          i += 1 + oct.group(1)!.length;
          continue;
        }
        if (next == 'n') {
          out.write('\n');
        } else if (next == 'r') {
          out.write('\r');
        } else if (next == 't') {
          out.write('\t');
        } else {
          out.write(next);
        }
        i += 2;
        continue;
      }
      out.write(ch);
      i++;
    }
    return out.toString();
  }

  /// النص الظاهر فقط: بلا شيفرة ولا أنماط ولا تعليقات ولا وسوم.
  static String _visibleText(String html) {
    String text = html;
    text = text.replaceAll(RegExp(r'<!--[\s\S]*?-->'), ' ');
    text = text.replaceAll(
        RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), ' ');
    text = text.replaceAll(
        RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ');
    text = text.replaceAll(RegExp(r'<[^>]*>'), ' ');
    text = text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&#x27;', "'");
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  // ------------------------------------------------------------ الإرسال

  /// يرسل النموذج كالمتصفح: كل الحقول المخفية + اسم المستخدم + كلمة
  /// المرور (أو بصمتها في CHAP) + زر الإرسال، ثم يتبع التحويلات يدوياً
  /// مع حمل الكوكيز في كل خطوة.
  Future<_SendResult> _submit(
    _FormPlan plan,
    String username,
    String password,
    String destination,
  ) async {
    final Map<String, String> fields = <String, String>{
      for (final MapEntry<String, String> e in plan.hidden) e.key: e.value,
    };
    if (plan.usernameField != null) {
      fields[plan.usernameField!] = username;
    }
    if (plan.passwordField != null) {
      String value = password;
      if (plan.chapPrefix != null) {
        value = Md5Util.hash(plan.chapPrefix! + password + plan.chapChallenge!);
      } else if (plan.plainChap) {
        value = Md5Util.hash(password);
      }
      fields[plan.passwordField!] = value;
    }
    if (plan.submitName != null) {
      fields[plan.submitName!] = plan.submitValue ?? '';
    }
    if (destination.isNotEmpty) {
      fields['dst'] = destination;
    }

    final http.Request request;
    if (plan.isPost) {
      request = http.Request('POST', plan.action)..bodyFields = fields;
    } else {
      request =
          http.Request('GET', plan.action.replace(queryParameters: fields));
    }
    request.followRedirects = false;
    return _sendWithRedirects(
      request,
      <String, String>{},
      timeout: AppConstants.loginTimeout,
    );
  }

  /// إرسال طلب + متابعة تحويلات 3xx يدوياً (حتى 3 قفزات) بحمل الكوكيز.
  Future<_SendResult> _sendWithRedirects(
    http.Request request,
    Map<String, String> jar, {
    required Duration timeout,
  }) async {
    final Map<String, String> cookies = <String, String>{
      for (final MapEntry<String, String> e in jar.entries) e.key: e.value,
    };
    bool redirected = false;
    http.Request current = request;
    try {
      for (int hop = 0; hop < 4; hop++) {
        if (cookies.isNotEmpty) {
          final String header = cookies.keys
              .map((String k) => '$k=${cookies[k]}')
              .join('; ');
          current.headers['cookie'] = header;
        }
        final http.StreamedResponse streamed =
            await _httpClient.send(current).timeout(timeout);
        _absorbCookies(streamed.headers['set-cookie'], cookies);
        final http.Response response =
            await http.Response.fromStream(streamed);
        final int code = response.statusCode;
        if (code >= 300 && code < 400) {
          final String location = response.headers['location'] ?? '';
          if (location.isNotEmpty && hop < 3) {
            final Uri next = current.url.resolve(location);
            current = http.Request('GET', next)..followRedirects = false;
            redirected = true;
            continue;
          }
        }
        return _SendResult(
          response: response,
          redirected: redirected,
          finalUri: current.url,
          cookies: cookies,
        );
      }
      return _SendResult(
        response: null,
        redirected: redirected,
        finalUri: current.url,
        cookies: cookies,
        error: 'تجاوز حد التحويلات',
      );
    } on TimeoutException {
      return _SendResult(
        response: null,
        redirected: redirected,
        finalUri: current.url,
        cookies: cookies,
        error: 'انتهت مهلة الاتصال بالبوابة',
      );
    } on SocketException catch (error) {
      return _SendResult(
        response: null,
        redirected: redirected,
        finalUri: current.url,
        cookies: cookies,
        error: 'تعذّر الاتصال بالبوابة: ${error.message}',
      );
    } catch (error) {
      return _SendResult(
        response: null,
        redirected: redirected,
        finalUri: current.url,
        cookies: cookies,
        error: 'فشل الطلب: $error',
      );
    }
  }

  /// امتصاص ترويسة Set-Cookie (قد تكون مدموجة بفواصل).
  static void _absorbCookies(String? header, Map<String, String> jar) {
    if (header == null || header.isEmpty) return;
    for (final String piece in header.split(',')) {
      final String first = piece.split(';').first.trim();
      final int eq = first.indexOf('=');
      if (eq > 0) {
        jar[first.substring(0, eq).trim()] = first.substring(eq + 1).trim();
      }
    }
  }

  // ------------------------------------------------------------ دليل الجلسة

  /// مسارات صفحات حالة الروترات الشائعة.
  static const List<String> _statusPaths = <String>[
    '/status',
    '/status.html',
    '/user/status.html',
    '/logout.html',
    '/info.html',
  ];

  /// دليل الجلسة: المسار المفتوح بلا كوكيز ليس دليلاً؛ المقفول الذي
  /// يُفتح بكوكيز المحاولة دليل قبول، والباقي مقفولاً دليل رفض.
  Future<bool?> _statusSessionEvidence(
    String base,
    Map<String, String> jar,
    String code,
  ) async {
    final String key = normalizeBase(base);
    final Uri root = Uri.parse('$key/');
    for (final String path in _statusPaths) {
      final _SendResult bare = await _sendWithRedirects(
        http.Request('GET', root.resolve(path))..followRedirects = false,
        <String, String>{},
        timeout: const Duration(seconds: 4),
      );
      final http.Response? bareResponse = bare.response;
      final bool bareOpen = bareResponse != null &&
          bareResponse.statusCode >= 200 &&
          bareResponse.statusCode < 300 &&
          !looksLikeLoginPage(bareResponse.body);
      if (bareOpen) continue; // عامة للجميع — ليست دليلاً

      final _SendResult authed = await _sendWithRedirects(
        http.Request('GET', root.resolve(path))..followRedirects = false,
        jar,
        timeout: const Duration(seconds: 4),
      );
      final http.Response? response = authed.response;
      if (response == null) continue;
      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          !looksLikeLoginPage(response.body)) {
        return true;
      }
      return false;
    }
    return null;
  }

  // ------------------------------------------------------------ العلامات

  /// علامات قبول صريحة في النص الظاهر فقط.
  static const List<String> _successMarkers = <String>[
    'logged in',
    'login success',
    'you are logged in',
    'تم الاتصال',
    'تم تسجيل الدخول',
    'session active',
    'you are connected',
  ];

  /// علامات رفض صريحة في النص الظاهر فقط.
  static const List<String> _failureMarkers = <String>[
    'invalid',
    'incorrect',
    'wrong',
    'failed',
    'denied',
    'not authorized',
    'unauthorized',
    'غير صحيح',
    'غير صالح',
  ];

  static bool _containsAny(String haystack, List<String> needles) {
    for (final String needle in needles) {
      if (haystack.contains(needle)) return true;
    }
    return false;
  }
}
