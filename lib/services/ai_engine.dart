import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/app_state.dart';
import 'workspace_manager.dart';

// ============================================================================
// JOOhub — FULL-POWER PURE-DART AI ENGINE v9.0
// Supports Gemini, OpenAI, OpenRouter, Groq, DeepSeek & Custom OpenAI APIs
// Live Model Discovery + Full Multi-File App Builder + Project Architect
// + Inline Code Editor Bug Fixer & Refactorer + Auto-Retry Resilience
// ============================================================================

class AiProviderPreset {
  final String id;
  final String name;
  final String defaultModel;
  final List<String> models;
  final String keyHint;

  const AiProviderPreset({
    required this.id,
    required this.name,
    required this.defaultModel,
    required this.models,
    required this.keyHint,
  });
}

const List<AiProviderPreset> kAiProviders = [
  AiProviderPreset(
    id: 'gemini',
    name: 'Google Gemini',
    defaultModel: 'gemini-2.5-flash',
    models: [
      'gemini-2.5-flash',
      'gemini-2.5-pro',
      'gemini-2.0-flash',
    ],
    keyHint: 'AIzaSy...',
  ),
  AiProviderPreset(
    id: 'openai',
    name: 'OpenAI',
    defaultModel: 'gpt-4o-mini',
    models: [
      'gpt-4o',
      'gpt-4o-mini',
      'o3-mini',
    ],
    keyHint: 'sk-...',
  ),
  AiProviderPreset(
    id: 'openrouter',
    name: 'OpenRouter',
    defaultModel: 'google/gemini-2.5-flash',
    models: [
      'google/gemini-2.5-flash',
      'anthropic/claude-sonnet-4',
      'deepseek/deepseek-chat-v3-0324',
      'openai/gpt-4o-mini',
    ],
    keyHint: 'sk-or-v1-...',
  ),
  AiProviderPreset(
    id: 'deepseek',
    name: 'DeepSeek',
    defaultModel: 'deepseek-chat',
    models: [
      'deepseek-chat',
      'deepseek-reasoner',
    ],
    keyHint: 'sk-...',
  ),
  AiProviderPreset(
    id: 'groq',
    name: 'Groq',
    defaultModel: 'llama-3.3-70b-versatile',
    models: [
      'llama-3.3-70b-versatile',
      'deepseek-r1-distill-llama-70b',
      'qwen-qwq-32b',
    ],
    keyHint: 'gsk_...',
  ),
  AiProviderPreset(
    id: 'custom',
    name: 'مخصص (OpenAI API)',
    defaultModel: 'gpt-4o-mini',
    models: ['gpt-4o-mini', 'deepseek-chat'],
    keyHint: 'sk-...',
  ),
];

AiProviderPreset aiProviderById(String id) {
  return kAiProviders.firstWhere(
    (e) => e.id == id,
    orElse: () => kAiProviders.first,
  );
}

class AiBuildSpec {
  final String prompt;
  final String appName;
  final String packageName;
  final String? iconPath;
  final String category;
  final String visualStyle;
  final String accentName;
  final String accentHex;
  final String language;
  final String navigation;
  final List<String> features;

  const AiBuildSpec({
    required this.prompt,
    required this.appName,
    required this.packageName,
    this.iconPath,
    required this.category,
    required this.visualStyle,
    required this.accentName,
    required this.accentHex,
    required this.language,
    required this.navigation,
    required this.features,
  });
}

class AiFileAction {
  final String type; // write | delete
  final String path;
  final String content;

  const AiFileAction({
    required this.type,
    required this.path,
    required this.content,
  });

  int get lineCount => content.isEmpty ? 0 : content.split('\n').length;
}

class AiResponseBundle {
  final String summary;
  final List<AiFileAction> actions;
  final String rawText;

  const AiResponseBundle({
    required this.summary,
    required this.actions,
    required this.rawText,
  });
}

class AiCodeFixResult {
  final String fixedCode;
  final String explanation;
  final bool changed;

  const AiCodeFixResult({
    required this.fixedCode,
    required this.explanation,
    required this.changed,
  });
}

class AiConnectionTestResult {
  final bool ok;
  final int latencyMs;
  final String message;

  const AiConnectionTestResult({
    required this.ok,
    required this.latencyMs,
    required this.message,
  });
}

