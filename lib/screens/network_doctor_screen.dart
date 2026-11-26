import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/app_theme.dart';
import '../services/github_engine.dart';

// ============================================================================
// NETWORK DOCTOR & ACTIVITY HISTORY SCREEN 
// • فحص DNS + سرعة الاتصال (Ping ms) + رصيد GitHub API + صلاحيات التوكن
// • سجل العمليات والأخطاء المحفوظ مع نسخ التقرير الكامل بضغطة واحدة
// ============================================================================

class NetworkDoctorScreen extends StatefulWidget {
  const NetworkDoctorScreen({super.key});

  @override
  State<NetworkDoctorScreen> createState() => _NetworkDoctorScreenState();
}

class _NetworkDoctorScreenState extends State<NetworkDoctorScreen> {
  ConnectionHealthResult? _result;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _runDiagnostics();
  }

  Future<void> _runDiagnostics() async {
    setState(() => _checking = true);
    final acc = appState.activeAccount;
    final client = acc != null
        ? appState.createClientFor(acc)
        : GitHubApiClient(
            '',
            maxRetries: appState.maxRetries,
            timeoutSeconds: appState.timeoutSeconds,
          );
    try {
      final res = await client.checkConnectionHealth();
      if (!mounted) return;
      setState(() => _result = res);
    } finally {
      client.close();
      if (mounted) setState(() => _checking = false);
    }
  }

  String _fmtTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day}/${dt.month} • $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final accent = appState.primaryColor;
    final r = _result;

    return Scaffold(
      appBar: AppBar(
        title: const Text('فحص الشبكة وسجل العمليات'),
        actions: [
          IconButton(
            tooltip: 'إعادة الفحص',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _checking ? null : _runDiagnostics,
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: appState,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              // Live Network Health Banner
              ApexCard(
                borderColor: r == null
                    ? accent.withValues(alpha: 0.4)
                    : (r.apiOk ? kSuccess : kCoral),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: (r == null
                                    ? accent
                                    : (r.apiOk ? kSuccess : kCoral))
                                .withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: _checking
                              ? Padding(
                                  padding: const EdgeInsets.all(11),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: accent,
                                  ),
                                )
                              : Icon(
                                  r?.apiOk == true
                                      ? Icons.wifi_tethering_rounded
                                      : Icons.wifi_off_rounded,
                                  color: r?.apiOk == true ? kSuccess : kCoral,
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _checking
                                    ? 'بنفحص الاتصال بـ GitHub دلوقتي...'
                                    : (r?.qualityLabel ?? 'جاهز للفحص'),
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                r?.userLogin != null
                                    ? 'الحساب النشط: @${r!.userLogin}'
                                    : (appState.activeAccount == null
                                        ? 'مفيش حساب GitHub مربوط حالياً'
                                        : 'حساب: @${appState.activeAccount!.login}'),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white60,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (r != null) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: StatMiniBox(
                              label: 'الـ DNS',
                              value: r.dnsOk ? 'شغال ✓' : 'فشل ✕',
                              color: r.dnsOk ? kSuccess : kCoral,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: StatMiniBox(
                              label: 'الاستجابة (Ping)',
                              value: r.latencyMs > 0
                                  ? '${r.latencyMs} ms'
                                  : '--',
                              color: r.latencyMs > 0 && r.latencyMs <= 500
                                  ? kSuccess
                                  : (r.latencyMs > 900 ? kAmber : kSky),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: StatMiniBox(
                              label: 'رصيد API',
                              value: r.rateLimit > 0
                                  ? '${r.rateRemaining}/${r.rateLimit}'
                                  : '--',
                              color: accent,
                            ),
                          ),
                        ],
                      ),
                      if (r.tokenScopes.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'صلاحيات التوكن المفعّلة:',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: r.tokenScopes
                              .map((s) => ApexPill(
                                    text: s,
                                    color: (s == 'repo' || s == 'workflow')
                                        ? kSuccess
                                        : kSky,
                                    icon: Icons.verified_outlined,
                                  ))
                              .toList(),
                        ),
                      ],
                    ],
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      icon: const Icon(Icons.speed_rounded, size: 18),
                      label: Text(
                        _checking ? 'جاري الفحص...' : 'اختبر سرعة وحالة الاتصال',
                      ),
                      onPressed: _checking ? null : _runDiagnostics,
                    ),
                  ],
                ),
              ),

              if (r?.error != null) ...[
                const SizedBox(height: 12),
                ErrorDiagnosticCard(
                  error: r!.error!,
                  onRetry: _runDiagnostics,
                ),
              ],

              const SizedBox(height: 16),

              // Active Resilient Engine Config Summary
              ApexCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'إعدادات قوة الاتصال والرفع الحالية',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ApexPill(
                          text: 'الدفعة: ${appState.uploadBatchSize} ملفات',
                          color: accent,
                        ),
                        ApexPill(
                          text: 'إعادة المحاولة: ${appState.maxRetries} مرات',
                          color: kSky,
                        ),
                        ApexPill(
                          text: 'المهلة: ${appState.timeoutSeconds} ثانية',
                          color: kAmber,
                        ),
                        ApexPill(
                          text: appState.enableCheckpoints
                              ? 'الاستكمال التلقائي: شغال'
                              : 'الاستكمال التلقائي: مقفول',
                          color: appState.enableCheckpoints
                              ? kSuccess
                              : Colors.white54,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // Activity History Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'سجل العمليات والأخطاء',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                  if (appState.history.isNotEmpty)
                    Row(
                      children: [
                        TextButton.icon(
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          label: const Text('نسخ'),
                          onPressed: () async {
                            final txt = appState.history
                                .map((h) =>
                                    '[${_fmtTime(h.time)}] ${h.isError ? "ERROR" : "OK"}: ${h.title} — ${h.detail}')
                                .join('\n');
                            await Clipboard.setData(ClipboardData(text: txt));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('اتنسخ سجل العمليات كله'),
                                ),
                              );
                            }
                          },
                        ),
                        TextButton.icon(
                          style: TextButton.styleFrom(foregroundColor: kCoral),
                          icon: const Icon(Icons.delete_outline, size: 16),
                          label: const Text('مسح'),
                          onPressed: () => appState.clearHistory(),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 8),

              if (appState.history.isEmpty)
                const ApexCard(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(
                      child: Text(
                        'لسه مفيش عمليات متسجلة — أي رفع أو بناء أو خطأ هيتسجل هنا تلقائي.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12.5, color: Colors.white54),
                      ),
                    ),
                  ),
                )
              else
                ...appState.history.map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ApexCard(
                        padding: const EdgeInsets.all(12),
                        borderColor: item.isError
                            ? kCoral.withValues(alpha: 0.45)
                            : kStroke,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              item.isError
                                  ? Icons.error_outline_rounded
                                  : Icons.check_circle_outline_rounded,
                              color: item.isError ? kCoral : kSuccess,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item.title,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        _fmtTime(item.time),
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          color: Colors.white38,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    item.detail,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: Colors.white70,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )),
            ],
          );
        },
      ),
    );
  }
}
