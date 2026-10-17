import 'package:flutter/foundation.dart';

import '../data/models/diagnostics_snapshot.dart';
import '../data/services/diagnostics_service.dart';

/// manages تبويب التشخيص.
class DiagnosticsController extends ChangeNotifier {
  DiagnosticsController(this._service);

  final DiagnosticsService _service;

  /// آخر نتيجة تشخيص.
  DiagnosticsSnapshot? snapshot;

  /// هل جارٍ التنفيذ؟
  bool running = false;

  /// رسالة خطأ آنية.
  String? error;

  /// ينفّذ فحصاً شاملاً.
  Future<void> run({String? gatewayHost}) async {
    if (running) return;
    running = true;
    error = null;
    notifyListeners();
    try {
      snapshot = await _service.run(gatewayHost: gatewayHost);
      if (snapshot?.hasError ?? false) {
        error = snapshot!.error;
      }
    } catch (e) {
      error = 'فشل التشخيص: $e';
    } finally {
      running = false;
      notifyListeners();
    }
  }

  /// رسالة خطأ آنية (تُستهلك مرة واحدة).
  String? takeError() {
    final String? value = error;
    error = null;
    return value;
  }
}
