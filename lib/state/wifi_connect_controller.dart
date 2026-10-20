import 'package:flutter/foundation.dart';

import '../data/models/attempt_log.dart';
import '../data/models/wifi_network_item.dart';
import '../data/services/code_file_service.dart';
import '../data/services/permission_service.dart';
import '../data/services/wifi_connect_service.dart';
import '../data/services/wifi_scan_service.dart';
import 'logs_controller.dart';

/// يدير الاتصال الحقيقي بشبكة واي فاي — كما في تطبيق إعدادات أندرويد.
///
/// - محاولة واحدة بكلمة مرور يدوية (زر «اتصال»).
/// - حلقة تلقائية تجرب رموز ملف TXT عبر محاولات اتصال حقيقية متتالية،
///   وتتحقق من الحالة الفعلية للاتصال بعد كل محاولة.
///
/// الحلقة تعمل على المسار الرئيسي بمهام غير حاجبة (استعلامات حالة)، فلا
/// تتجمد الواجهة؛ الاستعلامات نفسها نداءات منصة سريعة.
class WifiConnectController extends ChangeNotifier {
  WifiConnectController({
    required WifiConnectService service,
    LogsController? logsController,
    CodeFileService codeFileService = const CodeFileService(),
    WifiScanService? scanService,
  })  : _service = service,
        _logsController = logsController,
        _codeFileService = codeFileService,
        _scanService = scanService;

  final WifiConnectService _service;
  final LogsController? _logsController;
  final CodeFileService _codeFileService;
  final WifiScanService? _scanService;

  // ------------------------------------------------------------- الهدف
  /// اسم الشبكة المستهدفة.
  String ssid = '';

  /// هل الشبكة WPA3 (يحدد مسار كلمة المرور في المنصة)؟
  bool wpa3 = false;

  // ------------------------------------------------------------ المدخلات
  /// كلمة المرور اليدوية.
  String manualPassword = '';

  /// ملف TXT المختار للحلقة التلقائية.
  CodeFile? selectedFile;

  /// هل جارٍ اختيار الملف؟
  bool pickingFile = false;

  // ------------------------------------------------------- حالة التشغيل
  /// هل هناك محاولة/حلقة جارية؟
  bool running = false;

  /// هل الحلقة متوقفة مؤقتاً؟
  bool paused = false;

  /// طلب إلغاء صادر من المستخدم.
  bool _cancelRequested = false;

  /// عدد المحاولات المنتهية.
  int completed = 0;

  /// إجمالي الرموز في الحلقة (0 = محاولة يدوية واحدة).
  int total = 0;

  /// الرمز الحالي قيد التجربة.
  String? currentCode;

  /// هل تم الاتصال فعلاً بالشبكة؟
  bool connected = false;

  /// اسم الشبكة المتصل بها عند النجاح (لتأكيد المستخدم).
  String? connectedSsid;

  /// هل انتهت كل المحاولات دون نجاح؟
  bool exhausted = false;

  /// هل هناك مانع نظامي يمنع الاقتران (الواي فاي/الموقع مغلق)؟
  /// الواجهة تعرض أزرار الإصلاح المباشر ويتوقف تكرار المحاولات.
  bool needsSystemFix = false;

  /// محاولات الجلسة.
  List<AttemptLog> sessionLogs = <AttemptLog>[];

  /// رسالة خطأ/حالة آنية.
  String? error;

  /// الرموز الفعلية للتجربة: من الملف إن وُجد وإلا الرمز اليدوي.
  List<String> get effectiveCodes {
    final CodeFile? file = selectedFile;
    if (file != null && file.codes.isNotEmpty) return file.codes;
    final String manual = manualPassword.trim();
    if (manual.isNotEmpty) return <String>[manual];
    return <String>[];
  }

  /// نسبة الإنجاز.
  double get progress {
    if (total <= 0) return 0;
    return (completed / total).clamp(0.0, 1.0).toDouble();
  }

  /// هل يمكن بدء الاتصال اليدوي؟
  bool get canConnect =>
      !running && ssid.isNotEmpty && manualPassword.trim().isNotEmpty;

  /// هل يمكن بدء الحلقة التلقائية؟ (ملف برموز أو أكثر من رمز يدوي)
  bool get canStartLoop {
    if (running || ssid.isEmpty) return false;
    final CodeFile? file = selectedFile;
    if (file != null && file.codes.isNotEmpty) return true;
    return effectiveCodes.length > 1;
  }

