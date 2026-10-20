// ═══════════════════════════════════════════════════════════════════════
// معمل الروتر الافتراضي — خادم بوابة دخول حقيقي (HTTP فعلي على 127.0.0.1)
// يُشغَّل داخل flutter test بلا أي إنترنت، ويقلّد أنظمة البوابات الشائعة
// حتى يُختبر محرك «البوابة التلقائية» الحقيقي ضدها كوداً بكود.
// ═══════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// أنماط الروترات الحقيقية الشائعة.
enum LabRouterMode {
  /// ميكروتك بصفحة دخول عادية (PAP): النموذج في الجذر، وPOST الفعلي إلى /login.
  mikrotikPap,

  /// ميكروتك مع تشفير CHAP: المتصفح يرسل MD5(معرف + كلمة المرور + التحدي)
  /// بدل كلمة المرور الصريحة.
  mikrotikChap,

  /// بوابة صفحتها الرئيسية ترحيبية وحالة عامة مفتوحة بلا جلسة —
  /// الفخ الكلاسيكي الذي يجعل أي حكم فضفاض يقبل كل الرموز.
  openStatusTrap,

  /// بوابة معطلة/مفتوحة تقبل أي رمز — بلاغ المستخدم الحقيقي.
  acceptsAnything,
}

/// تنفيذ MD5 مكتمل (RFC 1321) خاص بالمعمل — المدخلات Latin-1 فقط.
class LabMd5 {
  const LabMd5._();

  static String hash(String input) {
    final List<int> bytes = input.codeUnits;
    final int bitLen = bytes.length * 8;
    final List<int> msg = <int>[...bytes, 0x80];
    while (msg.length % 64 != 56) {
      msg.add(0);
    }
    for (int i = 0; i < 8; i++) {
      msg.add((bitLen >> (8 * i)) & 0xFF);
    }

    int a0 = 0x67452301;
    int b0 = 0xEFCDAB89;
    int c0 = 0x98BADCFE;
    int d0 = 0x10325476;

    for (int chunk = 0; chunk < msg.length; chunk += 64) {
      final List<int> m = List<int>.filled(16, 0);
      for (int j = 0; j < 16; j++) {
        final int base = chunk + j * 4;
        m[j] = msg[base] |
            (msg[base + 1] << 8) |
            (msg[base + 2] << 16) |
            (msg[base + 3] << 24);
      }
      int a = a0;
      int b = b0;
      int c = c0;
      int d = d0;
      for (int i = 0; i < 64; i++) {
        int f;
        int g;
        if (i < 16) {
          f = (b & c) | ((~b) & d);
          g = i;
        } else if (i < 32) {
          f = (d & b) | ((~d) & c);
          g = (5 * i + 1) % 16;
        } else if (i < 48) {
          f = b ^ c ^ d;
          g = (3 * i + 5) % 16;
        } else {
          f = c ^ (b | ((~d) & 0xFFFFFFFF));
          g = (7 * i) % 16;
        }
        f = (f + a + _k[i] + m[g]) & 0xFFFFFFFF;
        a = d;
        d = c;
        c = b;
        b = (b + _rotl(f, _s[i])) & 0xFFFFFFFF;
      }
      a0 = (a0 + a) & 0xFFFFFFFF;
      b0 = (b0 + b) & 0xFFFFFFFF;
      c0 = (c0 + c) & 0xFFFFFFFF;
      d0 = (d0 + d) & 0xFFFFFFFF;
    }

    final StringBuffer hex = StringBuffer();
    for (final int value in <int>[a0, b0, c0, d0]) {
      for (int i = 0; i < 4; i++) {
        hex.write(((value >> (8 * i)) & 0xFF).toRadixString(16).padLeft(2, '0'));
      }
    }
    return hex.toString();
  }

  static int _rotl(int x, int c) => ((x << c) | (x >> (32 - c))) & 0xFFFFFFFF;

  static const List<int> _s = <int>[
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
    5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
  ];

