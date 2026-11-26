import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../core/app_state.dart';
import '../core/app_theme.dart';
import '../services/background_build_service.dart';
import '../services/github_engine.dart';
import '../services/workspace_manager.dart';
import 'github_connect_screen.dart';
import 'network_doctor_screen.dart';

// ============================================================================
// JOOhub — FULL REPOSITORY CONTROL HUB v9.0
// • Complete Repo Control: Edit Name/Description/Homepage/Topics, Instant
//   Private/Public Toggle, Archive/Unarchive, Default Branch, Collaborators,
//   and Safe Permanent Delete Repo
// • Cloud File Explorer: Browse folders, View/Edit files on GitHub, Upload
//   Single/Multiple Files directly to any folder, Create & Delete files
// • Branch Manager (Create / Switch / Delete) + Actions Control (Trigger,
//   Re-run, Cancel, Background Notification Monitor) + Releases Manager
// ============================================================================

class GitHubCloudHubTab extends StatefulWidget {
  const GitHubCloudHubTab({super.key});
  @override
  State<GitHubCloudHubTab> createState() => _GitHubCloudHubTabState();
}

class _GitHubCloudHubTabState extends State<GitHubCloudHubTab> {
  final _newRepoCtrl = TextEditingController();
  final _commitCtrl = TextEditingController(text: 'تحديث من JOOhub');
  final _largeFileCtrl = TextEditingController();

  GitHubApiClient? _api;
  List<GitHubRepo> _repos = [];
  GitHubRepo? _selected;
  List<String> _branches = [];
  String? _selectedBranch;
  List<GitHubCommitSummary> _commits = [];
  List<Map<String, dynamic>> _runs = [];
  List<GitHubReleaseAsset> _assets = [];

