import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/app_theme.dart';
import '../services/ai_engine.dart';
import '../services/background_build_service.dart';
import 'github_connect_screen.dart';
import 'network_doctor_screen.dart';

// ============================================================================
// TAB 5 — COMPLETE WORKING SETTINGS v9.0 (JOOhub)
// AI API + Live Model Fetch + Background Build & Animated Notification
// + Upload Engine + Code Editor + Appearance + Accounts + Maintenance
// ============================================================================

class ApexSettingsTab extends StatefulWidget {
  const ApexSettingsTab({super.key});

  @override
  State<ApexSettingsTab> createState() => _ApexSettingsTabState();
}

class _ApexSettingsTabState extends State<ApexSettingsTab> {
  late String _providerId;
  late TextEditingController _keyCtrl;
  late TextEditingController _modelCtrl;
  late TextEditingController _urlCtrl;
  late TextEditingController _sysPromptCtrl;
  bool _obscureKey = true;
  bool _testingAi = false;
  bool _fetchingModels = false;
  AiConnectionTestResult? _aiTestResult;
  List<String> _fetchedModels = [];

  @override
  void initState() {
    super.initState();
    _syncFromState();
  }

  void _syncFromState() {
    _providerId = appState.aiProviderId;
    _keyCtrl = TextEditingController(text: appState.aiApiKey);
    _modelCtrl = TextEditingController(text: appState.aiModel);
    _urlCtrl = TextEditingController(text: appState.aiCustomBaseUrl);
    _sysPromptCtrl = TextEditingController(text: appState.aiSystemPromptExtra);
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _modelCtrl.dispose();
    _urlCtrl.dispose();
    _sysPromptCtrl.dispose();
    super.dispose();
  }

  String _browserLabel(BrowserOpenMode m) {
    switch (m) {
      case BrowserOpenMode.askEveryTime:
        return 'السؤال كل مرة';
      case BrowserOpenMode.inApp:
        return 'المتصفح الداخلي';
      case BrowserOpenMode.external:
        return 'المتصفح الخارجي';
    }
  }

  String _batchLabel(int n) {
    if (n <= 3) return 'هادئ (3 ملفات)';
    if (n <= 6) return 'متوازن (5 ملفات)';
    return 'سريع (10 ملفات)';
  }

