import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/app_theme.dart';
import '../services/ai_engine.dart';
import '../services/workspace_manager.dart';
import 'ai_app_builder_sheet.dart';
import 'editor_screen.dart';

// ============================================================================
// AI STUDIO TAB — BUILD FULL APPS + MANAGE & UPDATE EXISTING PROJECTS
// ============================================================================

class _AiChatEntry {
  final bool isUser;
  final String text;
  final List<AiFileAction> actions;
  final LocalProject? builtProject;
  bool applied;

  _AiChatEntry({
    required this.isUser,
    required this.text,
    this.actions = const [],
    this.builtProject,
    this.applied = false,
  });
}

class AiStudioTab extends StatefulWidget {
  final VoidCallback onProjectChanged;
  final void Function(int idx) onSwitchTab;

  const AiStudioTab({
    super.key,
    required this.onProjectChanged,
    required this.onSwitchTab,
  });

  @override
  State<AiStudioTab> createState() => _AiStudioTabState();
}

class _AiStudioTabState extends State<AiStudioTab> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  // 0 = Build New App, 1 = Manage Existing Project
  int _mode = 0;
  List<LocalProject> _projects = [];
  LocalProject? _selectedProject;
  bool _autoApply = false;
  bool _busy = false;
  String _buildStep = '';
  double _buildProgress = 0.0;

  final List<_AiChatEntry> _messages = [];
  Map<String, String?>? _lastBackup;
  LocalProject? _lastBackupProject;

  @override
  void initState() {
    super.initState();
    _loadProjects();
    appState.addListener(_onAppStateUpdate);
  }

  void _onAppStateUpdate() {
    if (!mounted) return;
    if (appState.activeProject != null &&
        _selectedProject?.path != appState.activeProject?.path) {
      setState(() {
        _selectedProject = appState.activeProject;
      });
    }
  }

  Future<void> _loadProjects() async {
    final list = await WorkspaceManager.listProjects();
    if (!mounted) return;
    setState(() {
      _projects = list;
      if (appState.activeProject != null &&
          list.any((p) => p.path == appState.activeProject!.path)) {
        _selectedProject = list.firstWhere(
          (p) => p.path == appState.activeProject!.path,
        );
      } else if (list.isNotEmpty) {
        _selectedProject ??= list.first;
      } else {
        _selectedProject = null;
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _openQuickAiConfig() async {
    final accent = appState.primaryColor;
    var providerId = appState.aiProviderId;
    final keyCtrl = TextEditingController(text: appState.aiApiKey);
    final modelCtrl = TextEditingController(text: appState.aiModel);
    final urlCtrl = TextEditingController(text: appState.aiCustomBaseUrl);
    var obscure = true;
    var testing = false;
    AiConnectionTestResult? testRes;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          final preset = aiProviderById(providerId);
          return Padding(
            padding: EdgeInsets.fromLTRB(
              14,
              14,
              14,
              MediaQuery.of(ctx).viewInsets.bottom + 14,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.key_rounded, color: accent, size: 18),
                      const SizedBox(width: 7),
                      const Expanded(
                        child: Text(
                          'إعداد مفتاح ونموذج AI',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w900),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: kAiProviders.map((prov) {
                      final sel = prov.id == providerId;
                      return ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(prov.name,
                            style: const TextStyle(fontSize: 11)),
                        selected: sel,
                        selectedColor: accent.withValues(alpha: 0.24),
                        onSelected: (_) {
                          setModal(() {
                            providerId = prov.id;
                            modelCtrl.text = prov.defaultModel;
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: keyCtrl,
                    obscureText: obscure,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    decoration: InputDecoration(
                      labelText: 'مفتاح API Key',
                      hintText: preset.keyHint,
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 18,
                        ),
                        onPressed: () => setModal(() => obscure = !obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: modelCtrl,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    decoration: const InputDecoration(
                      labelText: 'اسم النموذج (Model ID)',
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: preset.models
                        .map((m) => ActionChipBtn(
                              icon: Icons.memory_rounded,
                              label: m,
                              color: modelCtrl.text == m ? accent : Colors.white60,
                              onTap: () => setModal(() => modelCtrl.text = m),
                            ))
                        .toList(),
                  ),
                  if (providerId == 'custom') ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: urlCtrl,
                      style:
                          const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      decoration: const InputDecoration(
                        labelText: 'رابط الخادم (Base URL)',
                        hintText: 'https://api.example.com/v1',
                      ),
                    ),
                  ],
                  if (testRes != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: (testRes!.ok ? kSuccess : kCoral)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: (testRes!.ok ? kSuccess : kCoral)
                              .withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        testRes!.message,
                        style: TextStyle(
                          fontSize: 11,
                          color: testRes!.ok ? kSuccess : kCoral,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: testing
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.wifi_tethering_rounded,
                                  size: 16),
                          label: const Text('اختبار'),
                          onPressed: testing
                              ? null
                              : () async {
                                  setModal(() {
                                    testing = true;
                                    testRes = null;
                                  });
                                  final r = await AiEngine.testConnection(
                                    providerId: providerId,
                                    apiKey: keyCtrl.text,
                                    model: modelCtrl.text,
                                    customBaseUrl: urlCtrl.text,
                                  );
                                  setModal(() {
                                    testing = false;
                                    testRes = r;
                                  });
                                },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.save_rounded, size: 16),
                          label: const Text('حفظ الإعدادات'),
                          onPressed: () async {
                            await appState.updateAiConfig(
                              providerId: providerId,
                              apiKey: keyCtrl.text,
                              model: modelCtrl.text,
                              customBaseUrl: urlCtrl.text,
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _launchBuildWizard([String initialPrompt = '']) async {
    if (!appState.hasAiKey) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أضف مفتاح AI أولاً للاتصال بالنموذج')),
      );
      await _openQuickAiConfig();
      if (!appState.hasAiKey) return;
    }

    final spec = await showModalBottomSheet<AiBuildSpec>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AiAppBuilderSheet(initialPrompt: initialPrompt),
    );
    if (spec == null || !mounted) return;

    setState(() {
      _mode = 0;
      _busy = true;
      _buildStep = 'بدء البناء الكامل لتطبيق ${spec.appName}...';
      _buildProgress = 0.08;
      _messages.add(
        _AiChatEntry(
          isUser: true,
          text: 'بناء تطبيق: ${spec.appName} (${spec.packageName})\n'
              'الفكرة: ${spec.prompt}\n'
              'الخيارات: ${spec.category} • ${spec.visualStyle} • ${spec.accentName} • ${spec.language} • ${spec.navigation}',
        ),
      );
    });
    _scrollToBottom();

    try {
      final result = await AiEngine.buildFullApp(
        spec: spec,
        onProgress: (step, prog) {
          if (mounted) {
            setState(() {
              _buildStep = step;
              _buildProgress = prog;
            });
          }
        },
      );

      await _loadProjects();
      widget.onProjectChanged();

      if (!mounted) return;
      setState(() {
        _selectedProject = result.project;
        _messages.add(
          _AiChatEntry(
            isUser: false,
            text: result.bundle.summary,
            actions: result.bundle.actions,
            builtProject: result.project,
            applied: true,
          ),
        );
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          _AiChatEntry(
            isUser: false,
            text: 'فشل البناء: ${e.toString().replaceFirst("Exception: ", "")}',
          ),
        );
      });
      _scrollToBottom();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _buildStep = '';
          _buildProgress = 0.0;
        });
      }
    }
  }

  Future<void> _handleSend() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _busy) return;
    _inputCtrl.clear();

    // If in Build Mode OR user explicitly asks to build a new app -> open the 6-option Setup Sheet!
    if (_mode == 0 || AiEngine.isBuildAppIntent(text)) {
      await _launchBuildWizard(text);
      return;
    }

    // Manage / Update existing project
    if (!appState.hasAiKey) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أضف مفتاح AI أولاً للاتصال بالنموذج')),
      );
      await _openQuickAiConfig();
      if (!appState.hasAiKey) return;
    }

    if (_selectedProject == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر مشروعاً من القائمة أولاً أو أنشئ تطبيقاً جديداً')),
      );
      return;
    }

    final proj = _selectedProject!;
    setState(() {
      _busy = true;
      _messages.add(_AiChatEntry(isUser: true, text: text));
    });
    _scrollToBottom();

    try {
      final recentHistory = _messages
          .where((m) => m.builtProject == null)
          .take(6)
          .map((m) => {
                'role': m.isUser ? 'user' : 'assistant',
                'content': m.text,
              })
          .toList();

      final bundle = await AiEngine.manageProject(
        project: proj,
        userInstruction: text,
        chatHistory: recentHistory,
      );

      var appliedNow = false;
      if (_autoApply && bundle.actions.isNotEmpty) {
        await AiEngine.applyActionsToProject(proj, bundle.actions);
        appliedNow = true;
        widget.onProjectChanged();
      }

      if (!mounted) return;
      setState(() {
        _messages.add(
          _AiChatEntry(
            isUser: false,
            text: bundle.summary,
            actions: bundle.actions,
            applied: appliedNow,
          ),
        );
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          _AiChatEntry(
            isUser: false,
            text: 'خطأ في الاتصال بالنموذج: ${e.toString().replaceFirst("Exception: ", "")}',
          ),
        );
      });
      _scrollToBottom();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _undoLastAiChange() async {
    if (_lastBackup == null || _lastBackupProject == null) return;
    await AiEngine.restoreBackup(_lastBackupProject!, _lastBackup!);
    widget.onProjectChanged();
    if (!mounted) return;
    setState(() {
      _lastBackup = null;
      _lastBackupProject = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم التراجع عن آخر تعديل للذكاء الاصطناعي بنجاح')),
    );
  }

  Future<void> _applyEntryActions(_AiChatEntry entry) async {
    final proj = _selectedProject;
    if (proj == null || entry.actions.isEmpty) return;
    final res = await AiEngine.applyActionsToProjectWithBackup(proj, entry.actions);
    widget.onProjectChanged();
    if (!mounted) return;
    setState(() {
      entry.applied = true;
      _lastBackup = res.backup;
      _lastBackupProject = proj;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تم تطبيق ${res.count} تعديل على مشروع ${proj.name}'),
        action: SnackBarAction(
          label: 'تراجع',
          onPressed: _undoLastAiChange,
        ),
      ),
    );
  }

  @override
  void dispose() {
    appState.removeListener(_onAppStateUpdate);
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = appState.primaryColor;
    final prov = aiProviderById(appState.aiProviderId);

    return SafeArea(
      child: Column(
        children: [
          // Compact Top Bar
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            decoration: const BoxDecoration(
              color: kSurface,
              border: Border(bottom: BorderSide(color: kStroke)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.auto_awesome_rounded, color: accent, size: 18),
                    const SizedBox(width: 6),
                    const Text(
                      'مساعد الذكاء AI',
                      style:
                          TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900),
                    ),
                    const Spacer(),
                    InkWell(
                      borderRadius: BorderRadius.circular(7),
                      onTap: _openQuickAiConfig,
                      child: ApexPill(
                        text: appState.hasAiKey
                            ? '${prov.name} • ${appState.aiModel}'
                            : 'إعداد مفتاح AI',
                        color: appState.hasAiKey ? kSuccess : accent,
                        icon: appState.hasAiKey
                            ? Icons.check_circle_outline_rounded
                            : Icons.key_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Mode Switcher
                Row(
                  children: [
                    Expanded(
                      child: _ModeTabBtn(
                        label: 'بناء تطبيق جديد',
                        icon: Icons.add_box_outlined,
                        selected: _mode == 0,
                        accent: accent,
                        onTap: () => setState(() => _mode = 0),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _ModeTabBtn(
                        label: 'إدارة وتحديث مشروع',
                        icon: Icons.build_circle_outlined,
                        selected: _mode == 1,
                        accent: accent,
                        onTap: () {
                          _loadProjects();
                          setState(() => _mode = 1);
                        },
                      ),
                    ),
                  ],
                ),

                // Project selector when in Manage Mode
                if (_mode == 1) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedProject?.path,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'المشروع المستهدف',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 10, vertical: 7),
                          ),
                          items: _projects
                              .map((p) => DropdownMenuItem(
                                    value: p.path,
                                    child: Text(
                                      '${p.name} (${p.packageName})',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11.5),
                                    ),
                                  ))
                              .toList(),
                          onChanged: (val) {
                            final match =
                                _projects.where((p) => p.path == val).toList();
                            if (match.isNotEmpty) {
                              setState(() => _selectedProject = match.first);
                              appState.setActiveProject(match.first);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => setState(() => _autoApply = !_autoApply),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                          decoration: BoxDecoration(
                            color: _autoApply
                                ? kSuccess.withValues(alpha: 0.16)
                                : kSurfaceAlt,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _autoApply ? kSuccess : kStroke,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _autoApply
                                    ? Icons.flash_on_rounded
                                    : Icons.flash_off_rounded,
                                size: 14,
                                color: _autoApply ? kSuccess : Colors.white54,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                'تلقائي',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: _autoApply ? kSuccess : Colors.white54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Live Build Progress Bar
          if (_busy && _buildStep.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.08),
                border: Border(
                    bottom: BorderSide(color: accent.withValues(alpha: 0.35))),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: accent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _buildStep,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: accent,
                          ),
                        ),
                      ),
                      Text(
                        '${(_buildProgress * 100).round()}%',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: accent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      minHeight: 4,
                      value: _buildProgress,
                      color: accent,
                      backgroundColor: kSurfaceAlt,
                    ),
                  ),
                ],
              ),
            ),

          // Conversation / Empty State
          Expanded(
            child: _messages.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      ApexCard(
                        borderColor: accent.withValues(alpha: 0.3),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  _mode == 0
                                      ? Icons.rocket_launch_rounded
                                      : Icons.manage_accounts_rounded,
                                  color: accent,
                                  size: 18,
                                ),
                                const SizedBox(width: 7),
                                Text(
                                  _mode == 0
                                      ? 'بناء تطبيق Flutter بالكامل'
                                      : 'إدارة وتحديث مشاريعك بالـ AI',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _mode == 0
                                  ? 'اكتب فكرة التطبيق بالأسفل أو اضغط «إعداد بناء تطبيق» لتحديد الاسم، الباكدج، الأيقونة، و6 خيارات تخصيص قبل بدء البناء الكامل.'
                                  : 'اختر مشروعاً من الأعلى ثم اطلب إضافة شاشات، تعديل التصميم، أو إصلاح الأخطاء ليتم تطبيقها مباشرة على ملفات المشروع.',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Colors.white60,
                                height: 1.45,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                if (!appState.hasAiKey)
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      icon: const Icon(Icons.key_rounded,
                                          size: 15),
                                      label: const Text('إضافة مفتاح AI'),
                                      onPressed: _openQuickAiConfig,
                                    ),
                                  ),
                                if (!appState.hasAiKey)
                                  const SizedBox(width: 8),
                                if (_mode == 0)
                                  Expanded(
                                    child: FilledButton.icon(
                                      icon: const Icon(
                                          Icons.auto_awesome_rounded,
                                          size: 15),
                                      label: const Text('إعداد بناء تطبيق'),
                                      onPressed: () => _launchBuildWizard(),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) {
                      final m = _messages[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Align(
                          alignment: m.isUser
                              ? AlignmentDirectional.centerStart
                              : AlignmentDirectional.centerEnd,
                          child: Container(
                            constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.90,
                            ),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: m.isUser
                                  ? accent.withValues(alpha: 0.14)
                                  : kSurface,
                              borderRadius: BorderRadius.circular(11),
                              border: Border.all(
                                color: m.isUser
                                    ? accent.withValues(alpha: 0.4)
                                    : kStroke,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SelectableText(
                                  m.text,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    height: 1.45,
                                  ),
                                ),
                                if (m.actions.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: kBg,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: kStroke),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(Icons.description_outlined,
                                                size: 13, color: accent),
                                            const SizedBox(width: 5),
                                            Text(
                                              'الملفات (${m.actions.length})',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w800,
                                                color: accent,
                                              ),
                                            ),
                                            const Spacer(),
                                            if (m.applied)
                                              const ApexPill(
                                                text: 'مُطبّق',
                                                color: kSuccess,
                                                icon: Icons.check,
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 5),
                                        ...m.actions.take(10).map((a) => Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 2),
                                              child: Text(
                                                '${a.type == "delete" ? "−" : "+"} ${a.path} (${a.lineCount} سطر)',
                                                style: TextStyle(
                                                  fontFamily: 'monospace',
                                                  fontSize: 10.5,
                                                  color: a.type == 'delete'
                                                      ? kCoral
                                                      : Colors.white70,
                                                ),
                                              ),
                                            )),
                                        const SizedBox(height: 7),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: [
                                            if (!m.applied &&
                                                m.builtProject == null)
                                              ActionChipBtn(
                                                icon: Icons.check_circle_outline,
                                                label: 'تطبيق على المشروع',
                                                color: kSuccess,
                                                onTap: () =>
                                                    _applyEntryActions(m),
                                              ),
                                            if (m.builtProject != null ||
                                                _selectedProject != null)
                                              ActionChipBtn(
                                                icon: Icons.code_rounded,
                                                label: 'افتح المحرر',
                                                color: accent,
                                                onTap: () {
                                                  final target = m.builtProject ??
                                                      _selectedProject!;
                                                  appState
                                                      .setActiveProject(target);
                                                  Navigator.of(context).push(
                                                    MaterialPageRoute(
                                                      builder: (_) =>
                                                          ApexEditorScreen(
                                                              project: target),
                                                    ),
                                                  );
                                                },
                                              ),
                                            if (m.builtProject != null)
                                              ActionChipBtn(
                                                icon: Icons.cloud_upload_outlined,
                                                label: 'رفع GitHub',
                                                color: kSky,
                                                onTap: () {
                                                  appState.setActiveProject(
                                                      m.builtProject!);
                                                  widget.onSwitchTab(3);
                                                },
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Compact Input Bar
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: const BoxDecoration(
              color: kSurface,
              border: Border(top: BorderSide(color: kStroke)),
            ),
            child: Row(
              children: [
                if (_messages.isNotEmpty)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'مسح المحادثة',
                    icon: const Icon(Icons.delete_sweep_outlined,
                        size: 19, color: Colors.white54),
                    onPressed: _busy
                        ? null
                        : () => setState(() => _messages.clear()),
                  ),
                Expanded(
                  child: TextField(
                    controller: _inputCtrl,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _handleSend(),
                    style: const TextStyle(fontSize: 12.5),
                    decoration: InputDecoration(
                      hintText: _mode == 0
                          ? 'اكتب فكرة التطبيق المطلوب بناؤه...'
                          : 'اطلب تعديلاً أو ميزة للمشروع المحدد...',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 11, vertical: 9),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  height: 38,
                  width: 38,
                  child: IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: _busy
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : const Icon(Icons.send_rounded, size: 17),
                    onPressed: _busy ? null : _handleSend,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeTabBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _ModeTabBtn({
    required this.label,
    required this.icon,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.16) : kSurfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? accent : kStroke,
            width: selected ? 1.2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: selected ? accent : Colors.white54),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: selected ? Colors.white : Colors.white60,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
