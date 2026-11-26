import 'dart:io';

import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/app_theme.dart';
import '../services/github_engine.dart';
import '../services/workspace_manager.dart';
import 'create_project_wizard.dart';
import 'editor_screen.dart';
import 'github_connect_screen.dart';
import 'network_doctor_screen.dart';
import 'project_settings_screen.dart';

// ============================================================================
// TAB 1 — COMPACT SOLID PROJECTS DASHBOARD
// ============================================================================

class ProjectsHomeTab extends StatefulWidget {
  final void Function(int idx) onSwitchTab;
  const ProjectsHomeTab({super.key, required this.onSwitchTab});

  @override
  State<ProjectsHomeTab> createState() => _ProjectsHomeTabState();
}

class _ProjectsHomeTabState extends State<ProjectsHomeTab> {
  List<LocalProject> _projects = [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await WorkspaceManager.listProjects();
    if (!mounted) return;
    setState(() {
      _projects = list;
      _loading = false;
    });
  }

  Future<void> _openCreateWizard() async {
    final created = await Navigator.of(context).push<LocalProject>(
      MaterialPageRoute(builder: (_) => const CreateProjectWizardScreen()),
    );
    if (created != null) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم إنشاء تطبيق «${created.name}»')),
        );
      }
    }
  }

  Future<void> _exportZip(LocalProject proj) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('جاري ضغط ${proj.name} في ملف ZIP...')),
    );
    try {
      final zipFile = await WorkspaceManager.exportProjectToZip(proj);
      final sz = await zipFile.length();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم تصدير ZIP (${GitHubApiClient.fmtBytes(sz)}): ${zipFile.path}',
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل التصدير: $e')),
        );
      }
    }
  }

  Future<void> _confirmDelete(LocalProject proj) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('مسح المشروع', style: TextStyle(fontSize: 15)),
        content: Text(
          'هل تريد حذف «${proj.name}» نهائياً من الجهاز؟',
          style: const TextStyle(fontSize: 12.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: kCoral, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await WorkspaceManager.deleteProject(proj);
      if (appState.activeProject?.path == proj.path) {
        appState.setActiveProject(null);
      }
      await _load();
    }
  }

  Future<void> _showProjectDoctor(LocalProject proj) async {
    var stats = await WorkspaceManager.analyzeProject(proj);
    if (!mounted) return;
    final accent = appState.primaryColor;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'فحص: ${proj.name}',
                        style: const TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.w900),
                      ),
                    ),
                    ApexPill(
                      text: '${stats.score}%',
                      color: stats.score >= 85 ? kSuccess : accent,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: StatMiniBox(
                        label: 'الملفات',
                        value: '${stats.totalFiles}',
                        color: kSky,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: StatMiniBox(
                        label: 'سطور Dart',
                        value: '${stats.totalLines}',
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: StatMiniBox(
                        label: 'الحجم',
                        value: GitHubApiClient.fmtBytes(stats.totalBytes),
                        color: kAmber,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _DoctorCheckRow(
                  ok: stats.hasPubspec,
                  okText: 'ملف pubspec.yaml موجود',
                  failText: 'ملف pubspec.yaml مفقود',
                ),
                _DoctorCheckRow(
                  ok: stats.hasInternetPermission,
                  okText: 'صلاحية INTERNET مفعّلة في AndroidManifest.xml',
                  failText: 'صلاحية INTERNET مفقودة',
                ),
                _DoctorCheckRow(
                  ok: stats.hasApkWorkflow,
                  okText: 'ملف بناء APK السحابي جاهز',
                  failText: 'ملف Workflow لبناء APK غير موجود',
                ),
                _DoctorCheckRow(
                  ok: stats.hasAppIcon,
                  okText: 'أيقونة التطبيق مضبوطة',
                  failText: 'لا توجد أيقونة مخصصة للتطبيق',
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (!stats.hasInternetPermission || !stats.hasApkWorkflow)
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                          label: const Text('إصلاح تلقائي'),
                          onPressed: () async {
                            final fixes =
                                await WorkspaceManager.autoFixProject(proj);
                            final refreshed =
                                await WorkspaceManager.analyzeProject(proj);
                            setModalState(() => stats = refreshed);
                            if (mounted && fixes.isNotEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(fixes.join(' • '))),
                              );
                            }
                          },
                        ),
                      ),
                    if (!stats.hasInternetPermission || !stats.hasApkWorkflow)
                      const SizedBox(width: 6),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.code_rounded, size: 16),
                        label: const Text('المحرر'),
                        onPressed: () {
                          Navigator.pop(ctx);
                          appState.setActiveProject(proj);
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ApexEditorScreen(project: proj),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = appState.activeAccount;
    final accent = appState.primaryColor;
    final filtered = _query.trim().isEmpty
        ? _projects
        : _projects
            .where((p) =>
                p.name.toLowerCase().contains(_query.toLowerCase()) ||
                p.packageName.toLowerCase().contains(_query.toLowerCase()))
            .toList();

    return SafeArea(
      child: Column(
        children: [
          // Slim Solid App Header Bar (no promotional bloat)
          Container(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
            decoration: const BoxDecoration(
              color: kSurface,
              border: Border(bottom: BorderSide(color: kStroke)),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Icon(
                    Icons.hexagon_rounded,
                    color: Colors.black,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'JOOhub',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
                  ),
                ),
                const Spacer(),
                InkWell(
                  borderRadius: BorderRadius.circular(7),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const NetworkDoctorScreen(),
                    ),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(5),
                    child: Icon(Icons.network_check_rounded,
                        size: 18, color: kSky),
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  borderRadius: BorderRadius.circular(7),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const GitHubConnectScreen(),
                    ),
                  ),
                  child: ApexPill(
                    text: user != null ? '@${user.login}' : 'GitHub',
                    color: user != null ? kSuccess : accent,
                    icon: user != null ? Icons.verified : Icons.link,
                  ),
                ),
              ],
            ),
          ),

          // Main Scrollable Workspace
          Expanded(
            child: RefreshIndicator(
              color: accent,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  // Compact 3-Action Bar
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: const Text('جديد'),
                          onPressed: _openCreateWizard,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: accent.withValues(alpha: 0.6)),
                            foregroundColor: accent,
                          ),
                          icon: const Icon(Icons.auto_awesome_rounded, size: 15),
                          label: const Text('بناء AI'),
                          onPressed: () => widget.onSwitchTab(1),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.folder_zip_outlined, size: 15),
                          label: const Text('ZIP→APK'),
                          onPressed: () => widget.onSwitchTab(2),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Compact Search + Count Row
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          onChanged: (v) => setState(() => _query = v),
                          style: const TextStyle(fontSize: 12.5),
                          decoration: const InputDecoration(
                            hintText: 'بحث بالاسم أو Package Name...',
                            prefixIcon: Icon(Icons.search_rounded, size: 18),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ApexPill(text: '${_projects.length}', color: accent),
                    ],
                  ),
                  const SizedBox(height: 10),

                  if (_loading)
                    Padding(
                      padding: const EdgeInsets.all(28),
                      child: Center(
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: accent),
                      ),
                    )
                  else if (filtered.isEmpty)
                    ApexCard(
                      padding: const EdgeInsets.symmetric(
                          vertical: 22, horizontal: 14),
                      child: Column(
                        children: [
                          Icon(Icons.folder_off_outlined,
                              size: 32, color: accent.withValues(alpha: 0.55)),
                          const SizedBox(height: 8),
                          Text(
                            _projects.isEmpty
                                ? 'لا توجد مشاريع حالياً'
                                : 'لا توجد نتائج مطابقة',
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: Colors.white60,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              FilledButton.icon(
                                icon: const Icon(Icons.add_rounded, size: 15),
                                label: const Text('إنشاء تطبيق'),
                                onPressed: _openCreateWizard,
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.auto_awesome_rounded,
                                    size: 15),
                                label: const Text('بناء بالـ AI'),
                                onPressed: () => widget.onSwitchTab(1),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                  else
                    ...filtered.map((proj) {
                      final hasIcon = proj.iconPath != null &&
                          File(proj.iconPath!).existsSync();
                      final isActive = appState.activeProject?.path == proj.path;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ApexCard(
                          padding: const EdgeInsets.all(10),
                          borderColor: isActive
                              ? accent.withValues(alpha: 0.65)
                              : kStroke,
                          onTap: () {
                            appState.setActiveProject(proj);
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    ApexEditorScreen(project: proj),
                              ),
                            );
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: accent.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(9),
                                      border: Border.all(
                                        color: accent.withValues(alpha: 0.32),
                                      ),
                                      image: hasIcon
                                          ? DecorationImage(
                                              image: FileImage(
                                                  File(proj.iconPath!)),
                                              fit: BoxFit.cover,
                                            )
                                          : null,
                                    ),
                                    child: hasIcon
                                        ? null
                                        : Icon(Icons.terminal_rounded,
                                            size: 18, color: accent),
                                  ),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                proj.name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 13.5,
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 5),
                                            Text(
                                              'v${proj.version}',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w800,
                                                color: accent,
                                              ),
                                            ),
                                          ],
                                        ),
                                        Text(
                                          proj.packageName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 10.5,
                                            fontFamily: 'monospace',
                                            color: Colors.white54,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    WorkspaceManager.formatRelativeArabic(
                                        proj.modifiedAt),
                                    style: const TextStyle(
                                        fontSize: 10, color: Colors.white38),
                                  ),
                                  PopupMenuButton<String>(
                                    padding: EdgeInsets.zero,
                                    iconSize: 18,
                                    color: kSurfaceAlt,
                                    icon: const Icon(Icons.more_vert_rounded,
                                        color: Colors.white54),
                                    onSelected: (val) async {
                                      if (val == 'settings') {
                                        appState.setActiveProject(proj);
                                        await Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                ProjectSettingsScreen(
                                                    project: proj),
                                          ),
                                        );
                                        _load();
                                      } else if (val == 'zip') {
                                        await _exportZip(proj);
                                      } else if (val == 'delete') {
                                        await _confirmDelete(proj);
                                      }
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(
                                        value: 'settings',
                                        child: Text('الهوية والحزم',
                                            style: TextStyle(fontSize: 12)),
                                      ),
                                      PopupMenuItem(
                                        value: 'zip',
                                        child: Text('تصدير ZIP',
                                            style: TextStyle(fontSize: 12)),
                                      ),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Text('حذف المشروع',
                                            style: TextStyle(
                                                fontSize: 12, color: kCoral)),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  ActionChipBtn(
                                    icon: Icons.code_rounded,
                                    label: 'المحرر',
                                    color: accent,
                                    onTap: () {
                                      appState.setActiveProject(proj);
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              ApexEditorScreen(project: proj),
                                        ),
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 5),
                                  ActionChipBtn(
                                    icon: Icons.auto_awesome_rounded,
                                    label: 'AI',
                                    color: kViolet,
                                    onTap: () {
                                      appState.setActiveProject(proj);
                                      widget.onSwitchTab(1);
                                    },
                                  ),
                                  const SizedBox(width: 5),
                                  ActionChipBtn(
                                    icon: Icons.cloud_upload_outlined,
                                    label: 'رفع',
                                    color: kSky,
                                    onTap: () {
                                      appState.setActiveProject(proj);
                                      widget.onSwitchTab(3);
                                    },
                                  ),
                                  const SizedBox(width: 5),
                                  ActionChipBtn(
                                    icon: Icons.health_and_safety_outlined,
                                    label: 'فحص',
                                    color: kSuccess,
                                    onTap: () => _showProjectDoctor(proj),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DoctorCheckRow extends StatelessWidget {
  final bool ok;
  final String okText;
  final String failText;

  const _DoctorCheckRow({
    required this.ok,
    required this.okText,
    required this.failText,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
            size: 16,
            color: ok ? kSuccess : kCoral,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              ok ? okText : failText,
              style: TextStyle(
                fontSize: 11.5,
                color: ok ? Colors.white70 : kCoral,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