  Future<void> _saveAiConfig() async {
    await appState.updateAiConfig(
      providerId: _providerId,
      apiKey: _keyCtrl.text,
      model: _modelCtrl.text,
      customBaseUrl: _urlCtrl.text,
      systemPromptExtra: _sysPromptCtrl.text,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ إعدادات الذكاء الاصطناعي بنجاح')),
      );
    }
  }

  Future<void> _testAiConnection() async {
    setState(() {
      _testingAi = true;
      _aiTestResult = null;
    });
    final res = await AiEngine.testConnection(
      providerId: _providerId,
      apiKey: _keyCtrl.text,
      model: _modelCtrl.text,
      customBaseUrl: _urlCtrl.text,
    );
    if (!mounted) return;
    setState(() {
      _testingAi = false;
      _aiTestResult = res;
    });
  }

  Future<void> _fetchModels() async {
    setState(() => _fetchingModels = true);
    try {
      final list = await AiEngine.fetchAvailableModels(
        providerId: _providerId,
        apiKey: _keyCtrl.text,
        customBaseUrl: _urlCtrl.text,
      );
      if (!mounted) return;
      setState(() => _fetchedModels = list);
      if (list.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لم يتم العثور على نماذج من هذا المزود')),
        );
        return;
      }
      final picked = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: kSurface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        builder: (ctx) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(12),
            children: [
              Text(
                'النماذج المتاحة (${list.length})',
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              ...list.map((m) => ListTile(
                    dense: true,
                    title: Text(m,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12)),
                    trailing: _modelCtrl.text == m
                        ? Icon(Icons.check_circle,
                            color: appState.primaryColor, size: 18)
                        : null,
                    onTap: () => Navigator.pop(ctx, m),
                  )),
            ],
          ),
        ),
      );
      if (picked != null && mounted) {
        setState(() => _modelCtrl.text = picked);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل جلب النماذج: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _fetchingModels = false);
    }
  }

  Widget _sectionHeader(String title, Color accent) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          color: accent,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = appState.activeAccount;
    final accent = appState.primaryColor;
    final aiPreset = aiProviderById(_providerId);

    return SafeArea(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: const BoxDecoration(
              color: kSurface,
              border: Border(bottom: BorderSide(color: kStroke)),
            ),
            child: Row(
              children: [
                Icon(Icons.tune_rounded, color: accent, size: 18),
                const SizedBox(width: 7),
                const Text(
                  'إعدادات JOOhub',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                ),
                const Spacer(),
                InkWell(
                  borderRadius: BorderRadius.circular(7),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const NetworkDoctorScreen()),
                  ),
                  child: const ApexPill(
                    text: 'فحص الشبكة',
                    color: kSuccess,
                    icon: Icons.network_check_rounded,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                // ============================================================
                // 1. AI ENGINE SETTINGS
                // ============================================================
                _sectionHeader('محرك الذكاء الاصطناعي (AI API)', accent),
                ApexCard(
                  borderColor: appState.hasAiKey
                      ? kSuccess.withValues(alpha: 0.4)
                      : accent.withValues(alpha: 0.4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.auto_awesome_rounded,
                              color: accent, size: 16),
                          const SizedBox(width: 6),
                          const Expanded(
                            child: Text(
                              'المزود ومفتاح API والنموذج',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          ApexPill(
                            text: appState.hasAiKey ? 'مُفعّل' : 'غير متصل',
                            color: appState.hasAiKey ? kSuccess : kAmber,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        children: kAiProviders.map((prov) {
                          final sel = prov.id == _providerId;
                          return ChoiceChip(
                            visualDensity: VisualDensity.compact,
                            label: Text(prov.name,
                                style: const TextStyle(fontSize: 11)),
                            selected: sel,
                            selectedColor: accent.withValues(alpha: 0.24),
                            onSelected: (_) {
                              setState(() {
                                _providerId = prov.id;
                                _modelCtrl.text = prov.defaultModel;
                                _aiTestResult = null;
                                _fetchedModels = [];
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _keyCtrl,
                        obscureText: _obscureKey,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 11.5),
                        decoration: InputDecoration(
                          labelText: 'مفتاح API Key',
                          hintText: aiPreset.keyHint,
                          prefixIcon: const Icon(Icons.key_rounded, size: 17),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'لصق',
                                icon: const Icon(Icons.paste_rounded, size: 16),
                                onPressed: () async {
                                  final data = await Clipboard.getData(
                                      Clipboard.kTextPlain);
                                  if (data?.text != null && mounted) {
                                    setState(() =>
                                        _keyCtrl.text = data!.text!.trim());
                                  }
                                },
                              ),
                              IconButton(
                                icon: Icon(
                                  _obscureKey
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  size: 17,
                                ),
                                onPressed: () =>
                                    setState(() => _obscureKey = !_obscureKey),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _modelCtrl,
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: 11.5),
                              decoration: const InputDecoration(
                                labelText: 'اسم النموذج (Model ID)',
                                prefixIcon:
                                    Icon(Icons.memory_rounded, size: 17),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          OutlinedButton.icon(
                            icon: _fetchingModels
                                ? const SizedBox(
                                    width: 13,
                                    height: 13,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.cloud_download_outlined,
                                    size: 15),
                            label: const Text('جلب'),
                            onPressed: _fetchingModels ? null : _fetchModels,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        children: (_fetchedModels.isNotEmpty
                                ? _fetchedModels.take(6)
                                : aiPreset.models)
                            .map((m) => ActionChipBtn(
                                  icon: Icons.bolt_rounded,
                                  label: m,
                                  color: _modelCtrl.text == m
                                      ? accent
                                      : Colors.white60,
                                  onTap: () =>
                                      setState(() => _modelCtrl.text = m),
                                ))
                            .toList(),
                      ),
                      if (_providerId == 'custom') ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: _urlCtrl,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 11.5),
                          decoration: const InputDecoration(
                            labelText: 'رابط الخادم (Base URL)',
                            hintText: 'https://api.deepseek.com/v1',
                          ),
                        ),
                      ],
                      const Divider(color: kStroke, height: 14),
                      Row(
                        children: [
                          Text(
                            'الإبداع (Temp): ${appState.aiTemperature.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 11.5),
                          ),
                          Expanded(
                            child: Slider(
                              min: 0.0,
                              max: 1.0,
                              divisions: 10,
                              activeColor: accent,
                              value: appState.aiTemperature.clamp(0.0, 1.0),
                              onChanged: (v) =>
                                  appState.updateAiConfig(temperature: v),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Text(
                            'أقصى طول رد: ${appState.aiMaxTokens}',
                            style: const TextStyle(fontSize: 11.5),
                          ),
                          Expanded(
                            child: Slider(
                              min: 2048,
                              max: 16384,
                              divisions: 7,
                              activeColor: accent,
                              value:
                                  appState.aiMaxTokens.toDouble().clamp(2048, 16384),
                              onChanged: (v) => appState.updateAiConfig(
                                  maxTokens: v.round()),
                            ),
                          ),
                        ],
                      ),
                      TextField(
                        controller: _sysPromptCtrl,
                        maxLines: 2,
                        style: const TextStyle(fontSize: 11.5),
                        decoration: const InputDecoration(
                          labelText: 'تعليمات إضافية دائمة للذكاء (اختياري)',
                          hintText: 'مثال: استخدم تصميم داكن نظيف وتعليقات عربية',
                        ),
                      ),
                      if (_aiTestResult != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: (_aiTestResult!.ok ? kSuccess : kCoral)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: (_aiTestResult!.ok ? kSuccess : kCoral)
                                  .withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            _aiTestResult!.message,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _aiTestResult!.ok ? kSuccess : kCoral,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: _testingAi
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.wifi_tethering_rounded,
                                      size: 15),
                              label: const Text('اختبار الاتصال'),
                              onPressed: _testingAi ? null : _testAiConnection,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: FilledButton.icon(
                              icon: const Icon(Icons.save_rounded, size: 15),
                              label: const Text('حفظ'),
                              onPressed: _saveAiConfig,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // ============================================================
                // 2. BACKGROUND BUILD & ANIMATED NOTIFICATION
                // ============================================================
                _sectionHeader('نظام البناء في الخلفية والإشعار المتحرك', accent),
                ApexCard(
                  borderColor: accent.withValues(alpha: 0.35),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        activeColor: accent,
                        title: const Text(
                          'تفعيل البناء في الخلفية عند إغلاق التطبيق',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w800),
                        ),
                        subtitle: const Text(
                          'يُظهر إشعاراً متحركاً «جاري البناء» ويتابع GitHub Actions حتى عند قفل التطبيق',
                          style: TextStyle(fontSize: 10.5, color: Colors.white54),
                        ),
                        value: appState.backgroundBuildEnabled,
                        onChanged: (v) =>
                            appState.updateBgBuildPrefs(enabled: v),
                      ),
                      Row(
                        children: [
                          Text(
                            'فترة التحديث: ${appState.backgroundPollSeconds}ث',
                            style: const TextStyle(fontSize: 11.5),
                          ),
                          Expanded(
                            child: Slider(
                              min: 5,
                              max: 30,
                              divisions: 5,
                              activeColor: accent,
                              value: appState.backgroundPollSeconds
                                  .toDouble()
                                  .clamp(5, 30),
                              onChanged: (v) => appState.updateBgBuildPrefs(
                                  pollSeconds: v.round()),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(
                                  Icons.notifications_active_outlined,
                                  size: 15),
                              label: const Text('صلاحية الإشعارات'),
                              onPressed: () async {
                                final ok = await BackgroundBuildService
                                    .requestNotificationPermission();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(ok
                                          ? 'صلاحية الإشعارات مفعّلة بنجاح ✅'
                                          : 'يرجى السماح بالإشعارات من إعدادات الهاتف'),
                                    ),
                                  );
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: FilledButton.icon(
                              icon: const Icon(Icons.play_circle_outline,
                                  size: 15),
                              label: const Text('اختبار الإشعار'),
                              onPressed: () async {
                                await BackgroundBuildService
                                    .testAnimatedNotification();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                          'انظر لشريط الإشعارات: إشعار «جاري البناء» المتحرك يعمل الآن!'),
                                    ),
                                  );
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // ============================================================
                // 3. UPLOAD ENGINE & NETWORK
                // ============================================================
                _sectionHeader('نظام الرفع والشبكة', accent),
                ApexCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'طريقة الرفع الافتراضية:',
                        style: TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        children: [
                          ChoiceChip(
                            visualDensity: VisualDensity.compact,
                            label: const Text('ملف ملف (آمن 100%)',
                                style: TextStyle(fontSize: 11)),
                            selected:
                                appState.defaultUploadMode == 'file_by_file',
                            selectedColor: accent.withValues(alpha: 0.24),
                            onSelected: (_) => appState.updateNetworkPrefs(
                                uploadMode: 'file_by_file'),
                          ),
                          ChoiceChip(
                            visualDensity: VisualDensity.compact,
                            label: const Text('دفعات ذكية (5 مراحل)',
                                style: TextStyle(fontSize: 11)),
                            selected:
                                appState.defaultUploadMode == 'staged_batch',
                            selectedColor: accent.withValues(alpha: 0.24),
                            onSelected: (_) => appState.updateNetworkPrefs(
                                uploadMode: 'staged_batch'),
                          ),
                        ],
                      ),
                      const Divider(color: kStroke, height: 12),
                      Text(
                        'حجم الدفعة: ${_batchLabel(appState.uploadBatchSize)}',
                        style: const TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        children: [
                          ChoiceChip(
                            visualDensity: VisualDensity.compact,
                            label: const Text('هادئ (3)',
                                style: TextStyle(fontSize: 11)),
                            selected: appState.uploadBatchSize == 3,
                            selectedColor: accent.withValues(alpha: 0.24),
                            onSelected: (_) =>
                                appState.updateNetworkPrefs(batchSize: 3),
                          ),
                          ChoiceChip(
                            visualDensity: VisualDensity.compact,
                            label: const Text('متوازن (5)',
                                style: TextStyle(fontSize: 11)),
                            selected: appState.uploadBatchSize == 5,
                            selectedColor: accent.withValues(alpha: 0.24),
                            onSelected: (_) =>
                                appState.updateNetworkPrefs(batchSize: 5),
                          ),
                          ChoiceChip(
                            visualDensity: VisualDensity.compact,
                            label: const Text('سريع (10)',
                                style: TextStyle(fontSize: 11)),
                            selected: appState.uploadBatchSize == 10,
                            selectedColor: accent.withValues(alpha: 0.24),
                            onSelected: (_) =>
                                appState.updateNetworkPrefs(batchSize: 10),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Text('إعادة المحاولة: ${appState.maxRetries}',
                              style: const TextStyle(fontSize: 11.5)),
                          Expanded(
                            child: Slider(
                              min: 1,
                              max: 6,
                              divisions: 5,
                              activeColor: accent,
                              value: appState.maxRetries.toDouble(),
                              onChanged: (v) => appState.updateNetworkPrefs(
                                  retries: v.round()),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Text('المهلة: ${appState.timeoutSeconds}ث',
                              style: const TextStyle(fontSize: 11.5)),
                          Expanded(
                            child: Slider(
                              min: 20,
                              max: 90,
                              divisions: 7,
                              activeColor: accent,
                              value: appState.timeoutSeconds
                                  .toDouble()
                                  .clamp(20, 90),
                              onChanged: (v) => appState.updateNetworkPrefs(
                                  timeout: v.round()),
                            ),
                          ),
                        ],
                      ),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        activeColor: accent,
                        title: const Text('حفظ نقطة الاستكمال التلقائي',
                            style: TextStyle(fontSize: 12)),
                        value: appState.enableCheckpoints,
                        onChanged: (v) =>
                            appState.updateNetworkPrefs(checkpoints: v),
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          icon: const Icon(Icons.cleaning_services_outlined,
                              size: 15),
                          label: const Text('مسح نقاط الاستكمال القديمة'),
                          onPressed: () async {
                            final n = await appState.clearUploadCheckpoints();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text('تم مسح $n نقطة استكمال')),
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                // ============================================================
                // 4. APPEARANCE & TYPOGRAPHY
                // ============================================================
                _sectionHeader('المظهر والخطوط', accent),
                ApexCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.font_download_rounded,
                            color: accent, size: 19),
                        title: const Text('خط الواجهة',
                            style: TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w800)),
                        subtitle: Text(appState.uiFont.name,
                            style: const TextStyle(fontSize: 11)),
                        trailing:
                            const Icon(Icons.chevron_left_rounded, size: 18),
                        onTap: () async {
                          await showModalBottomSheet<void>(
                            context: context,
                            backgroundColor: kSurface,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(16)),
                            ),
                            builder: (_) => SafeArea(
                              child: ListView(
                                shrinkWrap: true,
                                padding: const EdgeInsets.all(12),
                                children: kUiFonts
                                    .map((f) => ListTile(
                                          dense: true,
                                          title: Text(f.name,
                                              style: const TextStyle(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w800)),
                                          subtitle: Text(f.sample,
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.white54)),
                                          trailing: appState.uiFontId == f.id
                                              ? Icon(Icons.check_circle,
                                                  color: accent, size: 18)
                                              : null,
                                          onTap: () async {
                                            await appState.setUiFont(f.id);
                                            if (context.mounted) {
                                              Navigator.pop(context);
                                            }
                                          },
                                        ))
                                    .toList(),
                              ),
                            ),
                          );
                        },
                      ),
                      const Divider(color: kStroke, height: 10),
                      Row(
                        children: [
                          Text(
                            'حجم الواجهة: ${(appState.uiFontScale * 100).round()}%',
                            style: const TextStyle(
                                fontSize: 11.5, fontWeight: FontWeight.w700),
                          ),
                          Expanded(
                            child: Slider(
                              min: 0.84,
                              max: 1.14,
                              divisions: 6,
                              activeColor: accent,
                              value: appState.uiFontScale.clamp(0.84, 1.14),
                              onChanged: (v) => appState.setUiFontScale(v),
                            ),
                          ),
                        ],
                      ),
                      const Divider(color: kStroke, height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: kOrangeAccents.map((preset) {
                          final sel = preset.id == appState.orangeAccentId;
                          return InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => appState.setOrangeAccent(preset.id),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 5),
                              decoration: BoxDecoration(
                                color: preset.primary
                                    .withValues(alpha: sel ? 0.20 : 0.08),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: sel ? preset.primary : kStroke,
                                  width: sel ? 1.2 : 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: preset.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    preset.name,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: sel ? Colors.white : Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),

                // ============================================================
                // 5. GITHUB ACCOUNTS
                // ============================================================
                _sectionHeader('حسابات GitHub', accent),
                ...appState.accounts.map((acc) {
                  final isAct = acc.login == active?.login;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: ApexCard(
                      borderColor: isAct ? accent : kStroke,
                      onTap: () => appState.switchAccount(acc.login),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 15,
                            backgroundColor: accent.withValues(alpha: 0.18),
                            child: Text(
                              acc.login.isNotEmpty
                                  ? acc.login[0].toUpperCase()
                                  : 'G',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: accent,
                                  fontWeight: FontWeight.w900),
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text('@${acc.login}',
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800)),
                          ),
                          if (isAct) ApexPill(text: 'نشط', color: accent),
                        ],
                      ),
                    ),
                  );
                }),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: Icon(Icons.person_add_alt_1_rounded,
                            color: accent, size: 16),
                        label: const Text('إضافة حساب'),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const GitHubConnectScreen()),
                        ),
                      ),
                    ),
                    if (active != null) ...[
                      const SizedBox(width: 6),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: kCoral,
                            side: BorderSide(
                                color: kCoral.withValues(alpha: 0.45)),
                          ),
                          icon: const Icon(Icons.logout_rounded, size: 16),
                          label: const Text('تسجيل خروج'),
                          onPressed: () => appState.removeActiveAccount(),
                        ),
                      ),
                    ],
                  ],
                ),

                // ============================================================
                // 6. CODE EDITOR SETTINGS
                // ============================================================
                _sectionHeader('محرر الأكواد', accent),
                ApexCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('المتصفح عند التفعيل',
                            style: TextStyle(fontSize: 12)),
                        subtitle: Text(_browserLabel(appState.browserMode),
                            style: const TextStyle(fontSize: 11)),
                        trailing:
                            const Icon(Icons.chevron_left_rounded, size: 18),
                        onTap: () async {
                          final m = await showModalBottomSheet<BrowserOpenMode>(
                            context: context,
                            backgroundColor: kSurface,
                            builder: (_) => SafeArea(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: BrowserOpenMode.values
                                    .map((v) => ListTile(
                                          dense: true,
                                          title: Text(_browserLabel(v)),
                                          trailing: appState.browserMode == v
                                              ? Icon(Icons.check, color: accent)
                                              : null,
                                          onTap: () => Navigator.pop(context, v),
                                        ))
                                    .toList(),
                              ),
                            ),
                          );
                          if (m != null) await appState.setBrowserMode(m);
                        },
                      ),
                      const Divider(color: kStroke, height: 8),
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('خط الكود',
                            style: TextStyle(fontSize: 12)),
                        subtitle: Text(appState.codeFont.name,
                            style: const TextStyle(fontSize: 11)),
                        trailing: const Icon(Icons.code_rounded, size: 18),
                        onTap: () async {
                          await showModalBottomSheet<void>(
                            context: context,
                            backgroundColor: kSurface,
                            builder: (_) => SafeArea(
                              child: ListView(
                                shrinkWrap: true,
                                padding: const EdgeInsets.all(10),
                                children: kCodeFonts
                                    .map((f) => ListTile(
                                          dense: true,
                                          title: Text(f.name),
                                          trailing: appState.codeFontId == f.id
                                              ? Icon(Icons.check, color: accent)
                                              : null,
                                          onTap: () async {
                                            await appState.setCodeFont(f.id);
                                            if (context.mounted) {
                                              Navigator.pop(context);
                                            }
                                          },
                                        ))
                                    .toList(),
                              ),
                            ),
                          );
                        },
                      ),
                      const Divider(color: kStroke, height: 8),
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('ثيم المحرر وتلوين الكود',
                            style: TextStyle(fontSize: 12)),
                        subtitle: Text(appState.codeTheme.name,
                            style: const TextStyle(fontSize: 11)),
                        trailing: const Icon(Icons.palette_outlined, size: 18),
                        onTap: () async {
                          await showModalBottomSheet<void>(
                            context: context,
                            backgroundColor: kSurface,
                            builder: (_) => SafeArea(
                              child: ListView(
                                shrinkWrap: true,
                                padding: const EdgeInsets.all(10),
                                children: kCodeThemes
                                    .map((t) => ListTile(
                                          dense: true,
                                          leading: CircleAvatar(
                                            radius: 13,
                                            backgroundColor: t.bg,
                                            child: Text('</>',
                                                style: TextStyle(
                                                    fontSize: 9,
                                                    color: t.accent)),
                                          ),
                                          title: Text(t.name),
                                          trailing: appState.codeThemeId == t.id
                                              ? Icon(Icons.check, color: accent)
                                              : null,
                                          onTap: () async {
                                            await appState.setCodeTheme(t.id);
                                            if (context.mounted) {
                                              Navigator.pop(context);
                                            }
                                          },
                                        ))
                                    .toList(),
                              ),
                            ),
                          );
                        },
                      ),
                      const Divider(color: kStroke, height: 8),
                      Row(
                        children: [
                          Text('حجم الخط: ${appState.editorFontSize.round()}',
                              style: const TextStyle(fontSize: 11.5)),
                          Expanded(
                            child: Slider(
                              min: 10,
                              max: 22,
                              divisions: 12,
                              activeColor: accent,
                              value: appState.editorFontSize,
                              onChanged: (v) =>
                                  appState.updateEditorPrefs(fontSize: v),
                            ),
                          ),
                        ],
                      ),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        activeColor: accent,
                        title: const Text('فحص الأخطاء الفوري (Live Linter)',
                            style: TextStyle(fontSize: 12)),
                        value: appState.editorLiveLint,
                        onChanged: (v) =>
                            appState.updateEditorPrefs(liveLint: v),
                      ),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        activeColor: accent,
                        title: const Text('حفظ تلقائي عند التنقل بين الملفات',
                            style: TextStyle(fontSize: 12)),
                        value: appState.editorAutoSave,
                        onChanged: (v) =>
                            appState.updateEditorPrefs(autoSave: v),
                      ),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        activeColor: accent,
                        title: const Text('أرقام السطور',
                            style: TextStyle(fontSize: 12)),
                        value: appState.showLineNumbers,
                        onChanged: (v) =>
                            appState.updateEditorPrefs(lineNumbers: v),
                      ),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        activeColor: accent,
                        title: const Text('التفاف السطور',
                            style: TextStyle(fontSize: 12)),
                        value: appState.editorWordWrap,
                        onChanged: (v) =>
                            appState.updateEditorPrefs(wordWrap: v),
                      ),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        activeColor: accent,
                        title: const Text('شريط الرموز البرمجية',
                            style: TextStyle(fontSize: 12)),
                        value: appState.showSymbolBar,
                        onChanged: (v) =>
                            appState.updateEditorPrefs(symbolBar: v),
                      ),
                    ],
                  ),
                ),

                // ============================================================
                // 7. MAINTENANCE & BACKUP
                // ============================================================
                _sectionHeader('الصيانة والنسخ الاحتياطي', accent),
                ApexCard(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ActionChipBtn(
                        icon: Icons.verified_user_rounded,
                        label: 'تأكيد الحفظ الدائم الآن',
                        color: kSuccess,
                        onTap: () async {
                          final ok = await appState.saveNow();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(ok
                                    ? '✅ تم حفظ كل حساباتك ومفاتيحك وإعداداتك بشكل دائم (SharedPreferences + AppDocuments)'
                                    : 'تعذّر تأكيد الحفظ'),
                              ),
                            );
                          }
                        },
                      ),
                      ActionChipBtn(
                        icon: Icons.copy_all_rounded,
                        label: 'نسخ إعداداتي JSON',
                        color: kSky,
                        onTap: () async {
                          final txt = const JsonEncoder.withIndent('  ')
                              .convert(appState.toExportMap(
                                  includeSecrets: false));
                          await Clipboard.setData(ClipboardData(text: txt));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content:
                                      Text('تم نسخ نسخة الإعدادات إلى الحافظة')),
                            );
                          }
                        },
                      ),
                      ActionChipBtn(
                        icon: Icons.history_toggle_off_rounded,
                        label: 'مسح سجل النشاط',
                        color: kAmber,
                        onTap: () async {
                          await appState.clearHistory();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('تم مسح سجل النشاط')),
                            );
                          }
                        },
                      ),
                      ActionChipBtn(
                        icon: Icons.restore_rounded,
                        label: 'استعادة الافتراضي',
                        color: kCoral,
                        onTap: () async {
                          await appState.resetDefaults(
                              keepAccountsAndKeys: true);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'تمت استعادة الإعدادات الافتراضية (مع الحفاظ على حساباتك ومفتاح AI)'),
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),
                ApexCard(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Icon(Icons.hexagon_rounded, color: accent, size: 17),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'JOOhub v10.0 • YOSSEF JOO',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                      const Text(
                        '01029892573',
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: Colors.white38,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
