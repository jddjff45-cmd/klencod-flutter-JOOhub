import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';
import '../services/github_engine.dart';
import '../services/workspace_manager.dart';

enum BrowserOpenMode { askEveryTime, inApp, external }

class GitHubAccount {
  final String login;
  final String? name;
  GitHubAuthSession session;

  GitHubAccount({required this.login, this.name, required this.session});

  Map<String, dynamic> toJson() => {
        'login': login,
        'name': name,
        'session': session.toJson(),
      };

  factory GitHubAccount.fromJson(Map<String, dynamic> j) => GitHubAccount(
        login: (j['login'] ?? '').toString(),
        name: j['name'] as String?,
        session: GitHubAuthSession.fromJson(
          (j['session'] as Map<String, dynamic>?) ?? const {},
        ),
      );
}

class LocalProject {
  final String name;
  final String path;
  final String packageName;
  final String version;
  final String? iconPath;
  final DateTime modifiedAt;

  const LocalProject({
    required this.name,
    required this.path,
    this.packageName = 'com.yossefjoo.app',
    this.version = '1.0.0',
    this.iconPath,
    required this.modifiedAt,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'packageName': packageName,
        'version': version,
        'iconPath': iconPath,
        'modifiedAt': modifiedAt.toIso8601String(),
      };

  factory LocalProject.fromJson(Map<String, dynamic> j) => LocalProject(
        name: (j['name'] ?? 'App').toString(),
        path: (j['path'] ?? '').toString(),
        packageName: (j['packageName'] ?? 'com.yossefjoo.app').toString(),
        version: (j['version'] ?? '1.0.0').toString(),
        iconPath: j['iconPath'] as String?,
        modifiedAt:
            DateTime.tryParse((j['modifiedAt'] ?? '').toString()) ?? DateTime.now(),
      );
}

class ProjectConfig {
  String appName;
  String packageName;
  String version;
  String buildNumber;
  String? iconPath;

  ProjectConfig({
    required this.appName,
    required this.packageName,
    this.version = '1.0.0',
    this.buildNumber = '1',
    this.iconPath,
  });

  Map<String, dynamic> toJson() => {
        'appName': appName,
        'packageName': packageName,
        'version': version,
        'buildNumber': buildNumber,
        'iconPath': iconPath,
      };

  factory ProjectConfig.fromJson(Map<String, dynamic> j) => ProjectConfig(
        appName: (j['appName'] ?? 'App').toString(),
        packageName: (j['packageName'] ?? 'com.yossefjoo.app').toString(),
        version: (j['version'] ?? '1.0.0').toString(),
        buildNumber: (j['buildNumber'] ?? '1').toString(),
        iconPath: j['iconPath'] as String?,
      );
}

class ProjectConfigService {
  final LocalProject project;
  ProjectConfigService(this.project);

  File get _file => File(p.join(project.path, '.joohub', 'project_config.json'));

  Future<ProjectConfig> load() async {
    try {
      if (await _file.exists()) {
        return ProjectConfig.fromJson(
          jsonDecode(await _file.readAsString()) as Map<String, dynamic>,
        );
      }
    } catch (_) {}
    return ProjectConfig(
      appName: project.name,
      packageName: project.packageName,
      version: project.version,
      iconPath: project.iconPath,
    );
  }

  Future<void> save(ProjectConfig c) async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(c.toJson()),
    );
  }
}

class ActivityRecord {
  final String title;
  final String detail;
  final bool isError;
  final DateTime time;

  const ActivityRecord({
    required this.title,
    required this.detail,
    required this.isError,
    required this.time,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'detail': detail,
        'isError': isError,
        'time': time.toIso8601String(),
      };

  factory ActivityRecord.fromJson(Map<String, dynamic> j) => ActivityRecord(
        title: (j['title'] ?? '').toString(),
        detail: (j['detail'] ?? '').toString(),
        isError: j['isError'] == true,
        time: DateTime.tryParse((j['time'] ?? '').toString()) ?? DateTime.now(),
      );
}

class AppState extends ChangeNotifier {
  static const String _prefsKey = 'joohub_permanent_state_v10';