class AiEngine {
  /// Detects if a user's message is asking to build/create a new app.
  static bool isBuildAppIntent(String text) {
    final low = text.toLowerCase().trim();
    if (low.isEmpty) return false;
    const keywords = [
      'ابني',
      'ابنِ',
      'اصنع',
      'اعمل تطبيق',
      'اعمل لي تطبيق',
      'اعملي تطبيق',
      'انشئ',
      'أنشئ',
      'تطبيق جديد',
      'مشروع جديد',
      'بناء تطبيق',
      'برمج تطبيق',
      'صمم تطبيق',
      'build app',
      'create app',
      'make an app',
      'new app',
      'generate app',
    ];
    for (final k in keywords) {
      if (low.contains(k)) return true;
    }
    return false;
  }

  static String _resolveOpenAiBase(String providerId, String customUrl) {
    switch (providerId) {
      case 'openai':
        return 'https://api.openai.com/v1';
      case 'openrouter':
        return 'https://openrouter.ai/api/v1';
      case 'deepseek':
        return 'https://api.deepseek.com/v1';
      case 'groq':
        return 'https://api.groq.com/openai/v1';
      case 'custom':
        final clean = customUrl.trim().replaceAll(RegExp(r'/+$'), '');
        if (clean.endsWith('/chat/completions')) {
          return clean.substring(0, clean.length - '/chat/completions'.length);
        }
        return clean;
      default:
        return 'https://api.openai.com/v1';
    }
  }

