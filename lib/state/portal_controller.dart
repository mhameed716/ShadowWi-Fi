import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/app_constants.dart';
import '../data/models/attempt_log.dart';
import '../data/models/gateway_info.dart';
import '../data/models/login_outcome.dart';
import '../data/services/auto_fill_runner.dart';
import '../data/services/code_file_service.dart';
import '../data/services/gateway_service.dart';
import '../data/services/portal_client.dart';
import 'logs_controller.dart';

/// يدير تبويب «البوابة»: الاكتشاف، الدخول اليدوي، والتشغيل التلقائي.
class PortalController extends ChangeNotifier {
  PortalController({
    required GatewayService gatewayService,
    LogsController? logsController,
    CodeFileService codeFileService = const CodeFileService(),
    PortalClient client = const PortalClient(),
  })  : _gatewayService = gatewayService,
        _logsController = logsController,
        _codeFileService = codeFileService,
        _client = client;

  final GatewayService _gatewayService;
  final LogsController? _logsController;
  final CodeFileService _codeFileService;
  final PortalClient _client;

  AutoFillRunner? _runner;
  StreamSubscription<AutoFillEvent>? _subscription;

  // ---------------------------------------------------------------- البوابة
  /// البوابة المكتشفة.
  GatewayInfo? gateway;

  /// هل جارٍ الاكتشاف؟
  bool detecting = false;

  // --------------------------------------------------------- الدخول اليدوي
  /// اسم المستخدم أو رقم الجهاز.
  String username = '';

  /// كلمة المرور أو الرمز.
  String password = '';

  /// وجهة الاتصال بعد الدخول.
  String destination = AppConstants.defaultDestination;

  /// هل جارٍ إرسال محاولة يدوية؟
  bool submitting = false;

  /// نتيجة آخر محاولة.
  LoginOutcome? lastOutcome;

  /// هل تم تسجيل الدخول بنجاح؟
  bool connected = false;

  // -------------------------------------------------------- التشغيل التلقائي
  /// الملف المختار.
  CodeFile? selectedFile;

  /// هل جارٍ اختيار الملف؟
  bool pickingFile = false;

  /// هل الحلقة تعمل؟
  bool running = false;

  /// هل الحلقة متوقفة مؤقتاً؟
  bool paused = false;

  /// عدد المحاولات المكتملة.
  int completed = 0;

  /// إجمالي عدد الرموز.
  int total = 0;

  /// الرمز قيد التجربة حالياً.
  String? currentCode;

  /// استخدام الرمز كاسم مستخدم بدل كلمة المرور.
  bool useCodeAsUsername = false;

  /// محاولات الجلسة الحالية.
  List<AttemptLog> sessionLogs = <AttemptLog>[];

  /// رسالة خطأ آنية.
  String? error;

  /// نسبة الإنجاز.
  double get progress {
    if (total <= 0) return 0;
    final double value = completed / total;
    return value.clamp(0.0, 1.0).toDouble();
  }

  /// هل يمكن تشغيل الحلقة؟
  bool get canStartAutoFill =>
      !running && selectedFile != null && gateway != null;

  /// تبدأ اكتشاف البوابة عند إقلاع التطبيق.
  Future<void> bootstrap() async {
    await detectGateway();
  }

  /// يكتشف البوابة الافتراضية.
  Future<void> detectGateway() async {
    if (detecting) return;
    detecting = true;
    notifyListeners();
    try {
      gateway = await _gatewayService.detect();
    } catch (e) {
      error = 'تعذّر اكتشاف البوابة: $e';
    } finally {
      detecting = false;
      notifyListeners();
    }
  }

  /// يحدّث اسم المستخدم.
  void setUsername(String value) {
    username = value;
    notifyListeners();
  }

  /// يحدّث كلمة المرور.
  void setPassword(String value) {
    password = value;
    notifyListeners();
  }

  /// يحدّث وجهة الاتصال.
  void setDestination(String value) {
    destination = value;
    notifyListeners();
  }

  /// يحدّث طريقة استخدام الرمز.
  void setUseCodeAsUsername(bool value) {
    useCodeAsUsername = value;
    notifyListeners();
  }

  /// يرسل محاولة دخول يدوية.
  Future<void> submitManual() async {
    final GatewayInfo? info = gateway;
    if (info == null) {
      error = 'لم يتم اكتشاف البوابة بعد';
      notifyListeners();
      return;
    }
    if (username.trim().isEmpty) {
      error = 'أدخل اسم المستخدم أو رقم الجهاز';
      notifyListeners();
      return;
    }
    if (submitting) return;

    submitting = true;
    lastOutcome = null;
    notifyListeners();

    final LoginOutcome outcome = await _client.attempt(
      baseUrl: info.baseUrl,
      username: username,
      password: password,
      destination: destination.trim().isEmpty
          ? AppConstants.defaultDestination
          : destination.trim(),
    );

    lastOutcome = outcome;
    connected = outcome.success;
    submitting = false;
    notifyListeners();

    await _recordAttempt(
      outcome: outcome,
      user: username,
      source: AttemptSource.manual,
    );
  }

