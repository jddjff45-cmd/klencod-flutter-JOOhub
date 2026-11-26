import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../core/app_state.dart';
import '../core/app_theme.dart';
import '../services/background_build_service.dart';
import '../services/github_engine.dart';
import '../services/workspace_manager.dart';
import '../services/zip_engine.dart';
import 'github_connect_screen.dart';
import 'network_doctor_screen.dart';

// ============================================================================
// JOOhub — MULTI-METHOD FILE UPLOAD & BACKGROUND APK BUILDER STUDIO v9.0
// 4 Source Methods:
//   1. ملف ملف (File-by-File / Multi-File Queue with Smart Path Editor)
//   2. ملف ZIP (Pick / Scan Device / Direct URL -> Auto-Extract & Flatten)
//   3. مشروع محلي (Pick any existing project from JOOhub Workspace)
//   4. لصق كود فوري (Paste main.dart -> Auto-Scaffold & Build APK)
// 2 Upload Engines:
//   • File-by-File Safe Mode (PUT /contents one-by-one with SHA auto-resolve)
//   • 5-Stage Staged Batch Engine (SHA-1 diff + Checkpoint recovery)
// Background Build Service:
//   • Animated "جاري البناء..." Android Notification even when app is closed!
// ============================================================================

class _StagedUploadItem {
  final File file;
  String repoPath;
  final int sizeBytes;

  _StagedUploadItem({
    required this.file,
    required this.repoPath,
    required this.sizeBytes,
  });
}

class ZipApkStudioTab extends StatefulWidget {
  final VoidCallback? onProjectExtracted;
  const ZipApkStudioTab({super.key, this.onProjectExtracted});

  @override
  State<ZipApkStudioTab> createState() => _ZipApkStudioTabState();
}

class _ZipApkStudioTabState extends State<ZipApkStudioTab> {
  // 0 = File-by-File, 1 = ZIP, 2 = Local Project, 3 = Paste Code
  int _sourceMode = 0;

  // 'file_by_file' | 'staged_batch'
  late String _uploadStrategy;

  final _urlCtrl = TextEditingController();
  final _appNameCtrl = TextEditingController();
  final _pkgCtrl = TextEditingController(text: 'com.yossefjoo.app');
  final _newRepoCtrl = TextEditingController();
  final _quickCodeCtrl = TextEditingController();

  // File-by-File queue
  final List<_StagedUploadItem> _queuedFiles = [];

  // Local projects
  List<LocalProject> _localProjects = [];

  // Prepared project (from ZIP, Local, or Paste Code)
  File? _selectedZip;
  ZipExtractResult? _extractResult;
  LocalProject? _preparedProject;
  String? _iconPath;
  String _buildMode = 'release_apk';
  bool _injectWorkflow = true;
  bool _flattenRoot = true;

  bool _working = false;
  String _statusText = '';
  double _progressVal = 0.0;
  UploadProgress? _uploadProgress;
  GitHubException? _lastError;
  final List<String> _logs = [];

  GitHubApiClient? _api;
  List<GitHubRepo> _repos = [];
  GitHubRepo? _targetRepo;
  List<Map<String, dynamic>> _latestRuns = [];
  List<GitHubReleaseAsset> _apkAssets = [];
  Timer? _pollTimer;
  GitHubCancelToken? _cancel;

  @override
  void initState() {
    super.initState();
    _uploadStrategy = appState.defaultUploadMode;
    _loadRepos();
    _loadLocalProjects();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _urlCtrl.dispose();
    _appNameCtrl.dispose();
    _pkgCtrl.dispose();
    _newRepoCtrl.dispose();
    _quickCodeCtrl.dispose();
    _api?.close();
    super.dispose();
  }

  void _log(String msg) {
    if (!mounted) return;
    setState(() => _logs.add(msg));
  }

  Future<void> _loadLocalProjects() async {
    final list = await WorkspaceManager.listProjects();
    if (!mounted) return;
    setState(() => _localProjects = list);
  }

  Future<void> _loadRepos() async {
    final acc = appState.activeAccount;
    if (acc == null) return;
    try {
      _api?.close();
      _api = appState.createClientFor(acc);
      final list = await _api!.listRepos();
      if (!mounted) return;
      setState(() {
        _repos = list;
        if (_targetRepo == null && list.isNotEmpty) _targetRepo = list.first;
      });
    } catch (_) {}
  }

  // ==========================================================================
  // METHOD 1: FILE-BY-FILE / MULTI-FILE QUEUE
  // ==========================================================================
  String _guessSmartRepoPath(String fileName) {
    final low = fileName.toLowerCase();
    if (low == 'pubspec.yaml' || low == 'readme.md' || low == '.gitignore') {
      return fileName;
    }
    if (low == 'main.dart') return 'lib/main.dart';
    if (low.endsWith('.dart')) return 'lib/$fileName';
    if (low == 'androidmanifest.xml') {
      return 'android/app/src/main/AndroidManifest.xml';
    }
    if (low == 'build.gradle.kts' || low == 'build.gradle') {
      return 'android/app/$fileName';
    }
    if (low.endsWith('.yml') || low.endsWith('.yaml')) {
      return '.github/workflows/$fileName';
    }
    if (low.endsWith('.png') || low.endsWith('.jpg') || low.endsWith('.svg')) {
      return 'assets/$fileName';
    }
    return fileName;
  }

