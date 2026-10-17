import 'dart:async';
import 'dart:isolate';

import '../models/login_outcome.dart';
import 'portal_client.dart';

/// أنواع أحداث التشغيل التلقائي.
enum AutoFillEventType {
  /// جاهز لاستقبال أوامر الإيقاف المؤقت.
  ready,

  /// بداية محاولة.
  attemptStarted,

  /// نهاية محاولة.
  attemptFinished,

  /// نجاح أحد الرموز.
  succeeded,

  /// انتهاء القائمة بأكملها.
  finished,

  /// إلغاء يدوي.
  cancelled,

  /// خطأ غير متوقع.
  failed,
}

/// حدث واحد أثناء التشغيل التلقائي.
class AutoFillEvent {
  const AutoFillEvent({
    required this.type,
    this.index,
    this.total,
    this.code,
    this.success,
    this.message,
    this.statusCode,
    this.durationMs,
  });

  /// نوع الحدث.
  final AutoFillEventType type;

  /// رقم المحاولة (يبدأ من صفر).
  final int? index;

  /// إجمالي عدد الرموز.
  final int? total;

  /// الرمز المستخدم في المحاولة.
  final String? code;

  /// هل نجحت المحاولة؟
  final bool? success;

  /// رسالة النتيجة.
  final String? message;

  /// رمز HTTP المُعاد.
  final int? statusCode;

  /// مدة المحاولة.
  final int? durationMs;
}

/// يشغّل حلقة المحاولات داخل Isolate منفصل مع دعم الإيقاف المؤقت والإلغاء.
class AutoFillRunner {
  AutoFillRunner._(this._isolate, this._eventsPort) {
    _eventsPort.listen(_handleMessage);
  }

  final Isolate _isolate;
  final ReceivePort _eventsPort;

  final StreamController<AutoFillEvent> _controller =
      StreamController<AutoFillEvent>.broadcast();

  SendPort? _commandPort;
  bool _disposed = false;
  bool _cancelled = false;

  /// تدفق الأحداث.
  Stream<AutoFillEvent> get events => _controller.stream;

  /// هل انتهى التشغيل؟
  bool get isFinished => _disposed;

  /// يبدأ تشغيلاً جديداً في isolate منفصل.
  static Future<AutoFillRunner> start({
    required List<String> codes,
    required String gateway,
    required String username,
    required String password,
    required String destination,
    bool useCodeAsUsername = false,
  }) async {
    final ReceivePort eventsPort = ReceivePort();
    final ReceivePort exitPort = ReceivePort();
    final ReceivePort errorPort = ReceivePort();

    final Map<String, dynamic> payload = <String, dynamic>{
      'events': eventsPort.sendPort,
      'codes': codes,
      'gateway': gateway,
      'username': username,
      'password': password,
      'destination': destination,
      'useCodeAsUsername': useCodeAsUsername,
    };

    final Isolate isolate = await Isolate.spawn<Map<String, dynamic>>(
      _workerMain,
      payload,
      debugName: 'shadowwifi-autofill',
      errorsAreFatal: true,
      onExit: exitPort.sendPort,
      onError: errorPort.sendPort,
    );

    final AutoFillRunner runner = AutoFillRunner._(isolate, eventsPort);

    exitPort.listen((dynamic _) {
      if (!runner._cancelled) {
        runner._emit(const AutoFillEvent(type: AutoFillEventType.finished));
      }
      runner._close();
    });

    errorPort.listen((dynamic error) {
      runner._emit(
        AutoFillEvent(
          type: AutoFillEventType.failed,
          message: 'خطأ في العملية الخلفية: $error',
        ),
      );
    });

    return runner;
  }

  /// إيقاف مؤقت بعد انتهاء المحاولة الحالية.
  void pause() => _commandPort?.send('pause');

  /// استئناف التنفيذ.
  void resume() => _commandPort?.send('resume');

  /// إلغاء التنفيذ.
  void cancel() => _commandPort?.send('cancel');

  /// إغلاق: يوقف الـ isolate ويحرر الموارد.
  Future<void> dispose() async {
    if (_disposed) return;
    _commandPort?.send('cancel');
    _isolate.kill(priority: Isolate.immediate);
    _close();
  }

  void _close() {
    if (_disposed) return;
    _disposed = true;
    _eventsPort.close();
    _controller.close();
  }