  /// Dynamically fetches available model IDs from the configured provider API.
  static Future<List<String>> fetchAvailableModels({
    String? providerId,
    String? apiKey,
    String? customBaseUrl,
  }) async {
    final pid = providerId ?? appState.aiProviderId;
    final key = (apiKey ?? appState.aiApiKey).trim();
    final customUrl = (customBaseUrl ?? appState.aiCustomBaseUrl).trim();
    if (key.isEmpty) {
      throw Exception('أدخل مفتاح API أولاً لجلب النماذج المتاحة.');
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      if (pid == 'gemini') {
        final uri = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models?key=${Uri.encodeQueryComponent(key)}',
        );
        final req = await client.getUrl(uri).timeout(const Duration(seconds: 20));
        final res = await req.close().timeout(const Duration(seconds: 20));
        final body = await res.transform(utf8.decoder).join();
        if (res.statusCode < 200 || res.statusCode >= 300) {
          throw Exception(_extractApiError(body, res.statusCode));
        }
        final decoded = jsonDecode(body) as Map<String, dynamic>;
        final models = (decoded['models'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .where((m) {
              final methods = (m['supportedGenerationMethods'] as List? ?? [])
                  .map((e) => e.toString())
                  .toList();
              return methods.contains('generateContent');
            })
            .map((m) => (m['name'] ?? '').toString().replaceFirst('models/', ''))
            .where((id) => id.isNotEmpty)
            .toList();
        models.sort();
        return models;
      }

      final base = _resolveOpenAiBase(pid, customUrl);
      if (base.isEmpty) {
        throw Exception('أدخل رابط Base URL أولاً.');
      }
      final uri = Uri.parse('$base/models');
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 20));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
      final res = await req.close().timeout(const Duration(seconds: 20));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception(_extractApiError(body, res.statusCode));
      }
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final list = (decoded['data'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map((m) => (m['id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toList();
      list.sort();
      return list.take(50).toList();
    } finally {
      client.close(force: true);
    }
  }

  /// Sends a completion request with automatic retry on transient network/429 errors.
  static Future<String> sendPrompt({
    required String systemPrompt,
    required String userPrompt,
    List<Map<String, String>> history = const [],
    String? providerIdOverride,
    String? apiKeyOverride,
    String? modelOverride,
    String? customUrlOverride,
    double? temperatureOverride,
    int? maxTokensOverride,
    int timeoutSeconds = 110,
    int retries = 2,
  }) async {
    final providerId = providerIdOverride ?? appState.aiProviderId;
    final apiKey = (apiKeyOverride ?? appState.aiApiKey).trim();
    final model = (modelOverride ?? appState.aiModel).trim();
    final customUrl = (customUrlOverride ?? appState.aiCustomBaseUrl).trim();
    final temp = temperatureOverride ?? appState.aiTemperature;
    final maxTok = maxTokensOverride ?? appState.aiMaxTokens;

    final fullSystemPrompt = appState.aiSystemPromptExtra.trim().isEmpty
        ? systemPrompt
        : '$systemPrompt\n\nAdditional user preferences:\n${appState.aiSystemPromptExtra.trim()}';

    if (apiKey.isEmpty) {
      throw Exception('مفتاح AI غير مُضاف. أضف مفتاح API من الإعدادات أولاً.');
    }
    if (model.isEmpty) {
      throw Exception('اسم النموذج (Model) غير محدد.');
    }

    Object? lastErr;
    for (var attempt = 0; attempt <= retries; attempt++) {
      final client = HttpClient()
        ..connectionTimeout = Duration(seconds: timeoutSeconds);
      try {
        if (providerId == 'gemini') {
          return await _callGemini(
            client: client,
            apiKey: apiKey,
            model: model,
            systemPrompt: fullSystemPrompt,
            userPrompt: userPrompt,
            history: history,
            temperature: temp,
            maxTokens: maxTok,
            timeoutSeconds: timeoutSeconds,
          );
        }

        final base = _resolveOpenAiBase(providerId, customUrl);
        if (base.isEmpty) {
          throw Exception('أدخل رابط الخادم المخصص (Base URL) في الإعدادات.');
        }
        final endpoint = '$base/chat/completions';

        return await _callOpenAiCompatible(
          client: client,
          endpoint: endpoint,
          apiKey: apiKey,
          model: model,
          systemPrompt: fullSystemPrompt,
          userPrompt: userPrompt,
          history: history,
          temperature: temp,
          maxTokens: maxTok,
          timeoutSeconds: timeoutSeconds,
          isOpenRouter: providerId == 'openrouter',
        );
      } catch (e) {
        lastErr = e;
        final msg = e.toString().toLowerCase();
        final transient = msg.contains('429') ||
            msg.contains('503') ||
            msg.contains('502') ||
            msg.contains('timeout') ||
            msg.contains('socketexception');
        if (!transient || attempt >= retries) rethrow;
        await Future<void>.delayed(Duration(seconds: (attempt + 1) * 2));
      } finally {
        client.close(force: true);
      }
    }
    throw lastErr ?? Exception('تعذّر الاتصال بخدمة الذكاء الاصطناعي.');
  }

  static Future<String> _callGemini({
    required HttpClient client,
    required String apiKey,
    required String model,
    required String systemPrompt,
    required String userPrompt,
    required List<Map<String, String>> history,
    required double temperature,
    required int maxTokens,
    required int timeoutSeconds,
  }) async {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/${Uri.encodeComponent(model)}:generateContent?key=${Uri.encodeQueryComponent(apiKey)}',
    );
    final req =
        await client.postUrl(uri).timeout(Duration(seconds: timeoutSeconds));
    req.headers.set(
      HttpHeaders.contentTypeHeader,
      'application/json; charset=utf-8',
    );

    final contents = <Map<String, dynamic>>[];
    for (final h in history) {
      final role = h['role'] == 'assistant' ? 'model' : 'user';
      contents.add({
        'role': role,
        'parts': [
          {'text': h['content'] ?? ''}
        ],
      });
    }
    contents.add({
      'role': 'user',
      'parts': [
        {'text': userPrompt}
      ],
    });

    final payload = {
      'system_instruction': {
        'parts': [
          {'text': systemPrompt}
        ],
      },
      'contents': contents,
      'generationConfig': {
        'temperature': temperature,
        'maxOutputTokens': maxTokens,
      },
    };

    req.add(utf8.encode(jsonEncode(payload)));
    final res = await req.close().timeout(Duration(seconds: timeoutSeconds));
    final bodyStr = await res.transform(utf8.decoder).join();

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(_extractApiError(bodyStr, res.statusCode));
    }

    final decoded = jsonDecode(bodyStr) as Map<String, dynamic>;
    final candidates = decoded['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      throw Exception('لم يُرجع النموذج أي رد (Empty candidates).');
    }
    final parts = (candidates.first['content']?['parts'] as List?) ?? const [];
    final buf = StringBuffer();
    for (final part in parts) {
      if (part is Map && part['text'] != null) {
        buf.write(part['text']);
      }
    }
    final out = buf.toString().trim();
    if (out.isEmpty) {
      throw Exception('رد النموذج فارغ.');
    }
    return out;
  }

  static Future<String> _callOpenAiCompatible({
    required HttpClient client,
    required String endpoint,
    required String apiKey,
    required String model,
    required String systemPrompt,
    required String userPrompt,
    required List<Map<String, String>> history,
    required double temperature,
    required int maxTokens,
    required int timeoutSeconds,
    bool isOpenRouter = false,
  }) async {
    final uri = Uri.parse(endpoint);
    final req =
        await client.postUrl(uri).timeout(Duration(seconds: timeoutSeconds));
    req.headers.set(
      HttpHeaders.contentTypeHeader,
      'application/json; charset=utf-8',
    );
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
    if (isOpenRouter) {
      req.headers.set('HTTP-Referer', 'https://joohub.app');
      req.headers.set('X-Title', 'JOOhub');
    }

    final messages = <Map<String, String>>[
      {'role': 'system', 'content': systemPrompt},
      ...history,
      {'role': 'user', 'content': userPrompt},
    ];

    final payload = <String, dynamic>{
      'model': model,
      'messages': messages,
      'max_tokens': maxTokens,
    };
    // Reasoning models like o3-mini don't accept custom temperature
    if (!model.toLowerCase().startsWith('o3') &&
        !model.toLowerCase().startsWith('o1')) {
      payload['temperature'] = temperature;
    }

    req.add(utf8.encode(jsonEncode(payload)));
    final res = await req.close().timeout(Duration(seconds: timeoutSeconds));
    final bodyStr = await res.transform(utf8.decoder).join();

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(_extractApiError(bodyStr, res.statusCode));
    }

    final decoded = jsonDecode(bodyStr) as Map<String, dynamic>;
    final choices = decoded['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw Exception('لم يُرجع النموذج أي رد (Empty choices).');
    }
    final content =
        (choices.first['message']?['content'] ?? '').toString().trim();
    if (content.isEmpty) {
      throw Exception('رد النموذج فارغ.');
    }
    return content;
  }

