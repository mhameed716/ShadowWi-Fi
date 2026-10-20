import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/services/portal_client.dart';
import '../../../data/services/state_store.dart';
import '../../../state/auto_portal_controller.dart';
import '../../widgets/section_card.dart';
import '../../widgets/status_chip.dart';

/// تنسيق توقيت الاكتشاف للعرض.
String formatTime(DateTime time) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}

/// الواجهة الخامسة — بوابة تلقائية: كشف + توليد + محاولات + نتائج.
class AutoPortalScreen extends StatefulWidget {
  const AutoPortalScreen({super.key});

  @override
  State<AutoPortalScreen> createState() => _AutoPortalScreenState();
}

class _AutoPortalScreenState extends State<AutoPortalScreen> {
  AutoPortalController? _listened;
  int _seenFound = 0;
  bool _sheetOpen = false;
  final TextEditingController _urlField = TextEditingController();
  final FocusNode _urlFocus = FocusNode();

  void _listen(AutoPortalController controller) {
    if (_listened == controller) return;
    _listened?.removeListener(_onChanged);
    _listened = controller;
    _seenFound = controller.foundCodes.length;
    controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _listened?.removeListener(_onChanged);
    _urlField.dispose();
    _urlFocus.dispose();
    super.dispose();
  }

  /// فاحص البوابة: يريك بالتفصيل ما اكتُشف من نموذج وماذا يُرسل فعلاً
  /// وكيف ردّ الراوتر — بشفافية كاملة.
  Future<void> _openInspector(
    BuildContext context,
    AutoPortalController wifi,
  ) async {
    if (wifi.portalUrl.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اكشف البوابة أولاً — لا يوجد رابط')),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FutureBuilder<PortalInspection>(
              future: PortalClient().inspect(wifi.portalUrl.trim()),
              builder:
                  (BuildContext c, AsyncSnapshot<PortalInspection> snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('جارٍ فحص البوابة...'),
                    ],
                  );
                }
                final PortalInspection inspection = snap.data ??
                    const PortalInspection(lines: <String>['تعذّر الفحص']);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'فاحص البوابة — تقرير كامل',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: inspection.lines
                              .map(
                                (String line) => Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 3,
                                  ),
                                  child: Text(
                                    line,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _onChanged() {
    final AutoPortalController controller = _listened!;
    if (!mounted) return;
    // مزامنة حقل الرابط مع الاكتشاف التلقائي دون كسر الكتابة اليدوية.
    if (_urlField.text != controller.portalUrl && !_urlFocus.hasFocus) {
      _urlField.text = controller.portalUrl;
    }
    if (controller.foundCodes.length > _seenFound && !_sheetOpen) {
      _seenFound = controller.foundCodes.length;
      _showResultSheet(controller);
    } else {
      _seenFound = controller.foundCodes.length;
    }
  }

  Future<void> _showResultSheet(AutoPortalController controller) async {
    _sheetOpen = true;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext sheetContext) {
        return AnimatedBuilder(
          animation: controller,
          builder: (BuildContext context, _) {
            final FoundCode? found = controller.lastFound;
            if (found == null) return const SizedBox(height: 160);
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const Icon(Icons.verified, color: AppColors.success),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'تم اكتشاف رمز صحيح!',
                          style: TextStyle(
                            color: AppColors.success,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      StatusChip(
                        label: 'المحرك متوقف مؤقتاً',
                        color: AppColors.warning,
                        icon: Icons.pause_circle,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.inputFill,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.success),
                    ),
                    child: Column(
                      children: <Widget>[
                        SelectableText(
                          found.code,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: AppColors.success,
                            fontFamily: 'monospace',
                            letterSpacing: 3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'توقيت الاكتشاف: ${formatTime(found.discoveredAt)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: found.code),
                            );
                            if (sheetContext.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('تم نسخ الرمز'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.copy, size: 18),
                          label: const Text('نسخ الرمز'),
                        ),
                      ),
                      if (controller.monitoring) ...<Widget>[
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () {
                              Navigator.of(sheetContext).pop();
                              controller.resumeEngine();
                            },
                            icon: const Icon(Icons.play_arrow, size: 18),
                            label: const Text('استئناف'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(() => _sheetOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    _listen(context.watch<AutoPortalController>());
    final AutoPortalController wifi = context.watch<AutoPortalController>();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        // ── حالة الشبكة والكشف ──
        SectionCard(
          title: 'الكشف التلقائي عن البوابة',
          icon: Icons.radar,
          subtitle: wifi.detectionMethod.isEmpty
              ? 'لم يتم الفحص بعد'
              : 'الطريقة: ${wifi.detectionMethod}',
          trailing: StatusChip(
            label: wifi.portalDetected ? 'بوابة مقيدة' : 'لا بوابة',
            color: wifi.portalDetected ? AppColors.success : AppColors.textSecondary,
            icon: wifi.portalDetected ? Icons.wifi_lock : Icons.wifi_off_outlined,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    Icons.lan_outlined,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'حالة الاتصال: ${wifi.connectionLabel}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => wifi.detectPortal(),
                icon: const Icon(Icons.search, size: 18),
                label: const Text('فحص البوابة الآن'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _openInspector(context, wifi),
                icon: const Icon(Icons.manage_search, size: 18),
                label: const Text('فاحص البوابة — ماذا يُرسل فعلاً؟'),
              ),
              if (wifi.acceptsAnything) ...<Widget>[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.deepOrange.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.deepOrange.withOpacity(0.4),
                    ),
                  ),
                  child: const Row(
                    children: <Widget>[
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.deepOrange,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'البوابة تقبل أي رمز — أُوقف البحث لأن تحديد '
                          'الرمز الصحيح مستحيل على هذه البوابة',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── الإعدادات ──
        SectionCard(
          title: 'الإعدادات',
          icon: Icons.tune,
          child: Column(
            children: <Widget>[
              TextField(
                controller: _urlField,
                focusNode: _urlFocus,
                onChanged: wifi.setPortalUrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'الرابط المستهدف (يُكتشف تلقائياً)',
                  hintText: 'http://... صفحة تسجيل الدخول',
                  prefixIcon: Icon(Icons.link, size: 20),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                onChanged: wifi.setStartInput,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'رقم البداية (اختياري)',
                  hintText:
                      'اتركه فارغاً للبدء من ${AutoPortalController.formatCode(1, wifi.codeLength)}',
                  prefixIcon: const Icon(Icons.pin, size: 20),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                onChanged: wifi.setStep,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'قيمة الزيادة (اختياري)',
                  hintText: '1 = متتالي • مثال 100: 511 → 611 → 711',
                  prefixIcon: Icon(Icons.fast_forward, size: 20),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  const Text(
                    'عدد الخانات',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    tooltip: 'تقليل',
                    onPressed: wifi.monitoring
                        ? null
                        : () => wifi.setCodeLength(wifi.codeLength - 1),
                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.inputFill,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      '${wifi.codeLength}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'زيادة',
                    onPressed: wifi.monitoring
                        ? null
                        : () => wifi.setCodeLength(wifi.codeLength + 1),
                    icon: const Icon(Icons.add_circle_outline, size: 20),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'من ${AutoPortalController.minLength} إلى ${AutoPortalController.maxLength}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── مؤشر الأعداد المباشر ──
        SectionCard(
          title: 'المؤشر المباشر',
          icon: Icons.monitor_heart_outlined,
          trailing: StatusChip(
            label: wifi.smartPaused
                ? 'توقف ذكي'
                : wifi.paused
                    ? 'إيقاف مؤقت'
                    : wifi.monitoring
                        ? 'يعمل'
                        : 'موقوف',
            color: wifi.smartPaused
                ? AppColors.success
                : wifi.monitoring
                    ? AppColors.info
                    : AppColors.textSecondary,
            icon: wifi.smartPaused
                ? Icons.pause_circle
                : wifi.monitoring
                    ? Icons.bolt
                    : Icons.stop_circle,
          ),
          child: Column(
            children: <Widget>[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  color: AppColors.inputFill,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: <Widget>[
                    const Text(
                      'الرقم الحالي قيد الفحص',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      AutoPortalController.formatCode(
                          wifi.currentNumber, wifi.codeLength),
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                        fontFamily: 'monospace',
                        letterSpacing: 4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _CounterCell(
                      label: 'المحاولات',
                      value: wifi.attempts.toString(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _CounterCell(
                      label: 'رموز صحيحة',
                      value: wifi.foundCodes.length.toString(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                wifi.statusText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── التجربة اليدوية الحرة ──
        SectionCard(
          title: 'تجربة يدوية حرة',
          icon: Icons.edit_note,
          subtitle: 'أدخل أي رمز أو كلمة وجرّبها فوراً على البوابة',
          child: Column(
            children: <Widget>[
              TextField(
                onChanged: wifi.setManualCode,
                textInputAction: TextInputAction.done,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                ),
                decoration: const InputDecoration(
                  labelText: 'رمز يدوي',
                  hintText: 'أي رمز أو كلمة مرور',
                  prefixIcon: Icon(Icons.keyboard, size: 20),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: wifi.manualTesting
                      ? null
                      : () => wifi.tryManualCode(),
                  icon: wifi.manualTesting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.bolt, size: 18),
                  label: const Text('تجربة الرمز'),
                ),
              ),
              if (wifi.manualResult != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  wifi.manualResult!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    fontWeight: FontWeight.w700,
                    color: wifi.manualSuccess == true
                        ? AppColors.success
                        : wifi.manualSuccess == false
                            ? AppColors.danger
                            : AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── أزرار التحكم ──
        Row(
          children: <Widget>[
            Expanded(
              child: FilledButton.icon(
                onPressed: wifi.monitoring
                    ? (wifi.paused || wifi.smartPaused
                        ? () => wifi.resumeEngine()
                        : null)
                    : () => wifi.start(),
                icon: Icon(
                  wifi.monitoring && !wifi.paused && !wifi.smartPaused
                      ? Icons.autorenew
                      : Icons.play_arrow,
                  size: 18,
                ),
                label: Text(
                  wifi.monitoring && !wifi.paused && !wifi.smartPaused
                      ? 'يعمل تلقائياً'
                      : 'بدء تلقائي',
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed:
                    wifi.monitoring && !wifi.paused ? () => wifi.pause() : null,
                icon: const Icon(Icons.pause, size: 18),
                label: const Text('إيقاف مؤقت'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => wifi.reset(),
                icon: const Icon(Icons.restart_alt, size: 18),
                label: const Text('إعادة ضبط'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── الرموز المكتشفة ──
        if (wifi.foundCodes.isNotEmpty)
          SectionCard(
            title: 'الرموز المكتشفة',
            icon: Icons.key,
            subtitle: 'اضغط أيقونة النسخ لنسخ أي رمز',
            child: Column(
              children: wifi.foundCodes
                  .map((FoundCode entry) => _FoundTile(entry: entry))
                  .toList(),
            ),
          ),
      ],
    );
  }
}

/// خلية عدّاد صغيرة.
class _CounterCell extends StatelessWidget {
  const _CounterCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: <Widget>[
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// صف رمز مكتشف مع زر نسخ.
class _FoundTile extends StatelessWidget {
  const _FoundTile({required this.entry});

  final FoundCode entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.inputFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.success.withOpacity(0.4)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.check_circle, color: AppColors.success, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              entry.code,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                fontFamily: 'monospace',
                letterSpacing: 2,
              ),
            ),
          ),
          Text(
            formatTime(entry.discoveredAt),
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'نسخ',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: entry.code));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('تم نسخ الرمز'),
                    duration: Duration(seconds: 1),
                  ),
                );
              }
            },
            icon: const Icon(Icons.copy, size: 16),
          ),
        ],
      ),
    );
  }
}