  List<GitHubAccount> accounts = [];
  String? activeLogin;
  LocalProject? activeProject;
  bool loaded = false;

  // Appearance & Typography
  BrowserOpenMode browserMode = BrowserOpenMode.askEveryTime;
  String orangeAccentId = 'solar';
  String uiFontId = 'cairo';
  double uiFontScale = 0.94;
  String codeFontId = 'jetbrains';
  String codeThemeId = 'orange_obsidian';
  double editorFontSize = 12.5;
  bool editorWordWrap = true;
  bool showSymbolBar = true;
  bool showLineNumbers = true;
  bool editorAutoSave = false;
  bool editorLiveLint = true;
  int editorTabSize = 2;

  // Staged Upload, File-by-File & Network Settings
  String defaultUploadMode = 'file_by_file';
  int uploadBatchSize = 5;
  int maxRetries = 4;
  int timeoutSeconds = 40;
  bool enableCheckpoints = true;

  // Background Build & Notifications Settings
  bool backgroundBuildEnabled = true;
  int backgroundPollSeconds = 10;

  // AI Model & API Key Configuration
  String aiProviderId = 'gemini';
  String aiApiKey = '';
  String aiModel = 'gemini-2.5-flash';
  String aiCustomBaseUrl = '';
  double aiTemperature = 0.35;
  int aiMaxTokens = 8192;
  String aiSystemPromptExtra = '';

  List<ActivityRecord> history = [];

  bool get hasAiKey => aiApiKey.trim().isNotEmpty;

  GitHubAccount? get activeAccount {
    if (accounts.isEmpty) return null;
    for (final a in accounts) {
      if (a.login == activeLogin) return a;
    }
    return accounts.first;
  }

  OrangeAccentPreset get accent => kOrangeAccents.firstWhere(
        (a) => a.id == orangeAccentId,
        orElse: () => kOrangeAccents.first,
      );

  Color get primaryColor => accent.primary;

  UiFontPreset get uiFont => kUiFonts.firstWhere(
        (f) => f.id == uiFontId,
        orElse: () => kUiFonts.first,
      );

  CodeFontPreset get codeFont => kCodeFonts.firstWhere(
        (f) => f.id == codeFontId,
        orElse: () => kCodeFonts.first,
      );

  CodeThemePreset get codeTheme => kCodeThemes.firstWhere(
        (t) => t.id == codeThemeId,
        orElse: () => kCodeThemes.first,
      );

  GitHubApiClient createClientFor(GitHubAccount acc) {
    return GitHubApiClient(
      acc.session.accessToken,
      session: acc.session,
      maxRetries: maxRetries,
      timeoutSeconds: timeoutSeconds,
    );
  }

  Future<void> loadAll() async {
    Map<String, dynamic>? loadedJson;

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.trim().isNotEmpty) {
        loadedJson = jsonDecode(raw) as Map<String, dynamic>;
      }
    } catch (_) {}

    if (loadedJson == null) {
      try {
        final f = await _prefsFile();
        if (await f.exists()) {
          loadedJson =
              jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        } else {
          final root = await WorkspaceManager.workspaceRoot();
          for (final legacyName in const [
            'state_v9.json',
            'state_v8.json',
            'state_v7.json',
            'state_v6.json',
            'state_v5.json'
          ]) {
            final legacy =
                File(p.join(root.path, '.joohub_system', legacyName));
            if (await legacy.exists()) {
              loadedJson = jsonDecode(await legacy.readAsString())
                  as Map<String, dynamic>;
              break;
            }
          }
        }
      } catch (_) {}
    }