  Future<void> _pickSingleOrMultiFiles({required bool allowMultiple}) async {
    try {
      final res = await FilePicker.platform.pickFiles(
        allowMultiple: allowMultiple,
      );
      if (res == null || res.files.isEmpty) return;
      var added = 0;
      for (final pf in res.files) {
        if (pf.path == null) continue;
        final f = File(pf.path!);
        if (!await f.exists()) continue;
        final sz = await f.length();
        final repoPath = _guessSmartRepoPath(p.basename(f.path));
        _queuedFiles.removeWhere((e) => e.repoPath == repoPath);
        _queuedFiles.add(
          _StagedUploadItem(file: f, repoPath: repoPath, sizeBytes: sz),
        );
        added++;
      }
      if (mounted) {
        setState(() {});
        _log('📄 تمت إضافة $added ملف إلى قائمة الرفع ملف ملف (الإجمالي: ${_queuedFiles.length})');
      }
    } catch (e) {
      _log('❌ تعذّر اختيار الملفات: $e');
    }
  }

  Future<void> _editQueuedItemPath(_StagedUploadItem item) async {
    final ctrl = TextEditingController(text: item.repoPath);
    final updated = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('تعديل مسار الملف داخل المستودع',
            style: TextStyle(fontSize: 14.5)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          decoration: const InputDecoration(
            labelText: 'المسار النسبي (مثال: lib/screens/home.dart)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('حفظ المسار'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (updated != null && updated.isNotEmpty && mounted) {
      setState(() => item.repoPath = updated.replaceAll('\\', '/'));
    }
  }

  Future<void> _uploadQueuedFilesAndBuild() async {
    if (_queuedFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أضف ملفاً واحداً على الأقل أولاً')),
      );
      return;
    }
    if (!await _ensureGitHubReady()) return;

    setState(() {
      _working = true;
      _lastError = null;
      _progressVal = 0.0;
      _statusText = 'جاري تجهيز ورفع الملفات ملف ملف...';
      _uploadProgress = null;
    });
    _cancel = GitHubCancelToken();

    try {
      final repo = await _resolveOrCreateRepo('joohub-files');
      final appName = _appNameCtrl.text.trim().isEmpty
          ? repo.name
          : _appNameCtrl.text.trim();
      final pkg = _pkgCtrl.text.trim().isEmpty
          ? WorkspaceManager.suggestPackageName(appName)
          : _pkgCtrl.text.trim();

      if (appState.backgroundBuildEnabled) {
        await BackgroundBuildService.startUploadNotification(
          title: 'جاري رفع الملفات • $appName',
          subtitle: 'رفع ${_queuedFiles.length} ملف (ملف ملف)...',
          progress: 0,
          indeterminate: false,
        );
      }

      // Optionally generate workflow file in temp dir and append to upload queue
      final uploadList = _queuedFiles
          .map((e) => (file: e.file, repoPath: e.repoPath))
          .toList();

      if (_injectWorkflow &&
          !uploadList
              .any((e) => e.repoPath == '.github/workflows/joohub_build_apk.yml')) {
        final root = await WorkspaceManager.workspaceRoot();
        final tmpDir = Directory(p.join(root.path, '.joohub_system', 'tmp_wf'));
        await tmpDir.create(recursive: true);
        await WorkspaceManager.injectApkBuilderWorkflow(
          tmpDir,
          appName: appName,
          packageName: pkg,
          buildMode: _buildMode,
        );
        final wfFile =
            File(p.join(tmpDir.path, '.github', 'workflows', 'joohub_build_apk.yml'));
        if (await wfFile.exists()) {
          uploadList.add((
            file: wfFile,
            repoPath: '.github/workflows/joohub_build_apk.yml',
          ));
        }
      }

      final sha = await _api!.uploadFilesOneByOne(
        repo: repo,
        items: uploadList,
        targetBranch: repo.defaultBranch,
        commitPrefix: 'JOOhub Build: $appName',
        cancelToken: _cancel,
        onLog: _log,
        onProgress: (prog) {
          if (mounted) {
            setState(() {
              _uploadProgress = prog;
              _progressVal = prog.fraction;
              _statusText = prog.stage;
            });
          }
          if (appState.backgroundBuildEnabled) {
            BackgroundBuildService.updateProgress(
              title: 'جاري الرفع • $appName',
              subtitle:
                  'ملف ${prog.completedFiles}/${prog.totalFiles}: ${prog.currentFile}',
              progress: (prog.fraction * 100).round().clamp(0, 100),
              indeterminate: false,
            );
          }
        },
      );

      _log('🚀 اكتمل رفع ${uploadList.length} ملف بنجاح! ($sha)');
      await _triggerAndMonitorBuild(repo, appName);
    } catch (e) {
      await _handleBuildError(e, 'رفع ملفات لبناء APK');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  // ==========================================================================
  // METHOD 2: ZIP PICK / SCAN / URL
  // ==========================================================================
  Future<void> _pickZipFile() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      if (res == null || res.files.isEmpty || res.files.single.path == null) {
        return;
      }
      await _processZipFile(File(res.files.single.path!));
    } catch (e) {
      _log('❌ تعذّر فتح منتقي الملفات: $e');
    }
  }