  /// يختار ملف TXT ويحلّله.
  Future<void> pickFile() async {
    if (pickingFile) return;
    pickingFile = true;
    notifyListeners();
    try {
      final CodeFile? file = await _codeFileService.pickTxtFile();
      if (file == null) {
        return;
      }
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

  /// إزالة الملف المختار.
  void clearFile() {
    selectedFile = null;
    completed = 0;
    total = 0;
    currentCode = null;
    notifyListeners();
  }

  /// يبدأ الحلقة التلقائية داخل isolate منفصل.
  Future<void> startAutoFill() async {
    final CodeFile? file = selectedFile;
    final GatewayInfo? info = gateway;

    if (running) return;
    if (file == null) {
      error = 'اختر ملف TXT يحتوي على الرموز أولاً';
      notifyListeners();
      return;
    }
    if (file.codes.isEmpty) {
      error = 'الملف لا يحتوي على أي رموز صالحة';
      notifyListeners();
      return;
    }
    if (info == null) {
      error = 'اكتشف البوابة أولاً';
      notifyListeners();
      return;
    }

    running = true;
    paused = false;
    completed = 0;
    total = file.codes.length;
    currentCode = null;
    sessionLogs = <AttemptLog>[];
    error = null;
    notifyListeners();

    try {
      _runner = await AutoFillRunner.start(
        codes: file.codes,
        gateway: info.baseUrl,
        username: username.trim(),
        password: password,
        destination: destination.trim().isEmpty
            ? AppConstants.defaultDestination
            : destination.trim(),
        useCodeAsUsername: useCodeAsUsername,
      );
      _subscription = _runner!.events.listen(_handleAutoFillEvent);
    } catch (e) {
      running = false;
      error = 'تعذّر بدء التشغيل التلقائي: $e';
      notifyListeners();
    }
  }

  /// إيقاف مؤقت.
  void pauseAutoFill() {
    if (!running) return;
    paused = true;
    _runner?.pause();
    notifyListeners();
  }

  /// استئناف.
  void resumeAutoFill() {
    if (!running) return;
    paused = false;
    _runner?.resume();
    notifyListeners();
  }

  /// إلغاء الحلقة.
  Future<void> cancelAutoFill() async {
    if (!running) return;
    paused = false;
    running = false;
    await _runner?.cancel();
    await _cleanupRunner();
    notifyListeners();
  }

  Future<void> _cleanupRunner() async {
    await _subscription?.cancel();
    _subscription = null;
    await _runner?.dispose();
    _runner = null;
  }

  void _handleAutoFillEvent(AutoFillEvent event) {
    switch (event.type) {
      case AutoFillEventType.ready:
        break;
      case AutoFillEventType.attemptStarted:
        currentCode = event.code;
        notifyListeners();
        break;
      case AutoFillEventType.attemptFinished:
        completed = (event.index ?? 0) + 1;
        currentCode = event.code;
        if (event.success ?? false) {
          connected = true;
        }
        _appendSessionLog(
          success: event.success ?? false,
          message: event.message ?? '',
          username: event.code ?? '',
          statusCode: event.statusCode,
          durationMs: event.durationMs ?? 0,
        );
        notifyListeners();
        break;
      case AutoFillEventType.succeeded:
        connected = true;
        error = null;
        notifyListeners();
        break;
      case AutoFillEventType.finished:
        running = false;
        paused = false;
        currentCode = null;
        notifyListeners();
        _cleanupRunner();
        break;
      case AutoFillEventType.cancelled:
        running = false;
        paused = false;
        currentCode = null;
        notifyListeners();
        _cleanupRunner();
        break;
      case AutoFillEventType.failed:
        running = false;
        paused = false;
        error = event.message;
        notifyListeners();
        _cleanupRunner();
        break;
    }
  }

  void _appendSessionLog({
    required bool success,
    required String message,
    required String username,
    int? statusCode,
    int durationMs = 0,
  }) {
    final AttemptLog log = AttemptLog(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      timestamp: DateTime.now(),
      gateway: gateway?.baseUrl ?? '',
      username: username,
      success: success,
      message: message,
      durationMs: durationMs,
      source: AttemptSource.automatic,
      statusCode: statusCode,
    );
    sessionLogs = <AttemptLog>[log, ...sessionLogs].take(50).toList();
    _logsController?.addAttempt(log);
  }

  Future<void> _recordAttempt({
    required LoginOutcome outcome,
    required String user,
    required AttemptSource source,
  }) async {
    final AttemptLog log = AttemptLog(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      timestamp: DateTime.now(),
      gateway: gateway?.baseUrl ?? '',
      username: user,
      success: outcome.success,
      message: outcome.message,
      durationMs: outcome.durationMs,
      source: source,
      statusCode: outcome.statusCode,
    );
    sessionLogs = <AttemptLog>[log, ...sessionLogs].take(50).toList();
    await _logsController?.addAttempt(log);
  }

  /// رسالة خطأ آنية (تُستهلك مرة واحدة).
  String? takeError() {
    final String? value = error;
    error = null;
    return value;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _runner?.dispose();
    super.dispose();
  }
}