    if (loadedJson != null) {
      _applyJson(loadedJson);
      await _saveAll();
    }
    loaded = true;
    notifyListeners();
  }

  void _applyJson(Map<String, dynamic> j) {
    accounts = (j['accounts'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(GitHubAccount.fromJson)
            .toList() ??
        [];
    activeLogin = j['activeLogin'] as String?;

    if (j['activeProject'] is Map<String, dynamic>) {
      final cand =
          LocalProject.fromJson(j['activeProject'] as Map<String, dynamic>);
      if (cand.path.isNotEmpty && Directory(cand.path).existsSync()) {
        activeProject = cand;
      }
    }

    final bm = (j['browserMode'] as num?)?.toInt() ?? 0;
    browserMode = BrowserOpenMode.values[bm.clamp(0, 2)];
    orangeAccentId = (j['orangeAccentId'] ?? 'solar').toString();
    uiFontId = (j['uiFontId'] ?? 'cairo').toString();
    uiFontScale =
        ((j['uiFontScale'] as num?)?.toDouble() ?? 0.94).clamp(0.84, 1.16);
    codeFontId = (j['codeFontId'] ?? 'jetbrains').toString();
    codeThemeId = (j['codeThemeId'] ?? 'orange_obsidian').toString();
    editorFontSize =
        ((j['editorFontSize'] as num?)?.toDouble() ?? 12.5).clamp(10.0, 22.0);
    editorWordWrap = j['editorWordWrap'] != false;
    showSymbolBar = j['showSymbolBar'] != false;
    showLineNumbers = j['showLineNumbers'] != false;
    editorAutoSave = j['editorAutoSave'] == true;
    editorLiveLint = j['editorLiveLint'] != false;
    editorTabSize = ((j['editorTabSize'] as num?)?.toInt() ?? 2).clamp(2, 4);

    defaultUploadMode =
        (j['defaultUploadMode'] ?? 'file_by_file').toString();
    uploadBatchSize =
        ((j['uploadBatchSize'] as num?)?.toInt() ?? 5).clamp(2, 15);
    maxRetries = ((j['maxRetries'] as num?)?.toInt() ?? 4).clamp(1, 6);
    timeoutSeconds =
        ((j['timeoutSeconds'] as num?)?.toInt() ?? 40).clamp(15, 90);
    enableCheckpoints = j['enableCheckpoints'] != false;

    backgroundBuildEnabled = j['backgroundBuildEnabled'] != false;
    backgroundPollSeconds =
        ((j['backgroundPollSeconds'] as num?)?.toInt() ?? 10).clamp(5, 30);

    aiProviderId = (j['aiProviderId'] ?? 'gemini').toString();
    aiApiKey = (j['aiApiKey'] ?? '').toString();
    aiModel = (j['aiModel'] ?? 'gemini-2.5-flash').toString();
    aiCustomBaseUrl = (j['aiCustomBaseUrl'] ?? '').toString();
    aiTemperature =
        ((j['aiTemperature'] as num?)?.toDouble() ?? 0.35).clamp(0.0, 1.2);
    aiMaxTokens =
        ((j['aiMaxTokens'] as num?)?.toInt() ?? 8192).clamp(1024, 16384);
    aiSystemPromptExtra = (j['aiSystemPromptExtra'] ?? '').toString();

    history = (j['history'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(ActivityRecord.fromJson)
            .toList() ??
        [];
  }

  Map<String, dynamic> toExportMap({bool includeSecrets = false}) => {
        if (includeSecrets) 'accounts': accounts.map((a) => a.toJson()).toList(),
        if (includeSecrets) 'activeLogin': activeLogin,
        if (activeProject != null) 'activeProject': activeProject!.toJson(),
        'browserMode': browserMode.index,
        'orangeAccentId': orangeAccentId,
        'uiFontId': uiFontId,
        'uiFontScale': uiFontScale,
        'codeFontId': codeFontId,
        'codeThemeId': codeThemeId,
        'editorFontSize': editorFontSize,
        'editorWordWrap': editorWordWrap,
        'showSymbolBar': showSymbolBar,
        'showLineNumbers': showLineNumbers,
        'editorAutoSave': editorAutoSave,
        'editorLiveLint': editorLiveLint,
        'editorTabSize': editorTabSize,
        'defaultUploadMode': defaultUploadMode,
        'uploadBatchSize': uploadBatchSize,
        'maxRetries': maxRetries,
        'timeoutSeconds': timeoutSeconds,
        'enableCheckpoints': enableCheckpoints,
        'backgroundBuildEnabled': backgroundBuildEnabled,
        'backgroundPollSeconds': backgroundPollSeconds,
        'aiProviderId': aiProviderId,
        if (includeSecrets) 'aiApiKey': aiApiKey,
        'aiModel': aiModel,
        'aiCustomBaseUrl': aiCustomBaseUrl,
        'aiTemperature': aiTemperature,
        'aiMaxTokens': aiMaxTokens,
        'aiSystemPromptExtra': aiSystemPromptExtra,
        'history': history.take(50).map((e) => e.toJson()).toList(),
      };

  Future<bool> saveNow() async => _saveAll();

  Future<bool> _saveAll() async {
    final encoded = const JsonEncoder.withIndent('  ')
        .convert(toExportMap(includeSecrets: true));
    var ok = false;

    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = await prefs.setString(_prefsKey, encoded);
      if (saved) ok = true;
    } catch (_) {}

    try {
      final f = await _prefsFile();
      await f.writeAsString(encoded, flush: true);
      ok = true;
    } catch (_) {}

    return ok;
  }

  Future<File> _prefsFile() async {
    final root = await WorkspaceManager.workspaceRoot();
    final f = File(p.join(root.path, '.joohub_system', 'state_v10.json'));
    await f.parent.create(recursive: true);
    return f;
  }

  Future<void> updateAiConfig({
    String? providerId,
    String? apiKey,
    String? model,
    String? customBaseUrl,
    double? temperature,
    int? maxTokens,
    String? systemPromptExtra,
  }) async {
    if (providerId != null) aiProviderId = providerId;
    if (apiKey != null) aiApiKey = apiKey.trim();
    if (model != null) aiModel = model.trim();
    if (customBaseUrl != null) aiCustomBaseUrl = customBaseUrl.trim();
    if (temperature != null) aiTemperature = temperature.clamp(0.0, 1.2);
    if (maxTokens != null) aiMaxTokens = maxTokens.clamp(1024, 16384);
    if (systemPromptExtra != null) {
      aiSystemPromptExtra = systemPromptExtra.trim();
    }
    await _saveAll();
    notifyListeners();
  }

  Future<void> updateBgBuildPrefs({
    bool? enabled,
    int? pollSeconds,
  }) async {
    if (enabled != null) backgroundBuildEnabled = enabled;
    if (pollSeconds != null) backgroundPollSeconds = pollSeconds.clamp(5, 30);
    await _saveAll();
    notifyListeners();
  }

  Future<void> recordActivity(
    String title,
    String detail, {
    bool isError = false,
  }) async {
    history.insert(
      0,
      ActivityRecord(
        title: title,
        detail: detail,
        isError: isError,
        time: DateTime.now(),
      ),
    );
    if (history.length > 50) {
      history = history.sublist(0, 50);
    }
    await _saveAll();
    notifyListeners();
  }

  Future<void> clearHistory() async {
    history.clear();
    await _saveAll();
    notifyListeners();
  }

  Future<int> clearUploadCheckpoints() async {
    var removed = 0;
    try {
      final root = await WorkspaceManager.workspaceRoot();
      await for (final ent in root.list(recursive: true, followLinks: false)) {
        if (ent is File && p.basename(ent.path).startsWith('upload_checkpoint')) {
          await ent.delete();
          removed++;
        }
      }
    } catch (_) {}
    return removed;
  }

  Future<void> resetDefaults({bool keepAccountsAndKeys = true}) async {
    final savedAccounts = accounts;
    final savedLogin = activeLogin;
    final savedKey = aiApiKey;

    browserMode = BrowserOpenMode.askEveryTime;
    orangeAccentId = 'solar';
    uiFontId = 'cairo';
    uiFontScale = 0.94;
    codeFontId = 'jetbrains';
    codeThemeId = 'orange_obsidian';
    editorFontSize = 12.5;
    editorWordWrap = true;
    showSymbolBar = true;
    showLineNumbers = true;
    editorAutoSave = false;
    editorLiveLint = true;
    editorTabSize = 2;
    defaultUploadMode = 'file_by_file';
    uploadBatchSize = 5;
    maxRetries = 4;
    timeoutSeconds = 40;
    enableCheckpoints = true;
    backgroundBuildEnabled = true;
    backgroundPollSeconds = 10;
    aiTemperature = 0.35;
    aiMaxTokens = 8192;
    aiSystemPromptExtra = '';

    if (keepAccountsAndKeys) {
      accounts = savedAccounts;
      activeLogin = savedLogin;
      aiApiKey = savedKey;
    } else {
      accounts = [];
      activeLogin = null;
      aiApiKey = '';
    }
    await _saveAll();
    notifyListeners();
  }

  Future<void> upsertAccount(GitHubAccount acc) async {
    accounts.removeWhere((a) => a.login == acc.login);
    accounts.insert(0, acc);
    activeLogin = acc.login;
    await _saveAll();
    notifyListeners();
  }

  Future<void> switchAccount(String login) async {
    activeLogin = login;
    await _saveAll();
    notifyListeners();
  }

  Future<void> removeActiveAccount() async {
    final cur = activeAccount;
    if (cur == null) return;
    accounts.removeWhere((a) => a.login == cur.login);
    activeLogin = accounts.isNotEmpty ? accounts.first.login : null;
    await _saveAll();
    notifyListeners();
  }

  Future<void> setBrowserMode(BrowserOpenMode mode) async {
    browserMode = mode;
    await _saveAll();
    notifyListeners();
  }

  Future<void> setOrangeAccent(String id) async {
    orangeAccentId = id;
    await _saveAll();
    notifyListeners();
  }

  Future<void> setUiFont(String id) async {
    uiFontId = id;
    await _saveAll();
    notifyListeners();
  }

  Future<void> setUiFontScale(double scale) async {
    uiFontScale = scale.clamp(0.84, 1.16);
    await _saveAll();
    notifyListeners();
  }

  Future<void> setCodeFont(String id) async {
    codeFontId = id;
    await _saveAll();
    notifyListeners();
  }

  Future<void> setCodeTheme(String id) async {
    codeThemeId = id;
    await _saveAll();
    notifyListeners();
  }

  Future<void> updateNetworkPrefs({
    String? uploadMode,
    int? batchSize,
    int? retries,
    int? timeout,
    bool? checkpoints,
  }) async {
    if (uploadMode != null) defaultUploadMode = uploadMode;
    if (batchSize != null) uploadBatchSize = batchSize.clamp(2, 15);
    if (retries != null) maxRetries = retries.clamp(1, 6);
    if (timeout != null) timeoutSeconds = timeout.clamp(15, 90);
    if (checkpoints != null) enableCheckpoints = checkpoints;
    await _saveAll();
    notifyListeners();
  }

  Future<void> updateEditorPrefs({
    double? fontSize,
    bool? wordWrap,
    bool? symbolBar,
    bool? lineNumbers,
    bool? autoSave,
    bool? liveLint,
    int? tabSize,
  }) async {
    if (fontSize != null) editorFontSize = fontSize.clamp(10.0, 22.0);
    if (wordWrap != null) editorWordWrap = wordWrap;
    if (symbolBar != null) showSymbolBar = symbolBar;
    if (lineNumbers != null) showLineNumbers = lineNumbers;
    if (autoSave != null) editorAutoSave = autoSave;
    if (liveLint != null) editorLiveLint = liveLint;
    if (tabSize != null) editorTabSize = tabSize.clamp(2, 4);
    await _saveAll();
    notifyListeners();
  }

  void setActiveProject(LocalProject? proj) {
    activeProject = proj;
    _saveAll();
    notifyListeners();
  }
}

final AppState appState = AppState();