  Future<void> _openDeviceZipScanner() async {
    final zips = await PureZipEngine.scanDeviceZipFiles();
    if (!mounted) return;
    if (zips.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لم نجد ملفات ZIP في التنزيلات — اختر الملف يدوياً'),
        ),
      );
      return;
    }
    final chosen = await showModalBottomSheet<File>(
      context: context,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(12),
          children: [
            const Text(
              'ملفات ZIP الموجودة على جهازك',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            ...zips.map((f) {
              var sz = 0;
              try {
                sz = f.lengthSync();
              } catch (_) {}
              return ListTile(
                dense: true,
                leading: Icon(Icons.folder_zip_rounded,
                    color: appState.primaryColor),
                title: Text(p.basename(f.path),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  '${GitHubApiClient.fmtBytes(sz)} • ${p.basename(f.parent.path)}',
                  style: const TextStyle(fontSize: 11, color: Colors.white54),
                ),
                onTap: () => Navigator.pop(context, f),
              );
            }),
          ],
        ),
      ),
    );
    if (chosen != null) await _processZipFile(chosen);
  }

  Future<void> _downloadAndExtractUrl() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty || !url.startsWith('http')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('أدخل رابط ملف ZIP مباشر صحيح يبدأ بـ https://')),
      );
      return;
    }
    setState(() {
      _working = true;
      _lastError = null;
      _statusText = 'جاري تحميل ملف ZIP من الرابط...';
      _progressVal = 0.0;
    });
    try {
      final root = await WorkspaceManager.workspaceRoot();
      final tmpZip = File(
        p.join(root.path, '.joohub_system',
            'dl_${DateTime.now().millisecondsSinceEpoch}.zip'),
      );
      _log('⬇️ تحميل الأرشيف من: $url');
      await PureZipEngine.downloadZipFromUrl(
        url,
        tmpZip,
        onProgress: (rec, tot) {
          if (mounted) {
            setState(() {
              _progressVal = tot > 0 ? (rec / tot).clamp(0.0, 1.0) : 0.3;
              _statusText =
                  'تحميل ZIP: ${GitHubApiClient.fmtBytes(rec)}${tot > 0 ? " / ${GitHubApiClient.fmtBytes(tot)}" : ""}';
            });
          }
        },
      );
      await _processZipFile(tmpZip);
    } catch (e) {
      await _handleBuildError(e, 'تحميل ZIP من رابط');
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _processZipFile(File zipFile) async {
    setState(() {
      _selectedZip = zipFile;
      _extractResult = null;
      _preparedProject = null;
      _uploadProgress = null;
      _lastError = null;
      _working = true;
      _statusText = 'جاري فك ضغط ${p.basename(zipFile.path)}...';
      _progressVal = 0.0;
    });
    try {
      final baseName = p.basenameWithoutExtension(zipFile.path);
      final folderName = WorkspaceManager.sanitizeFolderName(baseName);
      final root = await WorkspaceManager.workspaceRoot();
      var destDir = Directory(p.join(root.path, folderName));
      if (await destDir.exists()) {
        destDir = Directory(
          p.join(root.path,
              '${folderName}_${DateTime.now().millisecondsSinceEpoch % 1000}'),
        );
      }

      _log('📂 فك ضغط ${p.basename(zipFile.path)}...');
      final result = await PureZipEngine.extractZipFile(
        zipFile,
        destDir,
        flattenSingleRoot: _flattenRoot,
        onProgress: (done, total, cur) {
          if (mounted) {
            setState(() {
              _progressVal = total > 0 ? (done / total).clamp(0.0, 1.0) : 0.0;
              _statusText = 'فك الضغط ($done / $total): ${p.basename(cur)}';
            });
          }
        },
      );

      final detectedName = result.detectedAppName ?? baseName;
      final detectedPkg = result.detectedPackageName ??
          WorkspaceManager.suggestPackageName(detectedName);

      final proj = await WorkspaceManager.applyProjectIdentity(
        projectDir: result.targetDir,
        appName: detectedName,
        packageName: detectedPkg,
      );
      appState.setActiveProject(proj);
      widget.onProjectExtracted?.call();
      await _loadLocalProjects();

      if (!mounted) return;
      setState(() {
        _extractResult = result;
        _preparedProject = proj;
        _appNameCtrl.text = detectedName;
        _pkgCtrl.text = detectedPkg;
        _newRepoCtrl.text = WorkspaceManager.sanitizeFolderName(detectedName)
            .toLowerCase()
            .replaceAll('_', '-');
        _statusText = 'تم فك الضغط وتجهيز المشروع بنجاح';
        _progressVal = 1.0;
      });
      _log('✅ فك الضغط: ${result.fileCount} ملف (${GitHubApiClient.fmtBytes(result.totalBytes)})');
    } catch (e) {
      _log('❌ خطأ في فك الضغط: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  // ==========================================================================
  // METHOD 4: QUICK CODE -> SCAFFOLD -> BUILD APK
  // ==========================================================================
  Future<void> _prepareQuickCodeProject() async {
    final code = _quickCodeCtrl.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الصق كود lib/main.dart أولاً')),
      );
      return;
    }
    final appName = _appNameCtrl.text.trim().isEmpty
        ? 'JOOhubQuickApp'
        : _appNameCtrl.text.trim();
    final pkg = _pkgCtrl.text.trim().isEmpty
        ? WorkspaceManager.suggestPackageName(appName)
        : _pkgCtrl.text.trim();

    final proj = await WorkspaceManager.createProject(
      appName,
      packageName: pkg,
      iconSourcePath: _iconPath,
    );
    final mainFile = File(p.join(proj.path, 'lib', 'main.dart'));
    await mainFile.parent.create(recursive: true);
    await mainFile.writeAsString(code);
    appState.setActiveProject(proj);
    widget.onProjectExtracted?.call();
    await _loadLocalProjects();

    if (mounted) {
      setState(() => _preparedProject = proj);
    }
    await _uploadProjectAndBuildApk();
  }

  // ==========================================================================
  // SHARED UPLOAD + TRIGGER + BACKGROUND MONITOR
  // ==========================================================================
  Future<bool> _ensureGitHubReady() async {
    if (appState.activeAccount == null) {
      final ok = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const GitHubConnectScreen()),
      );
      if (ok != true) return false;
      await _loadRepos();
    }
    if (_api == null) await _loadRepos();
    return _api != null;
  }

  Future<GitHubRepo> _resolveOrCreateRepo(String fallbackPrefix) async {
    if (_targetRepo != null) return _targetRepo!;
    final rName = _newRepoCtrl.text.trim().isEmpty
        ? '$fallbackPrefix-${DateTime.now().millisecondsSinceEpoch % 10000}'
        : _newRepoCtrl.text.trim();
    _log('🆕 إنشاء مستودع جديد: $rName...');
    final repo = await _api!.createRepo(rName, isPrivate: true);
    if (mounted) {
      setState(() {
        _repos = [repo, ..._repos];
        _targetRepo = repo;
      });
    }
    return repo;
  }

  Future<void> _uploadProjectAndBuildApk() async {
    if (_preparedProject == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر مشروعاً أو فك ضغط ZIP أولاً')),
      );
      return;
    }
    if (!await _ensureGitHubReady()) return;

    setState(() {
      _working = true;
      _lastError = null;
      _progressVal = 0.0;
      _statusText = 'تجهيز الهوية وملف بناء APK...';
      _uploadProgress = null;
    });
    _cancel = GitHubCancelToken();

    try {
      final dir = Directory(_preparedProject!.path);
      final appName = _appNameCtrl.text.trim().isEmpty
          ? _preparedProject!.name
          : _appNameCtrl.text.trim();
      final pkg = _pkgCtrl.text.trim().isEmpty
          ? WorkspaceManager.suggestPackageName(appName)
          : _pkgCtrl.text.trim();

      _preparedProject = await WorkspaceManager.applyProjectIdentity(
        projectDir: dir,
        appName: appName,
        packageName: pkg,
        iconSourcePath: _iconPath,
      );
      appState.setActiveProject(_preparedProject);
      _log('🎨 تطبيق الهوية: $appName ($pkg)');

      if (_injectWorkflow) {
        await WorkspaceManager.injectApkBuilderWorkflow(
          dir,
          appName: appName,
          packageName: pkg,
          buildMode: _buildMode,
        );
        _log('⚙️ حقن ملف البناء السحابي (.github/workflows/joohub_build_apk.yml)');
      }

      final repo = await _resolveOrCreateRepo('joohub-apk');

      if (appState.backgroundBuildEnabled) {
        await BackgroundBuildService.startUploadNotification(
          title: 'جاري الرفع • $appName',
          subtitle: _uploadStrategy == 'file_by_file'
              ? 'الرفع الآمن ملف ملف...'
              : 'الرفع الذكي على 5 مراحل...',
          progress: 0,
          indeterminate: false,
        );
      }

      void onProg(UploadProgress prog) {
        if (mounted) {
          setState(() {
            _uploadProgress = prog;
            _progressVal = prog.fraction;
            _statusText = prog.stage;
          });
        }
        if (appState.backgroundBuildEnabled) {
          BackgroundBuildService.updateProgress(
            title: 'جاري الرفع • $appName',
            subtitle:
                '${prog.completedFiles}/${prog.totalFiles} • ${prog.currentFile}',
            progress: (prog.fraction * 100).round().clamp(0, 100),
            indeterminate: false,
          );
        }
      }

      final String sha;
      if (_uploadStrategy == 'file_by_file') {
        sha = await _api!.syncDirectoryFileByFile(
          projectDir: dir,
          repo: repo,
          targetBranch: repo.defaultBranch,
          commitMessage: 'Build APK: $appName ($pkg) via JOOhub',
          cancelToken: _cancel,
          onLog: _log,
          onProgress: onProg,
        );
      } else {
        sha = await _api!.syncDirectoryToRepo(
          projectDir: dir,
          repo: repo,
          commitMessage: 'Build APK: $appName ($pkg) via JOOhub',
          batchSize: appState.uploadBatchSize,
          useCheckpoint: appState.enableCheckpoints,
          cancelToken: _cancel,
          onLog: _log,
          onProgress: onProg,
        );
      }

      final shortSha = sha.length >= 7 ? sha.substring(0, 7) : sha;
      _log('🚀 اكتمل الرفع بنجاح! Commit: $shortSha');
      await _triggerAndMonitorBuild(repo, appName);
    } catch (e) {
      await _handleBuildError(e, 'رفع وبناء APK');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _triggerAndMonitorBuild(GitHubRepo repo, String appName) async {
    if (_injectWorkflow) {
      await _api!.triggerWorkflow(
        owner: repo.owner,
        repo: repo.name,
        workflowFileName: 'joohub_build_apk.yml',
        ref: repo.defaultBranch,
      );
    }
    _log('⏳ جاري البناء السحابي على GitHub Actions...');

    if (appState.backgroundBuildEnabled && appState.activeAccount != null) {
      await BackgroundBuildService.startCloudBuildMonitor(
        owner: repo.owner,
        repo: repo.name,
        token: appState.activeAccount!.session.accessToken,
        appName: appName,
        pollSeconds: appState.backgroundPollSeconds,
      );
      _log('🔔 تم تشغيل المتابعة في الخلفية — يمكنك إغلاق التطبيق وسيستمر إشعار «جاري البناء» المتحرك!');
    }

    await appState.recordActivity(
      'بناء APK السحابي',
      'رفع وبناء $appName على ${repo.fullName}',
    );
    await _refreshBuildStatus();
    _startLivePolling();
  }

  Future<void> _handleBuildError(Object e, String title) async {
    final diag = GitHubException.diagnose(e, endpoint: title);
    _log('❌ ${diag.title}: ${diag.reason}');
    await BackgroundBuildService.stop();
    await appState.recordActivity(
      title,
      '${diag.title} — ${diag.reason}',
      isError: true,
    );
    if (mounted) setState(() => _lastError = diag);
  }

  void _startLivePolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      Duration(seconds: appState.backgroundPollSeconds),
      (_) async {
        await _refreshBuildStatus();
        final anyRunning = _latestRuns.any(
          (r) => r['status'] == 'in_progress' || r['status'] == 'queued',
        );
        if (!anyRunning) _pollTimer?.cancel();
      },
    );
  }

  Future<void> _refreshBuildStatus() async {
    if (_api == null || _targetRepo == null) return;
    try {
      final runs = await _api!.listWorkflowRuns(
        _targetRepo!.owner,
        _targetRepo!.name,
        perPage: 5,
      );
      final assets = await _api!.listApkReleaseAssets(
        _targetRepo!.owner,
        _targetRepo!.name,
      );
      if (mounted) {
        setState(() {
          _latestRuns = runs;
          _apkAssets = assets;
        });
      }
    } catch (_) {}
  }

  Future<void> _pickIcon() async {
    final x = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (x != null && mounted) setState(() => _iconPath = x.path);
  }

  @override
  Widget build(BuildContext context) {
    final accent = appState.primaryColor;

    return SafeArea(
      child: Column(
        children: [
          // Top Header
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: const BoxDecoration(
              color: kSurface,
              border: Border(bottom: BorderSide(color: kStroke)),
            ),
            child: Row(
              children: [
                Icon(Icons.cloud_upload_rounded, color: accent, size: 18),
                const SizedBox(width: 7),
                const Expanded(
                  child: Text(
                    'استوديو رفع الملفات وبناء APK',
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900),
                  ),
                ),
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
                // 4 Source Methods Switcher
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.upload_file_rounded, size: 15),
                      label: const Text('ملف ملف',
                          style: TextStyle(fontSize: 11.5)),
                      selected: _sourceMode == 0,
                      selectedColor: accent.withValues(alpha: 0.25),
                      onSelected: (_) => setState(() => _sourceMode = 0),
                    ),
                    ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.folder_zip_rounded, size: 15),
                      label:
                          const Text('ملف ZIP', style: TextStyle(fontSize: 11.5)),
                      selected: _sourceMode == 1,
                      selectedColor: accent.withValues(alpha: 0.25),
                      onSelected: (_) => setState(() => _sourceMode = 1),
                    ),
                    ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.folder_copy_rounded, size: 15),
                      label: const Text('مشروع محلي',
                          style: TextStyle(fontSize: 11.5)),
                      selected: _sourceMode == 2,
                      selectedColor: accent.withValues(alpha: 0.25),
                      onSelected: (_) {
                        _loadLocalProjects();
                        setState(() => _sourceMode = 2);
                      },
                    ),
                    ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.code_rounded, size: 15),
                      label: const Text('لصق كود فوري',
                          style: TextStyle(fontSize: 11.5)),
                      selected: _sourceMode == 3,
                      selectedColor: accent.withValues(alpha: 0.25),
                      onSelected: (_) => setState(() => _sourceMode = 3),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // ============================================================
                // SOURCE MODE 0: FILE-BY-FILE QUEUE
                // ============================================================
                if (_sourceMode == 0)
                  ApexCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.upload_file_rounded,
                                color: accent, size: 17),
                            const SizedBox(width: 6),
                            const Expanded(
                              child: Text(
                                'رفع الملفات ملف ملف (أو عدة ملفات معاً)',
                                style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w900),
                              ),
                            ),
                            ApexPill(
                              text: '${_queuedFiles.length} ملف',
                              color: accent,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                icon: const Icon(Icons.add_circle_outline,
                                    size: 16),
                                label: const Text('إضافة ملف واحد'),
                                onPressed: _working
                                    ? null
                                    : () => _pickSingleOrMultiFiles(
                                        allowMultiple: false),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.library_add_outlined,
                                    size: 16),
                                label: const Text('إضافة عدة ملفات'),
                                onPressed: _working
                                    ? null
                                    : () => _pickSingleOrMultiFiles(
                                        allowMultiple: true),
                              ),
                            ),
                          ],
                        ),
                        if (_queuedFiles.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          ..._queuedFiles.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final item = entry.value;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 5),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 6),
                              decoration: BoxDecoration(
                                color: kSurfaceAlt,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: kStroke),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.insert_drive_file_outlined,
                                      size: 15, color: accent),
                                  const SizedBox(width: 7),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.repoPath,
                                          style: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        Text(
                                          GitHubApiClient.fmtBytes(
                                              item.sizeBytes),
                                          style: const TextStyle(
                                              fontSize: 10,
                                              color: Colors.white54),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'تعديل المسار',
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(Icons.edit_outlined,
                                        size: 16),
                                    onPressed: () => _editQueuedItemPath(item),
                                  ),
                                  IconButton(
                                    tooltip: 'إزالة',
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(Icons.delete_outline,
                                        size: 16, color: kCoral),
                                    onPressed: () => setState(
                                        () => _queuedFiles.removeAt(idx)),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
                  ),

                // ============================================================
                // SOURCE MODE 1: ZIP ARCHIVE
                // ============================================================
                if (_sourceMode == 1)
                  ApexCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                icon: const Icon(Icons.folder_zip_rounded,
                                    size: 16),
                                label: const Text('اختيار ملف ZIP'),
                                onPressed: _working ? null : _pickZipFile,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.search_rounded, size: 16),
                                label: const Text('مسح التنزيلات'),
                                onPressed:
                                    _working ? null : _openDeviceZipScanner,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _urlCtrl,
                                style: const TextStyle(fontSize: 11.5),
                                decoration: const InputDecoration(
                                  hintText: 'أو الصق رابط ZIP مباشر https://...',
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            OutlinedButton(
                              onPressed:
                                  _working ? null : _downloadAndExtractUrl,
                              child: const Text('تحميل'),
                            ),
                          ],
                        ),
                        SwitchListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          activeColor: accent,
                          title: const Text('تسطيح المجلد الجذري تلقائياً',
                              style: TextStyle(fontSize: 11.5)),
                          value: _flattenRoot,
                          onChanged: (v) => setState(() => _flattenRoot = v),
                        ),
                        if (_extractResult != null && _selectedZip != null)
                          Text(
                            '✅ ${p.basename(_selectedZip!.path)} • ${_extractResult!.fileCount} ملف',
                            style: const TextStyle(
                                fontSize: 11.5,
                                color: kSuccess,
                                fontWeight: FontWeight.w800),
                          ),
                      ],
                    ),
                  ),

                // ============================================================
                // SOURCE MODE 2: LOCAL PROJECT
                // ============================================================
                if (_sourceMode == 2)
                  ApexCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'اختر مشروعاً من مساحة العمل:',
                          style: TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 8),
                        if (_localProjects.isEmpty)
                          const Text(
                            'لا توجد مشاريع محلية بعد — أنشئ مشروعاً أو ابنه بالذكاء AI.',
                            style:
                                TextStyle(fontSize: 11.5, color: Colors.white54),
                          )
                        else
                          ..._localProjects.map((proj) {
                            final sel = _preparedProject?.path == proj.path;
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                Icons.folder_rounded,
                                color: sel ? accent : Colors.white54,
                              ),
                              title: Text(proj.name,
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800)),
                              subtitle: Text(proj.packageName,
                                  style: const TextStyle(
                                      fontSize: 10.5,
                                      fontFamily: 'monospace')),
                              trailing: sel
                                  ? ApexPill(text: 'محدد', color: accent)
                                  : null,
                              onTap: () {
                                setState(() {
                                  _preparedProject = proj;
                                  _appNameCtrl.text = proj.name;
                                  _pkgCtrl.text = proj.packageName;
                                  _newRepoCtrl.text =
                                      WorkspaceManager.sanitizeFolderName(
                                              proj.name)
                                          .toLowerCase()
                                          .replaceAll('_', '-');
                                });
                              },
                            );
                          }),
                      ],
                    ),
                  ),

                // ============================================================
                // SOURCE MODE 3: QUICK PASTE CODE -> APK
                // ============================================================
                if (_sourceMode == 3)
                  ApexCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'الصق كود lib/main.dart لتجهيز مشروع Flutter كامل وبناء APK فوراً:',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: TextField(
                            controller: _quickCodeCtrl,
                            maxLines: 7,
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 11.5),
                            decoration: const InputDecoration(
                              hintText: "import 'package:flutter/material.dart';\nvoid main() => runApp(...);",
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 10),

                // ============================================================
                // IDENTITY, TARGET REPO & UPLOAD STRATEGY
                // ============================================================
                ApexCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'إعدادات البناء والرفع السحابي',
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _appNameCtrl,
                              decoration: const InputDecoration(
                                labelText: 'اسم التطبيق (App Name)',
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          OutlinedButton.icon(
                            icon: Icon(
                              _iconPath != null
                                  ? Icons.check_circle
                                  : Icons.image_outlined,
                              size: 16,
                              color: _iconPath != null ? kSuccess : accent,
                            ),
                            label: const Text('الأيقونة'),
                            onPressed: _pickIcon,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _pkgCtrl,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12),
                        decoration: const InputDecoration(
                          labelText: 'معرّف الحزمة (Package ID)',
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_repos.isNotEmpty)
                        DropdownButtonFormField<GitHubRepo?>(
                          value: _targetRepo,
                          dropdownColor: kSurface,
                          decoration: const InputDecoration(
                            labelText: 'المستودع الهدف على GitHub',
                          ),
                          items: [
                            const DropdownMenuItem<GitHubRepo?>(
                              value: null,
                              child: Text('➕ إنشاء مستودع جديد تلقائياً'),
                            ),
                            ..._repos.map(
                              (r) => DropdownMenuItem<GitHubRepo?>(
                                value: r,
                                child: Text(
                                  '${r.isPrivate ? "🔒" : "🌐"} ${r.fullName}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                          onChanged: (v) => setState(() => _targetRepo = v),
                        ),
                      if (_targetRepo == null) ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: _newRepoCtrl,
                          decoration: const InputDecoration(
                            labelText: 'اسم المستودع الجديد (عند الإنشاء)',
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      if (_sourceMode != 0) ...[
                        const Text(
                          'طريقة الرفع إلى GitHub:',
                          style: TextStyle(
                              fontSize: 11.5, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 5),
                        Wrap(
                          spacing: 6,
                          children: [
                            ChoiceChip(
                              visualDensity: VisualDensity.compact,
                              label: const Text('ملف ملف (آمن 100%)',
                                  style: TextStyle(fontSize: 11)),
                              selected: _uploadStrategy == 'file_by_file',
                              selectedColor: accent.withValues(alpha: 0.25),
                              onSelected: (_) => setState(
                                  () => _uploadStrategy = 'file_by_file'),
                            ),
                            ChoiceChip(
                              visualDensity: VisualDensity.compact,
                              label: const Text('دفعات ذكية (5 مراحل)',
                                  style: TextStyle(fontSize: 11)),
                              selected: _uploadStrategy == 'staged_batch',
                              selectedColor: accent.withValues(alpha: 0.25),
                              onSelected: (_) => setState(
                                  () => _uploadStrategy = 'staged_batch'),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        children: [
                          ChoiceChip(
                            visualDensity: VisualDensity.compact,
                            label: const Text('Release APK',
                                style: TextStyle(fontSize: 11)),
                            selected: _buildMode == 'release_apk',
                            selectedColor: accent.withValues(alpha: 0.25),
                            onSelected: (_) =>
                                setState(() => _buildMode = 'release_apk'),
                          ),
                          ChoiceChip(
                            visualDensity: VisualDensity.compact,
                            label: const Text('Split APKs',
                                style: TextStyle(fontSize: 11)),
                            selected: _buildMode == 'split_apk',
                            selectedColor: accent.withValues(alpha: 0.25),
                            onSelected: (_) =>
                                setState(() => _buildMode = 'split_apk'),
                          ),
                          ChoiceChip(
                            visualDensity: VisualDensity.compact,
                            label: const Text('AAB (Play)',
                                style: TextStyle(fontSize: 11)),
                            selected: _buildMode == 'aab',
                            selectedColor: accent.withValues(alpha: 0.25),
                            onSelected: (_) =>
                                setState(() => _buildMode = 'aab'),
                          ),
                        ],
                      ),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        activeColor: accent,
                        title: const Text('حقن ملف بناء APK التلقائي (Workflow)',
                            style: TextStyle(fontSize: 11.5)),
                        value: _injectWorkflow,
                        onChanged: (v) => setState(() => _injectWorkflow = v),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        icon: _working
                            ? const SizedBox(
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.black),
                              )
                            : const Icon(Icons.rocket_launch_rounded, size: 17),
                        label: Text(
                          _sourceMode == 0
                              ? 'رفع الملفات ملف ملف وبناء APK في الخلفية'
                              : _sourceMode == 3
                                  ? 'تجهيز الكود ورفع وبناء APK في الخلفية'
                                  : 'رفع وبناء APK الآن (مع إشعار الخلفية)',
                        ),
                        onPressed: _working
                            ? null
                            : () {
                                if (_sourceMode == 0) {
                                  _uploadQueuedFilesAndBuild();
                                } else if (_sourceMode == 3) {
                                  _prepareQuickCodeProject();
                                } else {
                                  _uploadProjectAndBuildApk();
                                }
                              },
                      ),
                    ],
                  ),
                ),

                // Live Upload Progress Card
                if (_working || _uploadProgress != null) ...[
                  const SizedBox(height: 10),
                  if (_uploadProgress != null)
                    StagedUploadCard(
                      progress: _uploadProgress!,
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
                    )
                  else
                    ApexCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(_statusText,
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 6),
                          LinearProgressIndicator(
                            value: _progressVal > 0 ? _progressVal : null,
                            color: accent,
                            backgroundColor: kStroke,
                          ),
                        ],
                      ),
                    ),
                ],

                if (_lastError != null) ...[
                  const SizedBox(height: 10),
                  ErrorDiagnosticCard(
                    error: _lastError!,
                    onRetry: () {
                      if (_sourceMode == 0) {
                        _uploadQueuedFilesAndBuild();
                      } else {
                        _uploadProjectAndBuildApk();
                      }
                    },
                  ),
                ],

                // APK Releases Ready to Download
                if (_apkAssets.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ApexCard(
                    borderColor: kSuccess.withValues(alpha: 0.45),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'ملفات APK الجاهزة للتحميل',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w900,
                              color: kSuccess),
                        ),
                        const SizedBox(height: 6),
                        ..._apkAssets.take(6).map((a) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.android_rounded,
                                  color: kSuccess),
                              title: Text(a.name,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800)),
                              subtitle: Text(
                                '${GitHubApiClient.fmtBytes(a.size)} • ${a.tagName}',
                                style: const TextStyle(fontSize: 10.5),
                              ),
                              trailing: FilledButton(
                                onPressed: () => launchUrl(
                                  Uri.parse(a.downloadUrl),
                                  mode: LaunchMode.externalApplication,
                                ),
                                child: const Text('تحميل'),
                              ),
                            )),
                      ],
                    ),
                  ),
                ],

                // Recent Workflow Runs
                if (_latestRuns.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ApexCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'حالة البناء السحابي (GitHub Actions)',
                                style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w900),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                              onPressed: _refreshBuildStatus,
                            ),
                          ],
                        ),
                        ..._latestRuns.take(4).map((r) {
                          final st =
                              (r['conclusion'] ?? r['status'] ?? '').toString();
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
                            title: Text(
                              (r['name'] ?? 'Build APK').toString(),
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                            trailing: ApexPill(text: st, color: col),
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

                // Live Console Log
                if (_logs.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ApexCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'سجل العمليات المباشر',
                                style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w900),
                              ),
                            ),
                            TextButton(
                              onPressed: () => setState(() => _logs.clear()),
                              child: const Text('مسح'),
                            ),
                          ],
                        ),
                        ..._logs.reversed.take(20).map((l) => Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Text(
                                l,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  color: Colors.white70,
                                ),
                              ),
                            )),
                      ],
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