  /// يضبط الشبكة المستهدفة.
  void setTarget(String networkSsid, {bool isWpa3 = false}) {
    if (running) return;
    ssid = networkSsid;
    wpa3 = isWpa3;
    connected = false;
    connectedSsid = null;
    exhausted = false;
    needsSystemFix = false;
    completed = 0;
    total = 0;
    currentCode = null;
    error = null;
    notifyListeners();
  }

  /// يحدّث كلمة المرور اليدوية.
  void setPassword(String value) {
    manualPassword = value;
    notifyListeners();
  }

  /// يفتح منتقي ملف TXT ويقرأ الرموز.
  Future<void> pickFile() async {
    if (pickingFile || running) return;
    pickingFile = true;
    notifyListeners();
    try {
      final CodeFile? file = await _codeFileService.pickTxtFile();
      if (file == null) return;
      selectedFile = file;
      if (file.codes.isEmpty) {
        error = 'الملف لا يحتوي على أي رموز صالحة';
      }
    } catch (e) {
      error = 'تعذّر قراءة الملف: $e';
    } finally {
      pickingFile = false;
      notifyListeners();
    }
  }

  /// يزيل الملف المختار.
  void clearFile() {
    if (running) return;
    selectedFile = null;
    notifyListeners();
  }

  /// عدد الكلمات المكررة بالضبط في الملف (بعد تقليم المسافات،
  /// مع تجاهل الأسطر الفارغة) — الكلمات المختلفة حروفاً ليست مكررة.
  int get duplicateCount {
    final CodeFile? file = selectedFile;
    if (file == null) return 0;
    final Set<String> seen = <String>{};
    int duplicates = 0;
    for (final String raw in file.codes) {
      final String code = raw.trim();
      if (code.isEmpty) continue;
      if (!seen.add(code)) duplicates++;
    }
    return duplicates;
  }

  /// حذف الكلمات المكررة بالضبط مع إبقاء نسخة واحدة من كل كلمة —
  /// تجربة نفس الكلمة مرتين هدر صرف، والراوتر لا يغيّر كلمته بين
  /// سطرين من الملف. الكلمات المختلفة حروفاً تبقى كلها.
  void dedupeCodes() {
    if (running) return;
    final CodeFile? file = selectedFile;
    if (file == null) return;
    final Set<String> seen = <String>{};
    final List<String> unique = <String>[];
    for (final String raw in file.codes) {
      final String code = raw.trim();
      if (code.isEmpty) continue;
      if (seen.add(code)) unique.add(code);
    }
    final int before = file.codes.length;
    selectedFile = CodeFile(
      path: file.path,
      name: file.name,
      codes: unique,
    );
    final int removed = before - unique.length;
    error = removed > 0
        ? 'حُذفت $removed كلمة مكررة — بقيت ${unique.length} كلمة فريدة'
        : 'لا توجد كلمات مكررة — الملف نظيف (${unique.length} كلمة)';
    notifyListeners();
  }

  /// محاولة اتصال واحدة بكلمة المرور اليدوية (مثل نافذة أندرويد).
  Future<void> connectOnce() async {
    if (running) return;
    final String password = manualPassword.trim();
    if (ssid.isEmpty) {
      error = 'لم تُحدَّد الشبكة';
      notifyListeners();
      return;
    }
    if (password.isEmpty) {
      error = 'أدخل كلمة مرور الشبكة';
      notifyListeners();
      return;
    }

    // الأذونات اللازمة للاتصال (الموقع + الأجهزة القريبة على 13+) —
    // تُطلب تلقائياً إن لم تكن ممنوحة.
    await PermissionService.instance.requestScanPermissions();

    running = true;
    _cancelRequested = false;
    paused = false;
    connected = false;
    connectedSsid = null;
    exhausted = false;
    needsSystemFix = false;
    completed = 0;
    total = 1;
    currentCode = password;
    error = null;
    notifyListeners();

    final bool ok = await _attempt(password, isSingle: true);

    running = false;
    currentCode = null;
    if (!ok && !_cancelRequested) {
      exhausted = true;
      if (!needsSystemFix) {
        error =
            'فشل الاتصال بهذه الكلمة — تحقق منها أو جرّب الحلقة التلقائية';
      }
    }
    notifyListeners();
  }

