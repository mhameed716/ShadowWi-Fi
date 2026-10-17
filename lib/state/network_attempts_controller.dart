import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/app_constants.dart';
import '../data/models/attempt_log.dart';
import '../data/models/wifi_network_item.dart';
import '../data/services/auto_fill_runner.dart';
import '../data/services/code_file_service.dart';
import 'logs_controller.dart';

/// يدير تجربة رموز البوابة لشبكة مختارة من تبويب «الشبكات».
///
/// تُجرَّب الرموز (من إدخال يدوي أو ملف TXT) ككلمات مرور فقط — بدون اسم
/// مستخدم — داخل Isolate منفصل مع دعم الإيقاف المؤقت والإلغاء.
class NetworkAttemptsController extends ChangeNotifier {
  NetworkAttemptsController({
    CodeFileService codeFileService = const CodeFileService(),
    LogsController? logsController,
  })  : _codeFileService = codeFileService,
        _logsController = logsController;

  final CodeFileService _codeFileService;
  final LogsController? _logsController;

  AutoFillRunner? _runner;
  StreamSubscription<AutoFillEvent>? _subscription;

  // ------------------------------------------------------------- الهدف
  /// الشبكة الآمنة المختارة.
  WifiNetworkItem? target;

  /// بوابة البوابة الحالية (تُلتقط عند فتح النافذة).
  String gatewayUrl = '';

  // ------------------------------------------------------------ المدخلات
  /// الرمز المدخل يدوياً (يُستخدم إذا لم يُختر ملف).
  String manualCode = '';

  /// ملف TXT المختار.
  CodeFile? selectedFile;

  /// هل جارٍ اختيار الملف؟
  bool pickingFile = false;

  // ------------------------------------------------------- حالة التشغيل
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

  /// هل نجحت إحدى المحاولات؟
  bool connected = false;

  /// محاولات الجلسة الحالية.
  List<AttemptLog> sessionLogs = <AttemptLog>[];

  /// رسالة خطأ آنية.
  String? error;

  /// الرموز الفعلية للتجربة: من الملف إن وُجد وإلا الرمز اليدوي.
  List<String> get effectiveCodes {
    final CodeFile? file = selectedFile;
    if (file != null && file.codes.isNotEmpty) return file.codes;
    final String manual = manualCode.trim();
    if (manual.isNotEmpty) return <String>[manual];
    return <String>[];
  }

  /// نسبة الإنجاز.
  double get progress {
    if (total <= 0) return 0;
    return (completed / total).clamp(0.0, 1.0).toDouble();
  }

  /// هل يمكن بدء التشغيل؟
  bool get canStart =>
      !running && gatewayUrl.isNotEmpty && effectiveCodes.isNotEmpty;

  /// يضبط الشبكة الهدف وبوابة البوابة.
  ///
  /// يرفض التغيير إذا كانت هناك عملية جارية على شبكة أخرى.
  bool setTarget(WifiNetworkItem network, String gateway) {
    if (running && target != null && target!.bssid != network.bssid) {
      error = 'توجد عملية جارية على شبكة أخرى — ألغها أولاً';
      notifyListeners();
      return false;
    }
    target = network;
    if (gateway.isNotEmpty || gatewayUrl.isEmpty) {
      gatewayUrl = gateway;
    }
    notifyListeners();
    return true;
  }

  /// يحدّث بوابة التجربة يدوياً — يجعل التبويب مستقلاً عن الاكتشاف التلقائي.
  void setGateway(String value) {
    if (running) return;
    gatewayUrl = value.trim();
    notifyListeners();
  }

  /// يحدّث الرمز اليدوي.
  void setManualCode(String value) {
    manualCode = value;
    notifyListeners();
  }

  /// يفتح منتقي الملفات ويحلّل الرموز.
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

  /// يبدأ حلقة التجربة التلقائية (كل رمز = كلمة مرور، بدون اسم مستخدم).
  Future<void> start() async {
    if (running) return;
    if (gatewayUrl.isEmpty) {
      error = 'لم يتم اكتشاف بوابة الشبكة — افتح تبويب «البوابة» أولاً';
      notifyListeners();
      return;
    }
    final List<String> codes = effectiveCodes;
    if (codes.isEmpty) {
      error = 'أدخل رمزاً أو اختر ملف TXT أولاً';
      notifyListeners();
      return;
    }

    running = true;
    paused = false;
    connected = false;
    completed = 0;
    total = codes.length;
    currentCode = null;
    sessionLogs = <AttemptLog>[];
    error = null;
    notifyListeners();

    try {
      _runner = await AutoFillRunner.start(
        codes: codes,
        gateway: gatewayUrl,
        username: '',
        password: '',
        destination: AppConstants.defaultDestination,
        useCodeAsUsername: false,
        allowEmptyUsername: true,
      );
      _subscription = _runner!.events.listen(_handleEvent);
    } catch (e) {
      running = false;
      error = 'تعذّر بدء التشغيل التلقائي: $e';
      notifyListeners();
    }
  }

  /// إيقاف مؤقت.
  void pause() {
    if (!running) return;
    paused = true;
    _runner?.pause();
    notifyListeners();
  }

  /// استئناف.
  void resume() {
    if (!running) return;
    paused = false;
    _runner?.resume();
    notifyListeners();
  }

  /// إلغاء الحلقة.
  Future<void> cancel() async {
    if (!running) return;
    paused = false;
    running = false;
    _runner?.cancel();
    await _cleanup();
    notifyListeners();
  }

  /// يصفّر الحالة بعد انتهاء العملية (يُستدعى عند إغلاق النافذة).
  void resetIfIdle() {
    if (running) return;
    target = null;
    manualCode = '';
    selectedFile = null;
    completed = 0;
    total = 0;
    currentCode = null;
    connected = false;
    sessionLogs = <AttemptLog>[];
    notifyListeners();
  }

  Future<void> _cleanup() async {
    await _subscription?.cancel();
    _subscription = null;
    await _runner?.dispose();
    _runner = null;
  }

  void _handleEvent(AutoFillEvent event) {
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
        _appendLog(
          success: event.success ?? false,
          message: event.message ?? '',
          code: event.code ?? '',
          statusCode: event.statusCode,
          durationMs: event.durationMs ?? 0,
        );
        notifyListeners();
        break;
      case AutoFillEventType.succeeded:
        connected = true;
        notifyListeners();
        break;
      case AutoFillEventType.finished:
      case AutoFillEventType.cancelled:
        running = false;
        paused = false;
        currentCode = null;
        notifyListeners();
        _cleanup();
        break;
      case AutoFillEventType.failed:
        running = false;
        paused = false;
        error = event.message;
        notifyListeners();
        _cleanup();
        break;
    }
  }

  void _appendLog({
    required bool success,
    required String message,
    required String code,
    int? statusCode,
    int durationMs = 0,
  }) {
    final AttemptLog log = AttemptLog(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      timestamp: DateTime.now(),
      gateway: gatewayUrl,
      username: '',
      success: success,
      message: 'شبكة: ${target?.displayName ?? '-'} — $message',
      durationMs: durationMs,
      source: AttemptSource.automatic,
      statusCode: statusCode,
    );
    sessionLogs = <AttemptLog>[log, ...sessionLogs].take(50).toList();
    _logsController?.addAttempt(log);
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