  void _emit(AutoFillEvent event) {
    if (_controller.isClosed) return;
    _controller.add(event);
  }

  void _handleMessage(dynamic message) {
    if (message is SendPort) {
      _commandPort = message;
      _emit(const AutoFillEvent(type: AutoFillEventType.ready));
      return;
    }
    if (message is! Map) return;

    final Object? type = message['type'];
    switch (type) {
      case 'attemptStarted':
        _emit(
          AutoFillEvent(
            type: AutoFillEventType.attemptStarted,
            index: message['index'] as int?,
            total: message['total'] as int?,
            code: message['code'] as String?,
          ),
        );
        break;
      case 'attemptFinished':
        _emit(
          AutoFillEvent(
            type: AutoFillEventType.attemptFinished,
            index: message['index'] as int?,
            total: message['total'] as int?,
            code: message['code'] as String?,
            success: message['success'] as bool?,
            message: message['message'] as String?,
            statusCode: message['statusCode'] as int?,
            durationMs: message['durationMs'] as int?,
          ),
        );
        break;
      case 'succeeded':
        _emit(
          AutoFillEvent(
            type: AutoFillEventType.succeeded,
            index: message['index'] as int?,
            total: message['total'] as int?,
          ),
        );
        break;
      case 'cancelled':
        _cancelled = true;
        _emit(const AutoFillEvent(type: AutoFillEventType.cancelled));
        break;
      case 'finished':
        _emit(const AutoFillEvent(type: AutoFillEventType.finished));
        break;
      default:
        break;
    }
  }
}

/// نقطة دخول الـ isolate: تقرأ الأوامر وتنفّذ المحاولات تسلسلياً.
@pragma('vm:entry-point')
void _workerMain(Map<String, dynamic> payload) {
  final SendPort events = payload['events'] as SendPort;
  final List<String> codes =
      (payload['codes'] as List<dynamic>).cast<String>();
  final String gateway = payload['gateway'] as String;
  final String username = payload['username'] as String;
  final String password = payload['password'] as String;
  final String destination = payload['destination'] as String;
  final bool useCodeAsUsername = payload['useCodeAsUsername'] as bool? ?? false;

  final ReceivePort control = ReceivePort();
  bool paused = false;
  bool cancelled = false;
  Completer<void>? resumeSignal;

  control.listen((dynamic message) {
    switch (message) {
      case 'pause':
        paused = true;
        break;
      case 'resume':
        paused = false;
        final Completer<void>? signal = resumeSignal;
        resumeSignal = null;
        if (signal != null && !signal.isCompleted) signal.complete();
        break;
      case 'cancel':
        cancelled = true;
        final Completer<void>? signal = resumeSignal;
        resumeSignal = null;
        if (signal != null && !signal.isCompleted) signal.complete();
        break;
      default:
        break;
    }
  });

  // إخبار الـ isolate الرئيسي بوجود قناة تحكم.
  events.send(control.sendPort);

  final PortalClient client = const PortalClient();

  Future<void> run() async {
    for (int index = 0; index < codes.length; index++) {
      if (cancelled) break;

      while (paused && !cancelled) {
        resumeSignal = Completer<void>();
        await resumeSignal!.future;
      }
      if (cancelled) break;

      final String code = codes[index];

      events.send(<String, dynamic>{
        'type': 'attemptStarted',
        'index': index,
        'total': codes.length,
        'code': code,
      });

      LoginOutcome outcome;
      try {
        outcome = await client.attempt(
          baseUrl: gateway,
          username: useCodeAsUsername ? code : username,
          password: useCodeAsUsername ? password : code,
          destination: destination,
        );
      } catch (error) {
        outcome = LoginOutcome(
          success: false,
          message: 'خطأ أثناء المحاولة: $error',
        );
      }

      events.send(<String, dynamic>{
        'type': 'attemptFinished',
        'index': index,
        'total': codes.length,
        'code': code,
        'success': outcome.success,
        'message': outcome.message,
        'statusCode': outcome.statusCode,
        'durationMs': outcome.durationMs,
      });

      if (outcome.success) {
        events.send(<String, dynamic>{
          'type': 'succeeded',
          'index': index,
          'total': codes.length,
        });
        break;
      }
    }

    events.send(<String, dynamic>{
      'type': cancelled ? 'cancelled' : 'finished',
      'total': codes.length,
    });

    control.close();
  }

  run();
}