  /// الحلقة التلقائية: تجربة رموز الملف عبر اتصالات حقيقية متتالية.
  Future<void> startLoop() async {
    if (running) return;
    final List<String> codes = effectiveCodes;
    if (ssid.isEmpty) {
      error = 'لم تُحدَّد الشبكة';
      notifyListeners();
      return;
    }
    if (codes.isEmpty) {
      error = 'أدخل كلمة مرور أو اختر ملف TXT';
      notifyListeners();
      return;
    }

    // الأذونات اللازمة للحلقة التلقائية.
    await PermissionService.instance.requestScanPermissions();

    // تدفئة فحص واحدة لبداية الحلقة — النظام يخزّن لمح الشبكة
    // فيتصل بالاقتراحات دون انتظار دورة فحص خلفية بطيئة.
    final WifiScanService? warmer = _scanService;
    if (warmer != null) {
      try {
        await warmer.scan();
      } catch (_) {
        // الفحص المقيّد زمنياً ليس شرطاً — النظام يفحص دورياً.
      }
    }

    running = true;
    _cancelRequested = false;
    paused = false;
    connected = false;
    connectedSsid = null;
    exhausted = false;
    needsSystemFix = false;
    completed = 0;
    total = codes.length;
    currentCode = null;
    error = null;
    notifyListeners();

    for (int index = 0; index < codes.length; index++) {
      await _waitWhilePaused();
      if (_cancelRequested) break;

      final String code = codes[index];
      currentCode = code;
      notifyListeners();

      final bool ok = await _attempt(code);
      completed = index + 1;
      notifyListeners();

      if (ok) break;

      // مانع نظامي (واي فاي/موقع مغلق) — التكرار بلا فائدة حتى الإصلاح،
      // فنتوقف فوراً ونعرض أزرار الإصلاح بدل استهلاك بقية الرموز.
      if (needsSystemFix) break;
    }

    running = false;
    currentCode = null;
    if (!connected && !_cancelRequested && !needsSystemFix) {
      exhausted = true;
      error = 'انتهت كل الرموز دون اتصال — تحقق من ملف الرموز أو نطاق الشبكة';
    }
    notifyListeners();
  }

  /// إيقاف مؤقت.
  void pause() {
    if (!running) return;
    paused = true;
    notifyListeners();
  }

  /// استئناف.
  void resume() {
    if (!running) return;
    paused = false;
    notifyListeners();
  }

  /// إلغاء المحاولة/الحلقة.
  void cancel() {
    if (!running) return;
    _cancelRequested = true;
    paused = false;
    notifyListeners();
  }

  /// يفتح إعدادات الواي فاي في النظام.
  Future<void> openWifiSettings() async {
    await _service.openWifiSettings();
  }

  /// يفتح إعدادات الموقع (الشرط النظامي للاقتران على أندرويد).
  Future<void> openLocationSettings() async {
    await _service.openLocationSettings();
  }

  /// يفتح لوحة الواي فاي الرسمية — الاتصال المضمون بضغطة من النظام.
  Future<void> openWifiPanel() async {
    await _service.openWifiPanel();
  }

  /// يصفّر الحالة بعد إغلاق النافذة (إن لم يكن هناك عمل جارٍ).
  void resetIfIdle() {
    if (running) return;
    ssid = '';
    wpa3 = false;
    manualPassword = '';
    selectedFile = null;
    completed = 0;
    total = 0;
    currentCode = null;
    connected = false;
    connectedSsid = null;
    exhausted = false;
    needsSystemFix = false;
    sessionLogs = <AttemptLog>[];
    error = null;
    notifyListeners();
  }

  // ------------------------------------------------------------- الداخلية

  /// ينفّذ محاولة اتصال حقيقية واحدة ويعيد النتيجة.
  ///
  /// محاولة يدوية (أندرويد 10+): مسار WifiNetworkSpecifier — نتيجة قاطعة
  /// مع نافذة النظام «اختيار جهاز» مرة واحدة، مقبولة للمستخدم.
  /// الحلقة التلقائية (كل الأنظمة): مسار الاقتراحات/الإعداد الصامت —
  /// بلا نوافذ نظام لكل رمز، والنتيجة تُستقصى من حالة الاتصال الفعلية.
  Future<bool> _attempt(String password, {bool isSingle = false}) async {
    final Stopwatch stopwatch = Stopwatch()..start();

    final int sdk = await _service.sdkVersion();
    if (sdk >= 29 && isSingle) {
      return _attemptSpecifier(password, isSingle: isSingle, stopwatch: stopwatch);
    }
    return _attemptPersistent(password, isSingle: isSingle, stopwatch: stopwatch);
  }