  static const List<int> _k = <int>[
    0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
    0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
    0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
    0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
    0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
    0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
    0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
    0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
    0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
    0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
    0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
    0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
    0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
    0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
    0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
    0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
  ];
}

/// راوتر افتراضي ببوابة دخول حقيقية يعمل على منفذ عشوائي محلي.
class LabRouter {
  LabRouter({
    required this.mode,
    required this.validCodes,
    this.noisyLoginPage = false,
  });

  final LabRouterMode mode;

  /// الرموز الصحيحة (اسم المستخدم = كلمة المرور = الرمز كعرف القسائم).
  final Set<String> validCodes;

  /// حقن ضجيج واقعي في صفحة الدخول (شيفرة JS تحوي كلمة invalid).
  final bool noisyLoginPage;

  /// تحدي CHAP الثابت (سلسلة hex 32) كما تصدره الميكروتك.
  final String challenge = 'a3f9c2e58b1d47f60e9d3c8a7b25f104';

  final List<String> log = <String>[];

  HttpServer? _server;

  String get baseUrl => 'http://127.0.0.1:${_server!.port}';

  /// هل وصل طلب دخول فعلي إلى صفحة تسجيل الدخول (/login)؟
  bool get loginPostReceived =>
      log.any((String line) => line.startsWith('POST /login '));

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((HttpRequest request) async {
      try {
        await _route(request);
      } catch (_) {
        try {
          await request.response.close();
        } catch (_) {}
      }
    });
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _route(HttpRequest request) async {
    final String path = request.uri.path;

    if (request.method == 'POST') {
      final String body = await utf8.decoder.bind(request).join();
      final Map<String, String> fields = Uri.splitQueryString(body);
      log.add('POST $path username=${fields['username'] ?? ''} '
          'password=${fields['password'] ?? ''}');
      if (path == '/login') {
        await _handleLogin(request, fields);
        return;
      }
      // السلوك الحقيقي للبوابات عند POST أعمى إلى غير وجهة النموذج: تجاهل.
      if (path == '/') {
        if (mode == LabRouterMode.openStatusTrap) {
          await _html(request, 200, _welcomePage());
        } else {
          await _html(request, 200, _loginPage());
        }
        return;
      }
      await _html(request, 404, _notFoundPage());
      return;
    }

    switch (path) {
      case '/':
        if (mode == LabRouterMode.openStatusTrap) {
          await _html(request, 200, _welcomePage());
        } else {
          await _html(request, 200, _loginPage());
        }
        return;
      case '/login':
      case '/login.html':
        await _html(request, 200, _loginPage());
        return;
      case '/status':
      case '/status.html':
        if (mode == LabRouterMode.openStatusTrap) {
          // بوابة سيئة الإعداد: لوحة الحالة عامة بلا جلسة.
          await _html(request, 200, _publicDashboard());
          return;
        }
        final String? user = _sessionUser(request);
        if (user == null) {
          await _redirect(request, '/login');
          return;
        }
        await _html(request, 200, _statusPage(user));
        return;
      case '/info.html':
      case '/logout.html':
        if (mode == LabRouterMode.openStatusTrap) {
          await _html(request, 200, _infoPage());
          return;
        }
        await _redirect(request, '/login');
        return;
      default:
        await _html(request, 404, _notFoundPage());
    }
  }

  Future<void> _handleLogin(
    HttpRequest request,
    Map<String, String> fields,
  ) async {
    final String username = (fields['username'] ?? '').trim();
    final String password = fields['password'] ?? '';

    final bool ok;
    if (mode == LabRouterMode.acceptsAnything) {
      ok = username.isNotEmpty;
    } else if (mode == LabRouterMode.mikrotikChap) {
      final String expected = chapResponse(username);
      ok = validCodes.contains(username) &&
          password.toLowerCase() == expected;
    } else {
      ok = validCodes.contains(username) && password == username;
    }

    if (ok) {
      log.add('LOGIN-OK $username');
      request.response.statusCode = 302;
      request.response.headers.set('location', '/status');
      request.response.headers.set(
        'set-cookie',
        'hotspot_session=$username-ok; path=/',
      );
      await request.response.close();
      return;
    }
    log.add('LOGIN-REJECT $username');
    await _html(request, 200, _loginPage(error: 'invalid username or password'));
  }