  static String _extractApiError(String bodyStr, int status) {
    if (status == 401 || status == 403) {
      return 'مفتاح API غير صحيح أو غير مصرح له (HTTP $status). تأكد من المفتاح في الإعدادات.';
    }
    if (status == 429) {
      return 'تم تجاوز حد الطلبات (Rate Limit / Quota 429). انتظر قليلاً أو جرّب نموذجاً آخر.';
    }
    try {
      final decoded = jsonDecode(bodyStr);
      if (decoded is Map) {
        final err = decoded['error'];
        if (err is Map && err['message'] != null) {
          return 'HTTP $status: ${err['message']}';
        }
        if (decoded['message'] != null) {
          return 'HTTP $status: ${decoded['message']}';
        }
      }
    } catch (_) {}
    final short = bodyStr.length > 180 ? bodyStr.substring(0, 180) : bodyStr;
    return 'HTTP $status: $short';
  }

  /// Tests connectivity to the configured AI provider & model.
  static Future<AiConnectionTestResult> testConnection({
    String? providerId,
    String? apiKey,
    String? model,
    String? customBaseUrl,
  }) async {
    final sw = Stopwatch()..start();
    try {
      final reply = await sendPrompt(
        systemPrompt: 'Reply with OK only.',
        userPrompt: 'Ping',
        providerIdOverride: providerId,
        apiKeyOverride: apiKey,
        modelOverride: model,
        customUrlOverride: customBaseUrl,
        timeoutSeconds: 20,
        retries: 0,
      );
      sw.stop();
      return AiConnectionTestResult(
        ok: true,
        latencyMs: sw.elapsedMilliseconds,
        message:
            'متصل بنجاح (${sw.elapsedMilliseconds} ms) — ${reply.split('\n').first}',
      );
    } catch (e) {
      sw.stop();
      return AiConnectionTestResult(
        ok: false,
        latencyMs: sw.elapsedMilliseconds,
        message: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  /// Inline Code Editor AI Fixer, Refactorer & Explainer.
  static Future<AiCodeFixResult> fixCodeWithAi({
    required String filePath,
    required String code,
    required String instruction,
    List<String> detectedIssues = const [],
  }) async {
    const systemPrompt = '''
You are JOOhub AI Code Doctor — an expert Flutter, Dart, Kotlin, YAML, and XML debugger.
Fix bugs, syntax errors, missing imports, null-safety issues, or apply the user's requested edit to the provided file.
Respond ONLY with a valid JSON object using this exact schema:
{
  "explanation": "شرح عربي مختصر وواضح لما تم إصلاحه أو تعديله",
  "code": "FULL corrected file content here (never partial snippets or ellipses)"
}
Rules:
1. Return the COMPLETE file content in "code".
2. Ensure zero syntax errors, valid brackets/quotes, null-safety, const IconData, and RTL compatibility where appropriate.
3. Preserve all existing working logic unless fixing a bug or fulfilling the instruction.
''';

    final issuesBlock = detectedIssues.isEmpty
        ? 'None reported.'
        : detectedIssues.map((e) => '- $e').join('\n');

    final userPrompt = '''
FILE: $filePath
DETECTED STATIC ISSUES:
$issuesBlock

INSTRUCTION:
$instruction

CURRENT CODE:
```
$code
```
''';

    final raw = await sendPrompt(
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      timeoutSeconds: 90,
    );

    final jsonStr = _extractJsonObject(raw.trim());
    if (jsonStr != null) {
      try {
        final m = jsonDecode(jsonStr) as Map<String, dynamic>;
        final exp = (m['explanation'] ?? 'تم إصلاح الكود بنجاح.').toString().trim();
        final fixed = (m['code'] ?? '').toString();
        if (fixed.trim().isNotEmpty) {
          return AiCodeFixResult(
            fixedCode: fixed,
            explanation: exp,
            changed: fixed != code,
          );
        }
      } catch (_) {}
    }

    // Fallback: extract code fence
    final fence = RegExp(r'```[a-zA-Z0-9_+-]*\n([\s\S]*?)```').firstMatch(raw);
    if (fence != null) {
      final extracted = fence.group(1)!.trimRight();
      return AiCodeFixResult(
        fixedCode: extracted,
        explanation: 'تم إصلاح وتحديث الكود بالذكاء الاصطناعي.',
        changed: extracted != code,
      );
    }

    return AiCodeFixResult(
      fixedCode: code,
      explanation: raw.trim(),
      changed: false,
    );
  }

  /// Reads real project files to build a rich context snapshot for AI project management.
  static Future<String> collectProjectContext(
    LocalProject proj, {
    int maxChars = 32000,
  }) async {
    final root = Directory(proj.path);
    if (!await root.exists()) return 'المجلد غير موجود.';

    const ignoredDirs = {'.git', 'build', '.dart_tool', '.gradle', '.joohub'};
    const textExts = {
      '.dart',
      '.yaml',
      '.yml',
      '.json',
      '.xml',
      '.kts',
      '.gradle',
      '.kt',
      '.java',
      '.md',
      '.html',
      '.css',
      '.js',
      '.txt',
    };

    final allRelPaths = <String>[];
    final readableFiles = <File>[];

    await for (final ent in root.list(recursive: true, followLinks: false)) {
      if (ent is! File) continue;
      final rel = p.relative(ent.path, from: root.path).replaceAll('\\', '/');
      if (p.split(rel).any((s) => ignoredDirs.contains(s))) continue;
      allRelPaths.add(rel);
      final ext = p.extension(ent.path).toLowerCase();
      if (textExts.contains(ext)) {
        readableFiles.add(ent);
      }
    }

    allRelPaths.sort();
    readableFiles.sort((a, b) {
      int score(File f) {
        final r = p.relative(f.path, from: root.path).replaceAll('\\', '/');
        if (r == 'pubspec.yaml') return 0;
        if (r == 'lib/main.dart') return 1;
        if (r.startsWith('lib/')) return 2;
        if (r.endsWith('AndroidManifest.xml')) return 3;
        return 4;
      }

      final cmp = score(a).compareTo(score(b));
      return cmp != 0 ? cmp : a.path.compareTo(b.path);
    });

    final buf = StringBuffer()
      ..writeln('PROJECT NAME: ${proj.name}')
      ..writeln('PACKAGE: ${proj.packageName}')
      ..writeln('FILES (${allRelPaths.length}):')
      ..writeln(allRelPaths.take(100).join('\n'))
      ..writeln('\n--- FILE CONTENTS ---');

    var used = buf.length;
    for (final f in readableFiles) {
      if (used >= maxChars) break;
      try {
        final rel = p.relative(f.path, from: root.path).replaceAll('\\', '/');
        var txt = await f.readAsString();
        if (txt.length > 6500) {
          txt = '${txt.substring(0, 6500)}\n// ... [truncated]';
        }
        final block = '\n=== FILE: $rel ===\n$txt\n';
        if (used + block.length > maxChars) continue;
        buf.write(block);
        used += block.length;
      } catch (_) {}
    }
    return buf.toString();
  }

  /// Sends a project-management/update request to AI and parses file actions.
  static Future<AiResponseBundle> manageProject({
    required LocalProject project,
    required String userInstruction,
    List<Map<String, String>> chatHistory = const [],
  }) async {
    final contextSnapshot = await collectProjectContext(project);

    const systemPrompt = '''
You are JOOhub AI — a senior Flutter & mobile software architect managing an existing project.
When the user asks to modify, fix, debug, refactor, or add features to the project, respond ONLY with a valid JSON object using this exact schema:
{
  "summary": "شرح عربي واضح ومختصر لما تم تعديله أو إجابته",
  "actions": [
    {
      "type": "write",
      "path": "lib/main.dart",
      "content": "FULL updated file content here"
    }
  ]
}
Rules:
1. If the user is only asking a question (no code edits needed), return "actions": [].
2. For every file in "actions" with type "write", ALWAYS output the COMPLETE file content (never partial diffs or ellipses).
3. Use relative paths inside the project (e.g., "lib/screens/home_screen.dart", "pubspec.yaml").
4. You may also use "type": "delete" with "content": "" to remove obsolete files.
5. Ensure valid, compilable Flutter/Dart code compatible with Flutter 3.x and Material 3. Never use fake/demo placeholder data unless requested.
6. Reply in Arabic in the "summary" field.
''';

    final userPrompt = '''
$contextSnapshot

=== USER REQUEST ===
$userInstruction
''';

    final raw = await sendPrompt(
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      history: chatHistory,
    );

    return parseAiBundle(raw);
  }

  /// Generates a complete multi-file Flutter application from [AiBuildSpec] and writes it to disk.
  static Future<({LocalProject project, AiResponseBundle bundle})> buildFullApp({
    required AiBuildSpec spec,
    void Function(String step, double progress)? onProgress,
  }) async {
    onProgress?.call('الاتصال بالنموذج وتوليد هيكل التطبيق الكامل...', 0.15);

    const systemPrompt = '''
You are JOOhub AI Full-App Builder.
Generate a COMPLETE, production-ready, compilable Flutter application based on the user's exact specification.
Respond ONLY with a valid JSON object matching this exact schema:
{
  "summary": "ملخص عربي مختصر للتطبيق المبني والملفات المنشأة",
  "files": [
    {
      "path": "pubspec.yaml",
      "content": "..."
    },
    {
      "path": "lib/main.dart",
      "content": "..."
    }
  ]
}
STRICT REQUIREMENTS:
1. Output COMPLETE, real, working, cleanly structured multi-file Flutter code (e.g., pubspec.yaml, lib/main.dart, lib/theme/app_theme.dart, lib/models/..., lib/screens/..., lib/widgets/...).
2. Keep dependencies in pubspec.yaml minimal and standard (prefer pure Flutter/Dart SDK widgets + standard packages only if truly needed; NEVER invent non-existent packages).
3. Avoid any hardcoded fake/demo data (no fake user stats or fake product lists); build clean, real interactive empty states where the user can add/manage their own real items immediately.
4. Strictly follow the user's chosen App Name, Package Name, Visual Style, Accent Color, Language/Directionality, Navigation Structure, and Features.
5. Ensure zero syntax errors, proper null-safety, `const IconData`, and `AlignmentDirectional` for RTL support.
''';

    final userPrompt = '''
Build a complete Flutter app with these exact specifications:
- User Idea / Prompt: ${spec.prompt}
- App Name: ${spec.appName}
- Package Name: ${spec.packageName}
- Category: ${spec.category}
- Visual Style / Theme: ${spec.visualStyle}
- Primary Accent Color: ${spec.accentName} (${spec.accentHex})
- Language & Direction: ${spec.language}
- Navigation Structure: ${spec.navigation}
- Selected Features: ${spec.features.isEmpty ? 'Standard clean architecture' : spec.features.join(', ')}

Generate all necessary Dart files and pubspec.yaml now as JSON.
''';

    final raw = await sendPrompt(
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      timeoutSeconds: 130,
    );

    onProgress?.call('تحليل الملفات المولّدة من الذكاء الاصطناعي...', 0.55);
    final bundle = parseAiBundle(raw);

    if (bundle.actions.isEmpty) {
      throw Exception(
        'لم يتمكن النموذج من توليد ملفات صالحة. جرّب توضيح الفكرة أو تغيير النموذج.',
      );
    }

    onProgress?.call('إنشاء مجلد المشروع وتجهيز ملفات أندرويد...', 0.72);
    final root = await WorkspaceManager.workspaceRoot();
    final folderName = WorkspaceManager.sanitizeFolderName(spec.appName);
    var dir = Directory(p.join(root.path, folderName));
    if (await dir.exists()) {
      dir = Directory(
        p.join(root.path,
            '${folderName}_${DateTime.now().millisecondsSinceEpoch % 1000}'),
      );
    }
    await dir.create(recursive: true);

    onProgress?.call('كتابة ${bundle.actions.length} ملف في مساحة العمل...', 0.84);
    var hasPubspec = false;
    for (final act in bundle.actions) {
      if (act.type == 'delete') continue;
      final cleanRel = _sanitizeRelativePath(act.path);
      if (cleanRel.isEmpty) continue;
      if (cleanRel == 'pubspec.yaml') hasPubspec = true;
      final outFile = File(p.join(dir.path, cleanRel));
      await outFile.parent.create(recursive: true);
      await outFile.writeAsString(act.content);
    }

    if (!hasPubspec) {
      final safeId =
          folderName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
      final pubName = safeId.isEmpty || RegExp(r'^[0-9]').hasMatch(safeId)
          ? 'app_$safeId'
          : safeId;
      await File(p.join(dir.path, 'pubspec.yaml')).writeAsString(
        'name: $pubName\n'
        'description: "${spec.appName}"\n'
        'publish_to: \'none\'\n'
        'version: 1.0.0+1\n\n'
        'environment:\n'
        '  sdk: ">=3.2.0 <4.0.0"\n\n'
        'dependencies:\n'
        '  flutter:\n'
        '    sdk: flutter\n\n'
        'flutter:\n'
        '  uses-material-design: true\n',
      );
    }

    final manifest = File(
      p.join(dir.path, 'android', 'app', 'src', 'main', 'AndroidManifest.xml'),
    );
    if (!await manifest.exists()) {
      final safeLabel = spec.appName.replaceAll('"', '');
      await manifest.parent.create(recursive: true);
      await manifest.writeAsString(
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <uses-permission android:name="android.permission.INTERNET"/>\n'
        '    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>\n'
        '    <application\n'
        '        android:label="$safeLabel"\n'
        '        android:icon="@mipmap/ic_launcher"\n'
        '        android:usesCleartextTraffic="true">\n'
        '    </application>\n'
        '</manifest>\n',
      );
    }

    onProgress?.call('تطبيق الاسم والباكدج والأيقونة وملف APK Workflow...', 0.94);
    final proj = await WorkspaceManager.applyProjectIdentity(
      projectDir: dir,
      appName: spec.appName,
      packageName: spec.packageName,
      iconSourcePath: spec.iconPath,
    );

    await WorkspaceManager.injectApkBuilderWorkflow(
      dir,
      appName: spec.appName,
      packageName: spec.packageName,
      buildMode: 'release_apk',
    );

    appState.setActiveProject(proj);
    await appState.recordActivity(
      'بناء تطبيق بالذكاء الاصطناعي',
      'تم بناء ${proj.name} (${proj.packageName}) — ${bundle.actions.length} ملفات',
    );

    onProgress?.call('اكتمل بناء التطبيق بالكامل!', 1.0);
    return (project: proj, bundle: bundle);
  }

  /// Applies parsed [AiFileAction] operations to an existing [LocalProject].
  /// Returns backup map of previous file contents so changes can be undone!
  static Future<({int count, Map<String, String?> backup})>
      applyActionsToProjectWithBackup(
    LocalProject proj,
    List<AiFileAction> actions,
  ) async {
    var count = 0;
    final backup = <String, String?>{};
    for (final act in actions) {
      final cleanRel = _sanitizeRelativePath(act.path);
      if (cleanRel.isEmpty) continue;
      final file = File(p.join(proj.path, cleanRel));
      if (await file.exists()) {
        try {
          backup[cleanRel] = await file.readAsString();
        } catch (_) {}
      } else {
        backup[cleanRel] = null;
      }
      if (act.type == 'delete') {
        if (await file.exists()) {
          await file.delete();
          count++;
        }
      } else {
        await file.parent.create(recursive: true);
        await file.writeAsString(act.content);
        count++;
      }
    }
    if (count > 0) {
      await appState.recordActivity(
        'تحديث مشروع بالذكاء الاصطناعي',
        'تم تطبيق $count تعديل على ${proj.name}',
      );
    }
    return (count: count, backup: backup);
  }

  static Future<int> applyActionsToProject(
    LocalProject proj,
    List<AiFileAction> actions,
  ) async {
    final res = await applyActionsToProjectWithBackup(proj, actions);
    return res.count;
  }

  static Future<void> restoreBackup(
    LocalProject proj,
    Map<String, String?> backup,
  ) async {
    for (final entry in backup.entries) {
      final file = File(p.join(proj.path, entry.key));
      if (entry.value == null) {
        if (await file.exists()) await file.delete();
      } else {
        await file.parent.create(recursive: true);
        await file.writeAsString(entry.value!);
      }
    }
  }

  static String _sanitizeRelativePath(String raw) {
    final normalized =
        raw.trim().replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');
    if (normalized.isEmpty || normalized.contains('..')) return '';
    return normalized;
  }

  static AiResponseBundle parseAiBundle(String raw) {
    final trimmed = raw.trim();
    final jsonCandidate = _extractJsonObject(trimmed);
    if (jsonCandidate != null) {
      try {
        final map = jsonDecode(jsonCandidate) as Map<String, dynamic>;
        final summary =
            (map['summary'] ?? map['message'] ?? '').toString().trim();
        final list =
            (map['actions'] as List?) ?? (map['files'] as List?) ?? const [];
        final actions = <AiFileAction>[];
        for (final item in list) {
          if (item is Map) {
            final path =
                (item['path'] ?? item['file'] ?? '').toString().trim();
            if (path.isEmpty) continue;
            final type =
                (item['type'] ?? 'write').toString().trim().toLowerCase();
            final content = (item['content'] ?? '').toString();
            actions.add(AiFileAction(type: type, path: path, content: content));
          }
        }
        return AiResponseBundle(
          summary: summary.isEmpty
              ? (actions.isNotEmpty
                  ? 'تم تجهيز ${actions.length} ملف بنجاح.'
                  : trimmed)
              : summary,
          actions: actions,
          rawText: trimmed,
        );
      } catch (_) {}
    }

    // Fallback: extract ```lang:path or // FILE: path blocks
    final actions = <AiFileAction>[];
    final blockRegex = RegExp(
      r'''```[a-zA-Z0-9_+-]*\s*(?:(?:path=|file=)?([a-zA-Z0-9_./-]+\.[a-zA-Z0-9]+))?\n([\s\S]*?)```''',
    );
    for (final m in blockRegex.allMatches(trimmed)) {
      var filePath = (m.group(1) ?? '').trim();
      final body = (m.group(2) ?? '').trimRight();
      if (filePath.isEmpty && body.isNotEmpty) {
        final firstLine = body.split('\n').first.trim();
        final headerMatch = RegExp(
          r'''^(?://|#)\s*(?:FILE|PATH):\s*([a-zA-Z0-9_./-]+\.[a-zA-Z0-9]+)''',
          caseSensitive: false,
        ).firstMatch(firstLine);
        if (headerMatch != null) {
          filePath = headerMatch.group(1)!.trim();
        }
      }
      if (filePath.isNotEmpty && body.isNotEmpty) {
        actions.add(AiFileAction(type: 'write', path: filePath, content: body));
      }
    }

    return AiResponseBundle(
      summary: actions.isNotEmpty
          ? 'تم استخراج ${actions.length} ملف جاهز للتطبيق.'
          : trimmed,
      actions: actions,
      rawText: trimmed,
    );
  }

  static String? _extractJsonObject(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    return text.substring(start, end + 1);
  }
}