  /// المسار الحاسم (أندرويد 10+).
  Future<bool> _attemptSpecifier(
    String password, {
    required bool isSingle,
    required Stopwatch stopwatch,
  }) async {
    final AttemptSource source =
        isSingle ? AttemptSource.manual : AttemptSource.automatic;

    needsSystemFix = false;

    // تدفئة الفحص قبل نافذة النظام: «اختيار جهاز» تعرض شبكات آخر فحص
    // للنظام فقط — إن كانت الشبكة غائبة عنه ظهرت النافذة فارغة بلا
    // أجهزة. نفحص من جديد ونتأكد من ظهورها، وإلا نمنع المحاولة برسالة
    // واضحة بدل إطلاق نافذة محكوم عليها بالفراغ.
    final WifiScanService? scan = _scanService;
    if (scan != null) {
      try {
        final List<WifiNetworkItem> results = await scan.scan();
        final bool visible =
            results.any((WifiNetworkItem item) => item.ssid == ssid);
        if (!visible) {
          final String message = 'الشبكة «$ssid» غير ظاهرة في الفحص الحالي — '
              'قرّب من الراوتر واسحب قائمة الشبكات للتحديث ثم أعد المحاولة';
          _appendLog(
            success: false,
            password: password,
            message: message,
            durationMs: stopwatch.elapsedMilliseconds,
            source: source,
          );
          error = message;
          notifyListeners();
          return false;
        }
      } catch (_) {
        // الفحص مقيّد زمنياً أو الأذونات لحظياً غير جاهزة — نكمل دون حجب.
      }
    }

    final SpecifierConnectResult result = await _service.connectViaSpecifier(
      ssid: ssid,
      password: password,
      wpa3: wpa3,
      timeoutMs: 25000,
    );

    if (result.unsupported) {
      // أجهزة نادرة لا تدعم المسار — نرجع للاقتراح + الاستقصاء.
      return _attemptPersistent(password, isSingle: isSingle, stopwatch: stopwatch);
    }

    if (result.connected) {
      // المنصة حفظت الشبكة كاقتراح قبل تحرير الاتصال — انتقال سلس.
      _appendLog(
        success: true,
        password: password,
        message: 'تم الاتصال بالشبكة فعلياً وحُفظت',
        durationMs: stopwatch.elapsedMilliseconds,
        source: source,
      );
      connected = true;
      connectedSsid = ssid;
      return true;
    }

    // رسالة دقيقة حسب السبب: نافذة تأكيد النظام، الموقع مغلق، واي فاي مغلق...
    final String message =
        WifiConnectService.specifierFailureMessage(result.reason);
    _appendLog(
      success: false,
      password: password,
      message: message,
      durationMs: stopwatch.elapsedMilliseconds,
      source: source,
    );

    if (result.needsSystemFix || result.reason == 'declined') {
      // واي فاي/موقع مغلق أو أُلغيت نافذة النظام — التكرار بلا فائدة الآن.
      needsSystemFix = true;
      error = message;
      notifyListeners();
    }
    return false;
  }

