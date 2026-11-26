import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/app_state.dart';
import '../core/app_theme.dart';
import '../services/workspace_manager.dart';

// ============================================================================
// PROJECT SETTINGS — IDENTITY & ICON + ANDROID PERMISSIONS + PUBSPEC MANAGER
// ============================================================================

class ProjectSettingsScreen extends StatefulWidget {
  final LocalProject project;
  const ProjectSettingsScreen({super.key, required this.project});

  @override
  State<ProjectSettingsScreen> createState() => _ProjectSettingsScreenState();
}

class _ProjectSettingsScreenState extends State<ProjectSettingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  final _nameCtrl = TextEditingController();
  final _pkgCtrl = TextEditingController();
  final _verCtrl = TextEditingController();
  final _buildCtrl = TextEditingController();
  final _customPkgNameCtrl = TextEditingController();
  final _customPkgVerCtrl = TextEditingController(text: 'any');

  String? _iconPath;
  Set<String> _activePerms = {};
  Map<String, String> _deps = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _loadAll();
  }

  Future<void> _loadAll() async {
    final c = await ProjectConfigService(widget.project).load();
    final perms =
        await WorkspaceManager.readManifestPermissions(widget.project);
    final deps = await WorkspaceManager.readPubspecDependencies(widget.project);
    if (!mounted) return;
    setState(() {
      _nameCtrl.text = c.appName;
      _pkgCtrl.text = c.packageName;
      _verCtrl.text = c.version;
      _buildCtrl.text = c.buildNumber;
      _iconPath = c.iconPath;
      _activePerms = perms;
      _deps = deps;
    });
  }

  Future<void> _saveIdentity() async {
    setState(() => _saving = true);
    try {
      final updated = await WorkspaceManager.applyProjectIdentity(
        projectDir: Directory(widget.project.path),
        appName: _nameCtrl.text.trim(),
        packageName: _pkgCtrl.text.trim(),
        version: _verCtrl.text.trim().isEmpty ? '1.0.0' : _verCtrl.text.trim(),
        buildNumber:
            _buildCtrl.text.trim().isEmpty ? '1' : _buildCtrl.text.trim(),
        iconSourcePath: _iconPath,
      );
      appState.setActiveProject(updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '✅ تم حفظ هوية المشروع وتحديث Manifest و Gradle والأيقونات بنجاح',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ خطأ: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _nameCtrl.dispose();
    _pkgCtrl.dispose();
    _verCtrl.dispose();
    _buildCtrl.dispose();
    _customPkgNameCtrl.dispose();
    _customPkgVerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = appState.primaryColor;
    final hasIcon = _iconPath != null && File(_iconPath!).existsSync();

    return Scaffold(
      appBar: AppBar(
        title: Text('إعدادات ${widget.project.name}'),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: accent,
          labelColor: accent,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(text: 'الهوية والأيقونة'),
            Tab(text: 'الصلاحيات'),
            Tab(text: 'حزم Pubspec'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          // TAB 1: Identity & App Icon
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ApexCard(
                borderColor: accent.withValues(alpha: 0.4),
                child: Row(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: accent.withValues(alpha: 0.5)),
                        image: hasIcon
                            ? DecorationImage(
                                image: FileImage(File(_iconPath!)),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: hasIcon
                          ? null
                          : Icon(Icons.apps_rounded, color: accent, size: 32),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('أيقونة التطبيق',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 6),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.image_outlined, size: 17),
                            label: const Text('اختيار صورة جديدة'),
                            onPressed: () async {
                              final x = await ImagePicker().pickImage(
                                source: ImageSource.gallery,
                                maxWidth: 1024,
                                maxHeight: 1024,
                              );
                              if (x != null) {
                                setState(() => _iconPath = x.path);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'اسم التطبيق'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _pkgCtrl,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration:
                    const InputDecoration(labelText: 'Package Name / App ID'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _verCtrl,
                      decoration: const InputDecoration(labelText: 'الإصدار'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _buildCtrl,
                      decoration:
                          const InputDecoration(labelText: 'رقم البناء'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.save_rounded),
                label: Text(_saving ? 'جاري الحفظ...' : 'حفظ وتطبيق على المشروع'),
                onPressed: _saving ? null : _saveIdentity,
              ),
            ],
          ),

          // TAB 2: Visual Android Permissions Manager
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'تحكم في صلاحيات AndroidManifest.xml بضغطة واحدة',
                style: TextStyle(fontSize: 12.5, color: Colors.white60),
              ),
              const SizedBox(height: 10),
              ...kAndroidPermissions.map((perm) {
                final on = _activePerms.contains(perm.permission);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ApexCard(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    borderColor: on ? accent.withValues(alpha: 0.45) : kStroke,
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      activeColor: accent,
                      secondary:
                          Icon(perm.icon, color: on ? accent : Colors.white54),
                      title: Text(perm.label,
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        perm.permission,
                        style: const TextStyle(
                            fontSize: 10.5,
                            fontFamily: 'monospace',
                            color: Colors.white38),
                      ),
                      value: on,
                      onChanged: (v) async {
                        await WorkspaceManager.toggleManifestPermission(
                          widget.project,
                          perm.permission,
                          v,
                        );
                        setState(() {
                          if (v) {
                            _activePerms.add(perm.permission);
                          } else {
                            _activePerms.remove(perm.permission);
                          }
                        });
                      },
                    ),
                  ),
                );
              }),
            ],
          ),

          // TAB 3: Visual Pubspec Dependency Manager
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ApexCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('إضافة حزمة مخصصة إلى pubspec.yaml',
                        style: TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _customPkgNameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'اسم الحزمة',
                              hintText: 'http',
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _customPkgVerCtrl,
                            decoration: const InputDecoration(
                              labelText: 'الإصدار',
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('إضافة الحزمة'),
                      onPressed: () async {
                        final n = _customPkgNameCtrl.text.trim();
                        if (n.isEmpty) return;
                        await WorkspaceManager.addPubspecDependency(
                          widget.project,
                          n,
                          _customPkgVerCtrl.text.trim(),
                        );
                        _customPkgNameCtrl.clear();
                        await _loadAll();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Text('الحزم المثبتة حالياً',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              if (_deps.isEmpty)
                const ApexCard(
                  child: Text('لا توجد حزم إضافية في pubspec.yaml بعد',
                      style: TextStyle(color: Colors.white54)),
                )
              else
                ..._deps.entries.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: ApexCard(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        child: Row(
                          children: [
                            Icon(Icons.extension, color: accent, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '${e.key}: ${e.value}',
                                style: const TextStyle(
                                    fontFamily: 'monospace', fontSize: 12.5),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: kCoral, size: 19),
                              onPressed: () async {
                                await WorkspaceManager.removePubspecDependency(
                                    widget.project, e.key);
                                await _loadAll();
                              },
                            ),
                          ],
                        ),
                      ),
                    )),
              const SizedBox(height: 14),
              const Text('حزم Flutter شائعة (إضافة بضغطة واحدة)',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              ...kPopularPackages.map((pkg) {
                final installed = _deps.containsKey(pkg.name);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: ApexCard(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${pkg.name} (${pkg.version})',
                                  style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800)),
                              Text(pkg.desc,
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.white54)),
                            ],
                          ),
                        ),
                        installed
                            ? const ApexPill(text: 'مثبتة', color: kSuccess)
                            : OutlinedButton(
                                onPressed: () async {
                                  await WorkspaceManager.addPubspecDependency(
                                    widget.project,
                                    pkg.name,
                                    pkg.version,
                                  );
                                  await _loadAll();
                                },
                                child: const Text('إضافة'),
                              ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ],
      ),
    );
  }
}
