// ═══════════════════════════════════════════════════════════════════════
// اختبارات معمل الروتر الافتراضي — تشغّل PortalClient الحقيقي (كود التطبيق
// نفسه) ضد بوابات افتراضية واقعية. أي فشل هنا = خطأ قاتل موثّق بالدليل.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:shadow_wifi/data/services/portal_client.dart';

import 'fake_router.dart';

void main() {
  final PortalClient client = PortalClient();
  const String goodCode = '5115125111';
  const String badCode = '9999999999';

  test('معمل MD5: متجهات RFC 1321 مرجعية', () {
    expect(LabMd5.hash(''), 'd41d8cd98f00b204e9800998ecf8427e');
    expect(LabMd5.hash('abc'), '900150983cd24fb0d6963f7d28e17f72');
    expect(
      LabMd5.hash('The quick brown fox jumps over the lazy dog'),
      '9e107d9d372bb6826bd81d3542a419d6',
    );
  });

  test('ميكروتك PAP: الرمز الصحيح يُرسل فعلاً إلى صفحة الدخول ويُقبل', () async {
    final LabRouter router = LabRouter(
      mode: LabRouterMode.mikrotikPap,
      validCodes: <String>{goodCode},
    );
    await router.start();
    addTearDown(router.stop);

    final outcome = await client.attempt(
      baseUrl: router.baseUrl,
      username: goodCode,
      password: goodCode,
      destination: '',
    );

    print('📜 سجل الروتر: ${router.log}');
    print('⚖️ حكم المحرك: نجاح=${outcome.success} | ${outcome.message}');

    // العقد: كلمة المرور تصل فعلاً إلى وجهة نموذج الدخول.
    expect(router.loginPostReceived, isTrue,
        reason: 'المحرك يجب أن يرسل الرمز إلى صفحة تسجيل الدخول نفسها');
    // العقد: الحقول المخفية للنموذج تُرسل كما هي كالمتصفح تماماً.
    expect(router.lastLoginFields?['popup'], 'true',
        reason: 'الحقول المخفية يجب أن تُرسل مع الطلب');
    expect(router.lastLoginFields?['username'], goodCode);
    expect(outcome.success, isTrue,
        reason: 'الرمز الصحيح يجب أن يُقبل من بوابة حقيقية');
  });

  test('ميكروتك PAP: الرمز الخاطئ يُرفض', () async {
    final LabRouter router = LabRouter(
      mode: LabRouterMode.mikrotikPap,
      validCodes: <String>{goodCode},
    );
    await router.start();
    addTearDown(router.stop);

    final outcome = await client.attempt(
      baseUrl: router.baseUrl,
      username: badCode,
      password: badCode,
      destination: '',
    );

    print('📜 سجل الروتر: ${router.log}');
    print('⚖️ حكم المحرك: نجاح=${outcome.success} | ${outcome.message}');
    expect(outcome.success, isFalse, reason: 'الرمز الخاطئ يجب أن يُرفض');
    expect(outcome.message, isNotEmpty);
  });

  test('ميكروتك CHAP: الرمز الصحيح يُشفّر MD5 كالمتصفح ويُقبل', () async {
    final LabRouter router = LabRouter(
      mode: LabRouterMode.mikrotikChap,
      validCodes: <String>{goodCode},
    );
    await router.start();
    addTearDown(router.stop);

    final outcome = await client.attempt(
      baseUrl: router.baseUrl,
      username: goodCode,
      password: goodCode,
      destination: '',
    );

    print('📜 سجل الروتر: ${router.log}');
    print('⚖️ حكم المحرك: نجاح=${outcome.success} | ${outcome.message}');
    expect(router.loginPostReceived, isTrue,
        reason: 'المحرك يجب أن يرسل البيانات إلى وجهة نموذج الدخول');
    expect(outcome.success, isTrue,
        reason: 'الرمز الصحيح يجب أن يُقبل حتى مع تشفير CHAP');
  });

  test('ميكروتك CHAP: الرمز الخاطئ يُرفض', () async {
    final LabRouter router = LabRouter(
      mode: LabRouterMode.mikrotikChap,
      validCodes: <String>{goodCode},
    );
    await router.start();
    addTearDown(router.stop);

    final outcome = await client.attempt(
      baseUrl: router.baseUrl,
      username: badCode,
      password: badCode,
      destination: '',
    );

    print('📜 سجل الروتر: ${router.log}');
    print('⚖️ حكم المحرك: نجاح=${outcome.success} | ${outcome.message}');
    expect(outcome.success, isFalse, reason: 'الرمز الخاطئ يجب أن يُرفض');
  });

  test('فخ الحالة المفتوحة: الرمز الخاطئ لا يُعلن «قبولاً مؤكداً»', () async {
    // بوابة صفحتها الرئيسية ترحيبية ولوحة الحالة عامة مفتوحة — أي حكم
    // فضفاض هنا يقبل كل الرموز زوراً (بلاغ المستخدم: «كل الرموز صحيحة»).
    final LabRouter router = LabRouter(
      mode: LabRouterMode.openStatusTrap,
      validCodes: <String>{goodCode},
    );
    await router.start();
    addTearDown(router.stop);

    final outcome = await client.attempt(
      baseUrl: router.baseUrl,
      username: badCode,
      password: badCode,
      destination: '',
    );

    print('📜 سجل الروتر: ${router.log}');
    print('⚖️ حكم المحرك: نجاح=${outcome.success} | ${outcome.message}');
    expect(outcome.success, isFalse,
        reason: 'رمز خاطئ على بوابة حالتها المفتوحة يجب ألا يُعلن قبولاً');
  });

  test('فخ الحالة المفتوحة: الرمز الصحيح يُقبل بدليل حقيقي', () async {
    final LabRouter router = LabRouter(
      mode: LabRouterMode.openStatusTrap,
      validCodes: <String>{goodCode},
    );
    await router.start();
    addTearDown(router.stop);

    final outcome = await client.attempt(
      baseUrl: router.baseUrl,
      username: goodCode,
      password: goodCode,
      destination: '',
    );

    print('📜 سجل الروتر: ${router.log}');
    print('⚖️ حكم المحرك: نجاح=${outcome.success} | ${outcome.message}');
    expect(outcome.success, isTrue,
        reason: 'الرمز الصحيح يجب أن يُقبل حتى على البوابات الفخّة');
  });

  test('ضجيج صفحة الدخول: شيفرة JS تحوي invalid لا تُرفض الرمز الصحيح', () async {
    final LabRouter router = LabRouter(
      mode: LabRouterMode.mikrotikPap,
      validCodes: <String>{goodCode},
      noisyLoginPage: true,
    );
    await router.start();
    addTearDown(router.stop);

    final outcome = await client.attempt(
      baseUrl: router.baseUrl,
      username: goodCode,
      password: goodCode,
      destination: '',
    );

    print('📜 سجل الروتر: ${router.log}');
    print('⚖️ حكم المحرك: نجاح=${outcome.success} | ${outcome.message}');
    expect(outcome.success, isTrue,
        reason: 'كلمة invalid داخل شيفرة الصفحة ليست رفضاً للرمز الصحيح');
  });

  test('بوابة تقبل أي رمز: العميل يبلّغ بما فعله الراوتر بحقيقة', () async {
    // الراوتر هنا قبل الرمز فعلاً — فالعميل يبلّغ بالحقيقة، والحماية من
    // «كل الرموز صحيحة» عبر اختبار التمييز في المتحكم (اختباراته في
    // ملف المتحكم).
    final LabRouter router = LabRouter(
      mode: LabRouterMode.acceptsAnything,
      validCodes: <String>{goodCode},
    );
    await router.start();
    addTearDown(router.stop);

    final outcome = await client.attempt(
      baseUrl: router.baseUrl,
      username: badCode,
      password: badCode,
      destination: '',
    );

    print('📜 سجل الروتر: ${router.log}');
    print('⚖️ حكم المحرك: نجاح=${outcome.success} | ${outcome.message}');
    expect(outcome.success, isTrue,
        reason: 'الراوتر قبل الرمز فعلاً — يجب الإبلاغ بالحقيقة');
  });
}