  /// بصمة CHAP التي يرسلها المتصفح: MD5(بايت 0xC8 + كلمة المرور + التحدي).
  String chapResponse(String username) {
    return LabMd5.hash('\u00C8' + username + challenge);
  }

  String? _sessionUser(HttpRequest request) {
    final String? cookie = request.headers.value('cookie');
    if (cookie == null) return null;
    for (final String part in cookie.split(';')) {
      final String trimmed = part.trim();
      const String prefix = 'hotspot_session=';
      if (trimmed.startsWith(prefix)) {
        final String value = trimmed.substring(prefix.length);
        if (value.endsWith('-ok')) {
          return value.substring(0, value.length - 3);
        }
      }
    }
    return null;
  }

  // ------------------------------------------------------------ الصفحات

  String _loginPage({String? error}) {
    final String errorBlock =
        error == null ? '' : '<div class="error">$error</div>';
    final String noise = noisyLoginPage
        ? "<script>function vchk(){var t='invalid voucher';return t.length;}</script>"
        : '';
    final String form;
    if (mode == LabRouterMode.mikrotikChap) {
      form = '<script src="/md5.js"></script>'
          '<form name="sendin" action="/login" method="post" style="display:none">'
          '<input type="hidden" name="username"/>'
          '<input type="hidden" name="password"/>'
          '<input type="hidden" name="dst"/>'
          '<input type="hidden" name="popup" value="true"/>'
          '</form>'
          '<script>function doLogin(){'
          'document.sendin.username.value = document.login.username.value;'
          "document.sendin.password.value = hexMD5('\\310' + "
          "document.login.password.value + '$challenge');"
          'document.sendin.submit();'
          'return false;}</script>'
          '<form name="login" action="#" onsubmit="return doLogin()">';
    } else {
      form = '<form name="login" action="/login" method="post">';
    }
    return '<!DOCTYPE html><html><head>'
        '<title>Hotspot Gateway - Login</title></head><body>'
        '$errorBlock$noise$form'
        '<input type="hidden" name="dst" value=""/>'
        '<input type="hidden" name="popup" value="true"/>'
        '<input type="text" name="username" value=""/>'
        '<input type="password" name="password" value=""/>'
        '<input type="submit" value="Connect"/>'
        '</form></body></html>';
  }

  String _welcomePage() {
    return '<!DOCTYPE html><html><head><title>FastNet Hotspot</title></head>'
        '<body><h1>Welcome to FastNet</h1>'
        '<p>Your gateway is ready. Please open the voucher page to enter '
        'your code.</p></body></html>';
  }

  String _publicDashboard() {
    return '<!DOCTYPE html><html><head><title>FastNet Dashboard</title>'
        '</head><body><h1>Dashboard</h1>'
        '<p>Time used: 00:00. Data used: 0 MB.</p></body></html>';
  }

  String _infoPage() {
    return '<!DOCTYPE html><html><head><title>Info</title></head>'
        '<body><p>Hotspot information page.</p></body></html>';
  }

  String _statusPage(String user) {
    return '<!DOCTYPE html><html><head><title>Status</title></head>'
        '<body><h1>Status</h1><p>user: $user</p>'
        '<p>time left: 60m</p></body></html>';
  }

  String _notFoundPage() {
    return '<!DOCTYPE html><html><head><title>404</title></head>'
        '<body><p>not found</p></body></html>';
  }

  // ------------------------------------------------------------ أدوات

  Future<void> _html(HttpRequest request, int status, String body) async {
    request.response.statusCode = status;
    request.response.headers.contentType =
        ContentType('text', 'html', charset: 'utf-8');
    request.response.write(body);
    await request.response.close();
  }

  Future<void> _redirect(HttpRequest request, String location) async {
    request.response.statusCode = 302;
    request.response.headers.set('location', location);
    await request.response.close();
  }
}
