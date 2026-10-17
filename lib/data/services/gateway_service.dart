import '../../core/app_constants.dart';
import '../models/gateway_info.dart';
import '../models/login_outcome.dart';
import 'portal_client.dart';
import 'system_channel.dart';

/// خدمة اكتشاف البوابة الافتراضية.
class GatewayService {
  GatewayService(this._system, {PortalClient client = const PortalClient()})
      : _client = client;

  final SystemChannel _system;
  final PortalClient _client;

  /// يكتشف البوابة: يبدأ من إعدادات النظام ثم يجرّب العناوين الشائعة.
  Future<GatewayInfo> detect() async {
    final String? systemGateway = await _system.gateway();
    if (systemGateway != null && systemGateway.isNotEmpty) {
      final LoginOutcome outcome = await _client.probe(systemGateway);
      if (outcome.success) {
        return GatewayInfo(
          host: systemGateway,
          baseUrl: PortalClient.normalizeBase(systemGateway),
          source: 'system',
          statusCode: outcome.statusCode,
          pageTitle: outcome.pageTitle,
          responded: true,
        );
      }
    }

    for (final String candidate in AppConstants.commonGateways) {
      final LoginOutcome outcome = await _client.probe(candidate);
      if (outcome.success) {
        return GatewayInfo(
          host: candidate,
          baseUrl: PortalClient.normalizeBase(candidate),
          source: 'probe',
          statusCode: outcome.statusCode,
          pageTitle: outcome.pageTitle,
          responded: true,
        );
      }
    }

    final String fallback = AppConstants.fallbackGateway;
    return GatewayInfo(
      host: fallback,
      baseUrl: PortalClient.normalizeBase(fallback),
      source: 'fallback',
      responded: false,
    );
  }

  /// يعيد فحص بوابة محددة بعينها.
  Future<GatewayInfo> probeHost(String host) async {
    final LoginOutcome outcome = await _client.probe(host);
    return GatewayInfo(
      host: host,
      baseUrl: PortalClient.normalizeBase(host),
      source: 'probe',
      statusCode: outcome.statusCode,
      pageTitle: outcome.pageTitle,
      responded: outcome.success,
    );
  }
}