  /// المسار الصامت مع استقصاء الحالة: اقتراح على 10+ وإعداد كامل على 9-.
  Future<bool> _attemptPersistent(
    String password, {
    required bool isSingle,
    required Stopwatch stopwatch,
  }) async {
    final AttemptSource source =
        isSingle ? AttemptSource.manual : AttemptSource.automatic;

    final WifiConnectResult result = await _service.connect(
      ssid: ssid,
      password: password,
      wpa3: wpa3,
    );

    if (result.mode == 'error') {
      _appendLog(
        success: false,
        password: password,
        message: result.message ?? 'فشل طلب الاتصال',
        durationMs: stopwatch.elapsedMilliseconds,
        source:
            isSingle ? AttemptSource.manual : AttemptSource.automatic,
      );
      error = result.message ?? 'فشل طلب الاتصال';
      notifyListeners();
      return false;
    }

    // طور التصفية: لا نرث ارتباط المحاولة السابقة — ننتظر انقضائه،
    // وإن تبيّن اتصال فعلي متأخر نعتبرها نجاحاً فورياً.
    for (int clear = 0; clear < 5; clear++) {
      if (await _service.isConnectedTo(ssid)) {
        connected = true;
        connectedSsid = ssid;
        _appendLog(
          success: true,
          password: password,
          message: 'تأكد الاتصال بالشبكة (تأكيد متأخر)',
          durationMs: stopwatch.elapsedMilliseconds,
          source: source,
        );
        return true;
      }
      final String clearing = await _service.supplicantState();
      if (!WifiConnectService.isLinkState(clearing)) break;
      await Future<void>.delayed(WifiConnectService.pollInterval);
    }

    // ننتظر تأكيد الاتصال الفعلي من المنصة — مع كشف مبكر للانفصال بعد
    // الارتباط (توقيع الكلمة الخاطئة الحقيقي) لتسريع تقدّم الحلقة دون
    // أي مساس بنجاح الكلمة الصحيحة (المهلة الكاملة تبقى حدّاً أقصى).
    bool sawLink = false;
    int regressions = 0;
    final int maxPolls =
        (WifiConnectService.connectTimeout.inMilliseconds /
                WifiConnectService.pollInterval.inMilliseconds)
            .ceil();

    for (int poll = 0; poll < maxPolls; poll++) {
      await Future<void>.delayed(WifiConnectService.pollInterval);

      // تجاوب فوري مع الإيقاف المؤقت والإلغاء بين الاستعلامات.
      while (paused && !_cancelRequested) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      if (_cancelRequested) {
        _appendLog(
          success: false,
          password: password,
          message: 'أُلغيت المحاولة',
          durationMs: stopwatch.elapsedMilliseconds,
          source: isSingle ? AttemptSource.manual : AttemptSource.automatic,
        );
        return false;
      }

      if (await _service.isConnectedTo(ssid)) {
        connected = true;
        connectedSsid = ssid;
        _appendLog(
          success: true,
          password: password,
          message: 'تم الاتصال بالشبكة بنجاح',
          durationMs: stopwatch.elapsedMilliseconds,
          source: isSingle ? AttemptSource.manual : AttemptSource.automatic,
        );
        return true;
      }

      // كشف الفشل المبكر: مرور بالمصادقة ثم الارتداد = كلمة خاطئة
      // (الاقتران الصحيح لا يرتد). قراءتان متتاليتان للارتداد تكفيان.
      final String supplicantState = await _service.supplicantState();
      if (WifiConnectService.isLinkState(supplicantState)) {
        sawLink = true;
        regressions = 0;
      } else if (WifiConnectService.authRegressionObserved(
        state: supplicantState,
        sawLink: sawLink,
      )) {
        regressions++;
        if (regressions >= 2) {
          _appendLog(
            success: false,
            password: password,
            message: 'انفصل بعد الارتباط — الكلمة غير صحيحة (اكتشاف مبكر)',
            durationMs: stopwatch.elapsedMilliseconds,
            source: source,
          );
          return false;
        }
      } else {
        regressions = 0;
      }
    }

    _appendLog(
      success: false,
      password: password,
      message: 'لم يتم الاتصال — الكلمة غير صحيحة أو الشبكة بعيدة',
      durationMs: stopwatch.elapsedMilliseconds,
      source: source,
    );
    return false;
  }

  Future<void> _waitWhilePaused() async {
    while (paused && !_cancelRequested) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  void _appendLog({
    required bool success,
    required String password,
    required String message,
    required int durationMs,
    required AttemptSource source,
  }) {
    final AttemptLog log = AttemptLog(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      timestamp: DateTime.now(),
      gateway: 'wifi://$ssid',
      username: password,
      success: success,
      message: 'شبكة: $ssid — $message',
      durationMs: durationMs,
      source: source,
    );
    sessionLogs = <AttemptLog>[log, ...sessionLogs].take(50).toList();
    _logsController?.addAttempt(log);
  }

  /// رسالة آنية (تُستهلك مرة واحدة).
  String? takeError() {
    final String? value = error;
    error = null;
    return value;
  }

  @override
  void dispose() {
    super.dispose();
  }
}