  bool _newRepoPrivate = true;
  bool _busy = false;
  late String _uploadMode;
  UploadProgress? _progress;
  GitHubCancelToken? _cancel;
  GitHubException? _lastError;
  VoidCallback? _lastRetryAction;
  final List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    _uploadMode = appState.defaultUploadMode;
    _refreshRepos();
  }

  @override
  void dispose() {
    _newRepoCtrl.dispose();
    _commitCtrl.dispose();
    _largeFileCtrl.dispose();
    _api?.close();
    super.dispose();
  }

  void _log(String s) {
    if (!mounted) return;
    setState(() => _logs.add(s));
  }

  void _captureError(Object e, String opTitle, {VoidCallback? retry}) {
    final diag = GitHubException.diagnose(e, endpoint: opTitle);
    _log('❌ ${diag.title}: ${diag.reason}');
    appState.recordActivity(opTitle, '${diag.title} — ${diag.reason}',
        isError: true);
    if (!mounted) return;
    setState(() {
      _lastError = diag;
      _lastRetryAction = retry;
    });
  }

  Future<void> _refreshRepos({String? selectFullName}) async {
    final acc = appState.activeAccount;
    if (acc == null) return;
    setState(() {
      _busy = true;
      _lastError = null;
    });
    try {
      _api?.close();
      _api = appState.createClientFor(acc);
      final repos = await _api!.listRepos();
      if (!mounted) return;
      GitHubRepo? picked;
      final wanted = selectFullName ?? _selected?.fullName;
      if (wanted != null) {
        for (final r in repos) {
          if (r.fullName == wanted) {
            picked = r;
            break;
          }
        }
      }
      picked ??= repos.isNotEmpty ? repos.first : null;
      setState(() {
        _repos = repos;
        _selected = picked;
        _selectedBranch = picked?.defaultBranch;
      });
      if (_selected != null) await _loadRepoTelemetry();
    } catch (e) {
      _captureError(e, 'تحميل المستودعات', retry: _refreshRepos);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadRepoTelemetry() async {
    if (_api == null || _selected == null) return;
    final owner = _selected!.owner;
    final repo = _selected!.name;
    try {
      final results = await Future.wait<dynamic>([
        _api!.listBranches(owner, repo),
        _api!.listWorkflowRuns(owner, repo, perPage: 6),
        _api!.listApkReleaseAssets(owner, repo),
      ]);
      final branches = results[0] as List<String>;
      final runs = results[1] as List<Map<String, dynamic>>;
      final assets = results[2] as List<GitHubReleaseAsset>;
      final activeBranch = (branches.contains(_selectedBranch))
          ? _selectedBranch!
          : (_selected!.defaultBranch);
      final commits = await _api!.listCommits(
        owner,
        repo,
        branch: activeBranch,
        perPage: 5,
      );
      if (mounted) {
        setState(() {
          _branches = branches.isEmpty ? [activeBranch] : branches;
          _selectedBranch = activeBranch;
          _runs = runs;
          _assets = assets;
          _commits = commits;
        });
      }
    } catch (_) {}
  }

  // ==========================================================================
  // FULL REPOSITORY CONTROL ACTIONS
  // ==========================================================================

  Future<void> _toggleRepoVisibilityQuick() async {
    if (_api == null || _selected == null) return;
    final targetPrivate = !_selected!.isPrivate;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        title: Text(
          targetPrivate ? 'تحويل المستودع إلى خاص 🔒' : 'تحويل المستودع إلى عام 🌐',
          style: const TextStyle(fontSize: 15),
        ),
        content: Text(
          targetPrivate
              ? 'سيصبح «${_selected!.fullName}» خاصاً ولا يراه غيرك والمتعاونين.'
              : 'سيصبح «${_selected!.fullName}» عاماً ومتاحاً للجميع على GitHub.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد التحويل'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final updated = await _api!.updateRepo(
        owner: _selected!.owner,
        repo: _selected!.name,
        isPrivate: targetPrivate,
      );
      _log(targetPrivate
          ? '🔒 تم تحويل ${updated.fullName} إلى مستودع خاص'
          : '🌐 تم تحويل ${updated.fullName} إلى مستودع عام');
      await appState.recordActivity(
        'تغيير خصوصية المستودع',
        '${updated.fullName} -> ${targetPrivate ? "خاص" : "عام"}',
      );
      await _refreshRepos(selectFullName: updated.fullName);
    } catch (e) {
      _captureError(e, 'تغيير خصوصية المستودع');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openEditRepoSheet() async {
    if (_api == null || _selected == null) return;
    final r = _selected!;
    final nameCtrl = TextEditingController(text: r.name);
    final descCtrl = TextEditingController(text: r.description);
    final homeCtrl = TextEditingController(text: r.homepage);
    final topicsCtrl = TextEditingController(text: r.topics.join(', '));
    var isPriv = r.isPrivate;
    var archived = r.archived;
    var hasIssues = r.hasIssues;
    var hasWiki = r.hasWiki;
    var defBranch = r.defaultBranch;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
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
                    Icon(Icons.settings_suggest_rounded,
                        color: appState.primaryColor, size: 19),
                    const SizedBox(width: 7),
                    const Expanded(
                      child: Text(
                        'تعديل إعدادات المستودع بالكامل',
                        style: TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.w900),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => Navigator.pop(ctx, false),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'اسم المستودع'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'وصف المستودع'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: homeCtrl,
                  decoration: const InputDecoration(
                      labelText: 'رابط الموقع (Homepage URL)'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: topicsCtrl,
                  decoration: const InputDecoration(
                    labelText: 'الوسوم (Topics مفصولة بفاصلة)',
                    hintText: 'flutter, android, joohub',
                  ),
                ),
                if (_branches.length > 1) ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _branches.contains(defBranch)
                        ? defBranch
                        : _branches.first,
                    dropdownColor: kSurfaceAlt,
                    decoration:
                        const InputDecoration(labelText: 'الفرع الافتراضي'),
                    items: _branches
                        .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setModal(() => defBranch = v);
                    },
                  ),
                ],
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: appState.primaryColor,
                  title: const Text('مستودع خاص (Private)',
                      style: TextStyle(fontSize: 12.5)),
                  value: isPriv,
                  onChanged: (v) => setModal(() => isPriv = v),
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: kAmber,
                  title: const Text('أرشفة المستودع (Archived / للقراءة فقط)',
                      style: TextStyle(fontSize: 12.5)),
                  value: archived,
                  onChanged: (v) => setModal(() => archived = v),
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: appState.primaryColor,
                  title: const Text('تفعيل Issues',
                      style: TextStyle(fontSize: 12.5)),
                  value: hasIssues,
                  onChanged: (v) => setModal(() => hasIssues = v),
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: appState.primaryColor,
                  title: const Text('تفعيل Wiki',
                      style: TextStyle(fontSize: 12.5)),
                  value: hasWiki,
                  onChanged: (v) => setModal(() => hasWiki = v),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.save_rounded, size: 16),
                  label: const Text('حفظ كل التعديلات على GitHub'),
                  onPressed: () => Navigator.pop(ctx, true),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (saved == true) {
      setState(() => _busy = true);
      try {
        final updated = await _api!.updateRepo(
          owner: r.owner,
          repo: r.name,
          newName: nameCtrl.text.trim(),
          description: descCtrl.text.trim(),
          homepage: homeCtrl.text.trim(),
          isPrivate: isPriv,
          archived: archived,
          defaultBranch: defBranch,
          hasIssues: hasIssues,
          hasWiki: hasWiki,
        );
        final topics = topicsCtrl.text
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        try {
          await _api!.setRepoTopics(updated.owner, updated.name, topics);
        } catch (_) {}
        _log('✅ تم تحديث إعدادات المستودع ${updated.fullName} بنجاح');
        await appState.recordActivity(
          'تعديل المستودع',
          'تم تحديث إعدادات ${updated.fullName}',
        );
        await _refreshRepos(selectFullName: updated.fullName);
      } catch (e) {
        _captureError(e, 'تعديل إعدادات المستودع');
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
    nameCtrl.dispose();
    descCtrl.dispose();
    homeCtrl.dispose();
    topicsCtrl.dispose();
  }

  Future<void> _confirmDeleteRepo() async {
    if (_api == null || _selected == null) return;
    final repo = _selected!;
    final confirmCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('⚠️ حذف المستودع نهائياً',
            style: TextStyle(color: kCoral, fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'سيتم حذف المستودع «${repo.fullName}» بالكامل من GitHub ولا يمكن التراجع!\n\nاكتب اسم المستودع للتأكيد: ${repo.name}',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: confirmCtrl,
              decoration: InputDecoration(hintText: repo.name),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: kCoral, foregroundColor: Colors.white),
            onPressed: () {
              if (confirmCtrl.text.trim() == repo.name) {
                Navigator.pop(ctx, true);
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                      content: Text('اكتب اسم المستودع بشكل مطابق تماماً')),
                );
              }
            },
            child: const Text('حذف نهائي'),
          ),
        ],
      ),
    );
    confirmCtrl.dispose();
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await _api!.deleteRepo(repo.owner, repo.name);
      _log('🗑️ تم حذف المستودع ${repo.fullName} نهائياً');
      await appState.recordActivity('حذف مستودع', 'تم حذف ${repo.fullName}');
      setState(() => _selected = null);
      await _refreshRepos();
    } catch (e) {
      _captureError(e, 'حذف المستودع');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openCloudFileExplorer() async {
    if (_api == null || _selected == null) return;
    final repo = _selected!;
    final branch = _selectedBranch ?? repo.defaultBranch;
    var curPath = '';
    List<GitHubContentEntry> entries = [];
    var loading = true;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          Future<void> loadDir(String path) async {
            setModal(() {
              loading = true;
              curPath = path;
            });
            try {
              final list = await _api!.listRepoContents(
                repo.owner,
                repo.name,
                path: path,
                ref: branch,
              );
              setModal(() {
                entries = list;
                loading = false;
              });
            } catch (e) {
              setModal(() => loading = false);
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx)
                    .showSnackBar(SnackBar(content: Text('خطأ: $e')));
              }
            }
          }

          if (loading && entries.isEmpty) {
            Future.microtask(() => loadDir(curPath));
          }

          return SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.78,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                  child: Row(
                    children: [
                      if (curPath.isNotEmpty)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                          onPressed: () {
                            final parent = curPath.contains('/')
                                ? curPath.substring(0, curPath.lastIndexOf('/'))
                                : '';
                            loadDir(parent);
                          },
                        ),
                      Expanded(
                        child: Text(
                          '${repo.name}/${curPath.isEmpty ? "" : curPath}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              fontFamily: 'monospace'),
                        ),
                      ),
                      IconButton(
                        tooltip: 'رفع ملف مباشر للمجلد الحالي',
                        icon: Icon(Icons.upload_file_rounded,
                            color: appState.primaryColor, size: 20),
                        onPressed: () async {
                          final picked = await FilePicker.platform
                              .pickFiles(allowMultiple: true);
                          if (picked == null || picked.files.isEmpty) return;
                          for (final pf in picked.files) {
                            if (pf.path == null) continue;
                            final f = File(pf.path!);
                            final targetPath = curPath.isEmpty
                                ? p.basename(f.path)
                                : '$curPath/${p.basename(f.path)}';
                            await _api!.putRepoFileBytes(
                              owner: repo.owner,
                              repo: repo.name,
                              repoPath: targetPath,
                              bytes: await f.readAsBytes(),
                              message: 'Upload $targetPath via JOOhub',
                              branch: branch,
                            );
                          }
                          await loadDir(curPath);
                        },
                      ),
                      IconButton(
                        tooltip: 'ملف نصي جديد',
                        icon: const Icon(Icons.note_add_outlined, size: 20),
                        onPressed: () async {
                          final nameC = TextEditingController();
                          final bodyC = TextEditingController();
                          final ok = await showDialog<bool>(
                            context: ctx,
                            builder: (dCtx) => AlertDialog(
                              backgroundColor: kSurface,
                              title: const Text('إنشاء ملف على GitHub',
                                  style: TextStyle(fontSize: 14.5)),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextField(
                                    controller: nameC,
                                    decoration: const InputDecoration(
                                        labelText: 'اسم الملف'),
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: bodyC,
                                    maxLines: 5,
                                    decoration: const InputDecoration(
                                        labelText: 'المحتوى'),
                                  ),
                                ],
                              ),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(dCtx, false),
                                    child: const Text('إلغاء')),
                                FilledButton(
                                    onPressed: () => Navigator.pop(dCtx, true),
                                    child: const Text('حفظ على GitHub')),
                              ],
                            ),
                          );
                          if (ok == true && nameC.text.trim().isNotEmpty) {
                            final rp = curPath.isEmpty
                                ? nameC.text.trim()
                                : '$curPath/${nameC.text.trim()}';
                            await _api!.putRepoFileBytes(
                              owner: repo.owner,
                              repo: repo.name,
                              repoPath: rp,
                              bytes: utf8.encode(bodyC.text),
                              message: 'Create $rp via JOOhub',
                              branch: branch,
                            );
                            await loadDir(curPath);
                          }
                          nameC.dispose();
                          bodyC.dispose();
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: kStroke),
                Expanded(
                  child: loading
                      ? const Center(child: CircularProgressIndicator())
                      : entries.isEmpty
                          ? const Center(child: Text('المجلد فارغ'))
                          : ListView.builder(
                              itemCount: entries.length,
                              itemBuilder: (_, i) {
                                final e = entries[i];
                                final isDir = e.type == 'dir';
                                return ListTile(
                                  dense: true,
                                  leading: Icon(
                                    isDir
                                        ? Icons.folder_rounded
                                        : Icons.description_outlined,
                                    color: isDir
                                        ? appState.primaryColor
                                        : Colors.white60,
                                    size: 18,
                                  ),
                                  title: Text(e.name,
                                      style: const TextStyle(
                                          fontSize: 12.5,
                                          fontFamily: 'monospace')),
                                  subtitle: isDir
                                      ? null
                                      : Text(GitHubApiClient.fmtBytes(e.size),
                                          style: const TextStyle(fontSize: 10)),
                                  trailing: isDir
                                      ? const Icon(Icons.chevron_left_rounded,
                                          size: 18)
                                      : IconButton(
                                          icon: const Icon(Icons.delete_outline,
                                              size: 17, color: kCoral),
                                          onPressed: () async {
                                            await _api!.deleteRepoFile(
                                              owner: repo.owner,
                                              repo: repo.name,
                                              repoPath: e.path,
                                              sha: e.sha,
                                              message:
                                                  'Delete ${e.path} via JOOhub',
                                              branch: branch,
                                            );
                                            await loadDir(curPath);
                                          },
                                        ),
                                  onTap: () async {
                                    if (isDir) {
                                      await loadDir(e.path);
                                    } else {
                                      try {
                                        final data = await _api!
                                            .getRepoFileText(
                                          repo.owner,
                                          repo.name,
                                          e.path,
                                          ref: branch,
                                        );
                                        if (!ctx.mounted) return;
                                        final editCtrl = TextEditingController(
                                            text: data.content);
                                        final save = await showDialog<bool>(
                                          context: ctx,
                                          builder: (dCtx) => AlertDialog(
                                            backgroundColor: kSurface,
                                            title: Text(e.name,
                                                style: const TextStyle(
                                                    fontSize: 14)),
                                            content: SizedBox(
                                              width: double.maxFinite,
                                              child: Directionality(
                                                textDirection:
                                                    TextDirection.ltr,
                                                child: TextField(
                                                  controller: editCtrl,
                                                  maxLines: 14,
                                                  style: const TextStyle(
                                                      fontFamily: 'monospace',
                                                      fontSize: 11.5),
                                                ),
                                              ),
                                            ),
                                            actions: [
                                              TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                          dCtx, false),
                                                  child: const Text('إغلاق')),
                                              FilledButton(
                                                  onPressed: () =>
                                                      Navigator.pop(dCtx, true),
                                                  child: const Text(
                                                      'حفظ على GitHub')),
                                            ],
                                          ),
                                        );
                                        if (save == true) {
                                          await _api!.putRepoFileBytes(
                                            owner: repo.owner,
                                            repo: repo.name,
                                            repoPath: e.path,
                                            bytes: utf8.encode(editCtrl.text),
                                            message:
                                                'Edit ${e.path} via JOOhub',
                                            branch: branch,
                                            existingSha: data.sha,
                                          );
                                          await loadDir(curPath);
                                        }
                                        editCtrl.dispose();
                                      } catch (err) {
                                        if (ctx.mounted) {
                                          ScaffoldMessenger.of(ctx)
                                              .showSnackBar(SnackBar(
                                                  content: Text('$err')));
                                        }
                                      }
                                    }
                                  },
                                );
                              },
                            ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _openCollaboratorsSheet() async {
    if (_api == null || _selected == null) return;
    final repo = _selected!;
    final userCtrl = TextEditingController();
    List<Map<String, dynamic>> collabs =
        await _api!.listCollaborators(repo.owner, repo.name);
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.fromLTRB(
            14,
            14,
            14,
            MediaQuery.of(ctx).viewInsets.bottom + 14,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'إدارة المتعاونين (Collaborators)',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: userCtrl,
                      decoration: const InputDecoration(
                          hintText: 'اسم مستخدم GitHub...'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  FilledButton(
                    onPressed: () async {
                      if (userCtrl.text.trim().isEmpty) return;
                      try {
                        await _api!.addCollaborator(
                            repo.owner, repo.name, userCtrl.text.trim());
                        userCtrl.clear();
                        collabs = await _api!
                            .listCollaborators(repo.owner, repo.name);
                        setModal(() {});
                      } catch (e) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx)
                              .showSnackBar(SnackBar(content: Text('$e')));
                        }
                      }
                    },
                    child: const Text('إضافة'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...collabs.map((c) {
                final login = (c['login'] ?? '').toString();
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_outline, size: 18),
                  title: Text('@$login', style: const TextStyle(fontSize: 12.5)),
                  trailing: login != repo.owner
                      ? IconButton(
                          icon: const Icon(Icons.remove_circle_outline,
                              color: kCoral, size: 18),
                          onPressed: () async {
                            await _api!
                                .removeCollaborator(repo.owner, repo.name, login);
                            collabs = await _api!
                                .listCollaborators(repo.owner, repo.name);
                            setModal(() {});
                          },
                        )
                      : ApexPill(text: 'المالك', color: appState.primaryColor),
                );
              }),
            ],
          ),
        ),
      ),
    );
    userCtrl.dispose();
  }

  Future<void> _openCreateBranchDialog() async {
    if (_api == null || _selected == null) return;
    final ctrl = TextEditingController();
    final createdName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('إنشاء فرع جديد (Branch)',
            style: TextStyle(fontSize: 15)),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(
            labelText: 'اسم الفرع الجديد (مثال: dev)',
            helperText:
                'سيتفرع من: ${_selectedBranch ?? _selected!.defaultBranch}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('إنشاء'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (createdName == null || createdName.isEmpty) return;
    setState(() => _busy = true);
    try {
      await _api!.createBranch(
        owner: _selected!.owner,
        repo: _selected!.name,
        newBranch: createdName,
        fromBranch: _selectedBranch ?? _selected!.defaultBranch,
      );
      _log('🌿 تم إنشاء الفرع الجديد: $createdName');
      setState(() => _selectedBranch = createdName);
      await _loadRepoTelemetry();
    } catch (e) {
      _captureError(e, 'إنشاء فرع جديد');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteCurrentBranch() async {
    if (_api == null || _selected == null || _selectedBranch == null) return;
    if (_selectedBranch == _selected!.defaultBranch) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يمكن حذف الفرع الافتراضي للمستودع')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await _api!.deleteBranch(
          _selected!.owner, _selected!.name, _selectedBranch!);
      _log('🗑️ تم حذف الفرع $_selectedBranch');
      setState(() => _selectedBranch = _selected!.defaultBranch);
      await _loadRepoTelemetry();
    } catch (e) {
      _captureError(e, 'حذف الفرع');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createNewRepo() async {
    if (_api == null) return;
    final name = _newRepoCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    try {
      final repo = await _api!.createRepo(name, isPrivate: _newRepoPrivate);
      _newRepoCtrl.clear();
      _log('🆕 تم إنشاء المستودع: ${repo.fullName}');
      await _refreshRepos(selectFullName: repo.fullName);
    } catch (e) {
      _captureError(e, 'إنشاء مستودع جديد');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncActiveProject() async {
    final proj = appState.activeProject;
    if (_api == null || _selected == null || proj == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('اختر مشروعاً من «مشاريعي» ومستودعاً أولاً'),
        ),
      );
      return;
    }
    _cancel = GitHubCancelToken();
    setState(() {
      _busy = true;
      _lastError = null;
      _progress = null;
    });
    try {
      if (appState.backgroundBuildEnabled) {
        await BackgroundBuildService.startUploadNotification(
          title: 'جاري رفع ${proj.name}',
          subtitle: _uploadMode == 'file_by_file'
              ? 'الرفع الآمن ملف ملف...'
              : 'الرفع المرحلي الذكي...',
          progress: 0,
          indeterminate: false,
        );
      }

      void onProg(UploadProgress prog) {
        if (mounted) setState(() => _progress = prog);
        if (appState.backgroundBuildEnabled) {
          BackgroundBuildService.updateProgress(
            title: 'جاري رفع ${proj.name}',
            subtitle:
                '${prog.completedFiles}/${prog.totalFiles} • ${prog.currentFile}',
            progress: (prog.fraction * 100).round().clamp(0, 100),
            indeterminate: false,
          );
        }
      }

      final String sha;
      if (_uploadMode == 'file_by_file') {
        sha = await _api!.syncDirectoryFileByFile(
          projectDir: Directory(proj.path),
          repo: _selected!,
          targetBranch: _selectedBranch,
          commitMessage: _commitCtrl.text.trim(),
          cancelToken: _cancel,
          onLog: _log,
          onProgress: onProg,
        );
      } else {
        sha = await _api!.syncDirectoryToRepo(
          projectDir: Directory(proj.path),
          repo: _selected!,
          targetBranch: _selectedBranch,
          commitMessage: _commitCtrl.text.trim(),
          batchSize: appState.uploadBatchSize,
          useCheckpoint: appState.enableCheckpoints,
          cancelToken: _cancel,
          onLog: _log,
          onProgress: onProg,
        );
      }
      await BackgroundBuildService.stop();
      final shortSha = sha.length >= 7 ? sha.substring(0, 7) : sha;
      _log('🎉 اكتمل رفع المشروع بنجاح • Commit: $shortSha');
      await appState.recordActivity(
        'رفع مشروع إلى GitHub',
        'تم رفع ${proj.name} إلى ${_selected!.fullName} • $shortSha',
      );
      await _loadRepoTelemetry();
    } catch (e) {
      await BackgroundBuildService.stop();
      _captureError(e, 'رفع المشروع إلى GitHub', retry: _syncActiveProject);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _triggerApkBuildNow() async {
    if (_api == null || _selected == null) return;
    setState(() {
      _busy = true;
      _lastError = null;
    });
    try {
      final ref = _selectedBranch ?? _selected!.defaultBranch;
      var ok = await _api!.triggerWorkflow(
        owner: _selected!.owner,
        repo: _selected!.name,
        workflowFileName: 'joohub_build_apk.yml',
        ref: ref,
      );
      if (!ok) {
        ok = await _api!.triggerWorkflow(
          owner: _selected!.owner,
          repo: _selected!.name,
          workflowFileName: 'build.yml',
          ref: ref,
        );
      }
      _log(ok
          ? '🚀 تم تشغيل بناء APK على GitHub Actions بنجاح!'
          : '⚠️ لم نجد ملف Workflow للبناء — أضفه من استوديو APK أو طبيب المشروع.');
      if (ok && appState.backgroundBuildEnabled && appState.activeAccount != null) {
        await BackgroundBuildService.startCloudBuildMonitor(
          owner: _selected!.owner,
          repo: _selected!.name,
          token: appState.activeAccount!.session.accessToken,
          appName: _selected!.name,
          pollSeconds: appState.backgroundPollSeconds,
        );
        _log('🔔 تم تفعيل إشعار «جاري البناء» المتحرك في الخلفية!');
      }
      await Future<void>.delayed(const Duration(seconds: 2));
      await _loadRepoTelemetry();
    } catch (e) {
      _captureError(e, 'تشغيل بناء APK', retry: _triggerApkBuildNow);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cloneSelectedRepo() async {
    if (_api == null || _selected == null) return;
    setState(() => _busy = true);
    try {
      final owner = _selected!.owner;
      final repo = _selected!.name;
      final branch = _selectedBranch ?? _selected!.defaultBranch;
      _log('⬇️ سحب المستودع $owner/$repo ($branch) إلى الجهاز...');

      final treeRes = await _api!.requestJsonFull(
        'GET',
        '/repos/$owner/$repo/git/trees/$branch?recursive=1',
      );
      if (treeRes.status != 200 || treeRes.body is! Map<String, dynamic>) {
        throw Exception('تعذّر قراءة شجرة المستودع');
      }
      final blobs = ((treeRes.body as Map)['tree'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .where((e) => e['type'] == 'blob')
          .toList();

      final root = await WorkspaceManager.workspaceRoot();
      final targetDir = Directory(p.join(root.path, repo));
      await targetDir.create(recursive: true);

      var count = 0;
      for (final b in blobs) {
        final relPath = b['path'].toString();
        final sha = b['sha'].toString();
        final blobRes = await _api!
            .requestJsonFull('GET', '/repos/$owner/$repo/git/blobs/$sha');
        if (blobRes.status == 200 && blobRes.body is Map<String, dynamic>) {
          final b64 = ((blobRes.body as Map)['content'] ?? '')
              .toString()
              .replaceAll('\n', '');
          final file = File(p.join(targetDir.path, relPath));
          await file.parent.create(recursive: true);
          await file.writeAsBytes(base64Decode(b64));
          count++;
        }
      }
      appState.setActiveProject(LocalProject(
        name: repo,
        path: targetDir.path,
        modifiedAt: DateTime.now(),
      ));
      _log('✅ تم سحب $count ملف إلى مجلد «$repo» بنجاح!');
    } catch (e) {
      _captureError(e, 'سحب المستودع للموبايل', retry: _cloneSelectedRepo);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uploadDirect500MB() async {
    if (_api == null || _selected == null) return;
    final f = File(_largeFileCtrl.text.trim());
    if (!await f.exists()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر الملف أولاً')),
      );
      return;
    }
    _cancel = GitHubCancelToken();
    setState(() => _busy = true);
    try {
      final relId = await _api!.getOrCreateReleaseId(
        owner: _selected!.owner,
        repo: _selected!.name,
        tag: 'joohub-files',
      );
      final url = await _api!.streamUploadReleaseAsset(
        owner: _selected!.owner,
        repo: _selected!.name,
        releaseId: relId,
        file: f,
        cancelToken: _cancel,
      );
      _log('✅ تم رفع الملف الكبير بنجاح: $url');
      await _loadRepoTelemetry();
    } catch (e) {
      _captureError(e, 'رفع ملف 500MB');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = appState.primaryColor;
    final acc = appState.activeAccount;

    if (acc == null) {
      return SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.hub_rounded, size: 52, color: accent),
                const SizedBox(height: 12),
                const Text(
                  'اربط حسابك على GitHub للتحكم الكامل بالمستودعات وبناء APK',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  icon: const Icon(Icons.login_rounded, size: 17),
                  label: const Text('تسجيل الدخول إلى GitHub'),
                  onPressed: () async {
                    final ok = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                          builder: (_) => const GitHubConnectScreen()),
                    );
                    if (ok == true) _refreshRepos();
                  },
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SafeArea(
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: const BoxDecoration(
              color: kSurface,
              border: Border(bottom: BorderSide(color: kStroke)),
            ),
            child: Row(
              children: [
                Icon(Icons.hub_rounded, color: accent, size: 18),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'GitHub • @${acc.login}',
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.network_check_rounded,
                      color: kSuccess, size: 19),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const NetworkDoctorScreen()),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.refresh_rounded, size: 19),
                  onPressed: _busy ? null : () => _refreshRepos(),
                ),
              ],
            ),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                // ============================================================
                // 1. REPOSITORY SELECTOR + FULL CONTROL PANEL
                // ============================================================
                ApexCard(
                  borderColor: accent.withValues(alpha: 0.35),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_repos.isNotEmpty)
                        DropdownButtonFormField<GitHubRepo>(
                          value: _selected,
                          dropdownColor: kSurface,
                          decoration: const InputDecoration(
                            labelText: 'المستودع النشط',
                          ),
                          items: _repos
                              .map((r) => DropdownMenuItem(
                                    value: r,
                                    child: Text(
                                      '${r.isPrivate ? "🔒" : "🌐"} ${r.fullName}${r.archived ? " (مؤرشف)" : ""}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ))
                              .toList(),
                          onChanged: (v) async {
                            if (v == null) return;
                            setState(() {
                              _selected = v;
                              _selectedBranch = v.defaultBranch;
                            });
                            await _loadRepoTelemetry();
                          },
                        ),
                      if (_selected != null) ...[
                        const SizedBox(height: 8),
                        if (_selected!.description.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              _selected!.description,
                              style: const TextStyle(
                                  fontSize: 11.5, color: Colors.white70),
                            ),
                          ),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            ActionChipBtn(
                              icon: _selected!.isPrivate
                                  ? Icons.lock_rounded
                                  : Icons.public_rounded,
                              label: _selected!.isPrivate
                                  ? 'خاص (اجعله عام)'
                                  : 'عام (اجعله خاص)',
                              color: _selected!.isPrivate ? kAmber : kSuccess,
                              onTap: _busy ? () {} : _toggleRepoVisibilityQuick,
                            ),
                            ActionChipBtn(
                              icon: Icons.edit_note_rounded,
                              label: 'تعديل المستودع',
                              color: accent,
                              onTap: _busy ? () {} : _openEditRepoSheet,
                            ),
                            ActionChipBtn(
                              icon: Icons.folder_open_rounded,
                              label: 'ملفات المستودع',
                              color: kSky,
                              onTap: _busy ? () {} : _openCloudFileExplorer,
                            ),
                            ActionChipBtn(
                              icon: Icons.group_add_outlined,
                              label: 'المتعاونون',
                              color: Colors.white70,
                              onTap: _busy ? () {} : _openCollaboratorsSheet,
                            ),
                            ActionChipBtn(
                              icon: Icons.download_rounded,
                              label: 'سحب للموبايل',
                              color: kSuccess,
                              onTap: _busy ? () {} : _cloneSelectedRepo,
                            ),
                            ActionChipBtn(
                              icon: Icons.delete_forever_rounded,
                              label: 'حذف المستودع',
                              color: kCoral,
                              onTap: _busy ? () {} : _confirmDeleteRepo,
                            ),
                          ],
                        ),
                        const Divider(color: kStroke, height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _branches.contains(_selectedBranch)
                                    ? _selectedBranch
                                    : (_branches.isNotEmpty
                                        ? _branches.first
                                        : null),
                                dropdownColor: kSurface,
                                decoration:
                                    const InputDecoration(labelText: 'الفرع'),
                                items: _branches
                                    .map((b) => DropdownMenuItem(
                                        value: b, child: Text(b)))
                                    .toList(),
                                onChanged: (v) async {
                                  setState(() => _selectedBranch = v);
                                  await _loadRepoTelemetry();
                                },
                              ),
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              tooltip: 'إنشاء فرع جديد',
                              icon: Icon(Icons.add_circle_outline,
                                  color: accent),
                              onPressed: _openCreateBranchDialog,
                            ),
                            IconButton(
                              tooltip: 'حذف الفرع الحالي',
                              icon: const Icon(Icons.delete_outline,
                                  color: kCoral),
                              onPressed: _deleteCurrentBranch,
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // ============================================================
                // 2. CREATE NEW REPO
                // ============================================================
                ApexCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('إنشاء مستودع جديد',
                          style: TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _newRepoCtrl,
                              decoration: const InputDecoration(
                                  hintText: 'اسم المستودع الجديد...'),
                            ),
                          ),
                          const SizedBox(width: 6),
                          FilterChip(
                            label: Text(_newRepoPrivate ? 'خاص' : 'عام',
                                style: const TextStyle(fontSize: 11)),
                            selected: _newRepoPrivate,
                            onSelected: (v) =>
                                setState(() => _newRepoPrivate = v),
                          ),
                          const SizedBox(width: 6),
                          FilledButton(
                            onPressed: _busy ? null : _createNewRepo,
                            child: const Text('إنشاء'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // ============================================================
                // 3. SYNC ACTIVE PROJECT & TRIGGER BACKGROUND APK BUILD
                // ============================================================
                ApexCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'رفع المشروع النشط: ${appState.activeProject?.name ?? "غير محدد"}',
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _commitCtrl,
                        decoration:
                            const InputDecoration(labelText: 'رسالة الـ Commit'),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        children: [
                          ChoiceChip(
                            visualDensity: VisualDensity.compact,
                            label: const Text('ملف ملف (آمن)',
                                style: TextStyle(fontSize: 11)),
                            selected: _uploadMode == 'file_by_file',
                            selectedColor: accent.withValues(alpha: 0.25),
                            onSelected: (_) =>
                                setState(() => _uploadMode = 'file_by_file'),
                          ),
                          ChoiceChip(
                            visualDensity: VisualDensity.compact,
                            label: const Text('دفعات 5 مراحل',
                                style: TextStyle(fontSize: 11)),
                            selected: _uploadMode == 'staged_batch',
                            selectedColor: accent.withValues(alpha: 0.25),
                            onSelected: (_) =>
                                setState(() => _uploadMode = 'staged_batch'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              icon: const Icon(Icons.cloud_upload_rounded,
                                  size: 16),
                              label: const Text('رفع المشروع'),
                              onPressed: _busy ? null : _syncActiveProject,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: Icon(Icons.android_rounded,
                                  color: kSuccess, size: 16),
                              label: const Text('بناء APK بالخلفية'),
                              onPressed: _busy ? null : _triggerApkBuildNow,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                if (_progress != null) ...[
                  const SizedBox(height: 10),
                  StagedUploadCard(
                    progress: _progress!,
                    accent: accent,
                    onTogglePause: () {
                      if (_cancel == null) return;
                      setState(() {
                        if (_cancel!.isPaused) {
                          _cancel!.resume();
                        } else {
                          _cancel!.pause();
                        }
                      });
                    },
                    onCancel: () {
                      _cancel?.cancel();
                      BackgroundBuildService.stop();
                    },
                  ),
                ],

                if (_lastError != null) ...[
                  const SizedBox(height: 10),
                  ErrorDiagnosticCard(
                    error: _lastError!,
                    onRetry: _lastRetryAction,
                  ),
                ],

                // ============================================================
                // 4. GITHUB ACTIONS RUNS (RE-RUN / CANCEL / BG MONITOR)
                // ============================================================
                if (_runs.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ApexCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('عمليات البناء (GitHub Actions)',
                            style: TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 6),
                        ..._runs.map((r) {
                          final runId = (r['id'] as num?)?.toInt() ?? 0;
                          final st = (r['conclusion'] ?? r['status'] ?? '')
                              .toString();
                          final activeRun = r['status'] == 'in_progress' ||
                              r['status'] == 'queued';
                          final col = st == 'success'
                              ? kSuccess
                              : (st == 'failure' ? kCoral : accent);
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              st == 'success'
                                  ? Icons.check_circle
                                  : (st == 'failure'
                                      ? Icons.cancel
                                      : Icons.timelapse),
                              color: col,
                              size: 18,
                            ),
                            title: Text((r['name'] ?? 'Workflow').toString(),
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w700)),
                            subtitle: Text(st, style: TextStyle(fontSize: 10.5, color: col)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (activeRun)
                                  IconButton(
                                    tooltip: 'إلغاء البناء',
                                    icon: const Icon(Icons.stop_circle_outlined,
                                        color: kCoral, size: 18),
                                    onPressed: () async {
                                      await _api!.cancelWorkflowRun(
                                          _selected!.owner,
                                          _selected!.name,
                                          runId);
                                      await _loadRepoTelemetry();
                                    },
                                  )
                                else
                                  IconButton(
                                    tooltip: 'إعادة تشغيل',
                                    icon: const Icon(Icons.replay_rounded,
                                        size: 18),
                                    onPressed: () async {
                                      await _api!.rerunWorkflowRun(
                                          _selected!.owner,
                                          _selected!.name,
                                          runId);
                                      if (appState.backgroundBuildEnabled) {
                                        await BackgroundBuildService
                                            .startCloudBuildMonitor(
                                          owner: _selected!.owner,
                                          repo: _selected!.name,
                                          token: acc.session.accessToken,
                                          appName: _selected!.name,
                                          pollSeconds:
                                              appState.backgroundPollSeconds,
                                        );
                                      }
                                      await _loadRepoTelemetry();
                                    },
                                  ),
                              ],
                            ),
                            onTap: () {
                              final u = (r['html_url'] ?? '').toString();
                              if (u.isNotEmpty) {
                                launchUrl(Uri.parse(u),
                                    mode: LaunchMode.inAppBrowserView);
                              }
                            },
                          );
                        }),
                      ],
                    ),
                  ),
                ],

                // ============================================================
                // 5. RELEASES & 500MB DIRECT UPLOAD
                // ============================================================
                const SizedBox(height: 10),
                ApexCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('الإصدارات وملفات APK (ورفع حتى 500MB)',
                          style: TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _largeFileCtrl,
                              decoration: const InputDecoration(
                                  hintText: 'اختر ملف كبير لرفعه في Releases...'),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.attach_file_rounded),
                            onPressed: () async {
                              final res = await FilePicker.platform.pickFiles();
                              if (res != null &&
                                  res.files.isNotEmpty &&
                                  res.files.single.path != null) {
                                setState(() => _largeFileCtrl.text =
                                    res.files.single.path!);
                              }
                            },
                          ),
                          FilledButton(
                            onPressed: _busy ? null : _uploadDirect500MB,
                            child: const Text('رفع'),
                          ),
                        ],
                      ),
                      if (_assets.isNotEmpty) ...[
                        const Divider(color: kStroke, height: 12),
                        ..._assets.take(8).map((a) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.android_rounded,
                                  color: kSuccess, size: 18),
                              title: Text(a.name,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700)),
                              subtitle: Text(
                                  '${GitHubApiClient.fmtBytes(a.size)} • ${a.tagName}',
                                  style: const TextStyle(fontSize: 10)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.download_rounded,
                                        color: kSuccess, size: 18),
                                    onPressed: () => launchUrl(
                                      Uri.parse(a.downloadUrl),
                                      mode: LaunchMode.externalApplication,
                                    ),
                                  ),
                                  if (a.assetId > 0)
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          color: kCoral, size: 18),
                                      onPressed: () async {
                                        await _api!.deleteReleaseAsset(
                                            _selected!.owner,
                                            _selected!.name,
                                            a.assetId);
                                        await _loadRepoTelemetry();
                                      },
                                    ),
                                ],
                              ),
                            )),
                      ],
                    ],
                  ),
                ),

                // Commits + Logs
                if (_commits.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ApexCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('آخر التعديلات (Commits)',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 6),
                        ..._commits.map((c) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '• ${c.sha.substring(0, c.sha.length >= 7 ? 7 : c.sha.length)} — ${c.message.split('\n').first}',
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.white70),
                              ),
                            )),
                      ],
                    ),
                  ),
                ],
                if (_logs.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ApexCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _logs.reversed
                          .take(15)
                          .map((l) => Text(l,
                              style: const TextStyle(
                                  fontSize: 10.5,
                                  fontFamily: 'monospace',
                                  color: Colors.white60)))
                          .toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
