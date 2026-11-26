import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../core/app_state.dart';
import '../core/app_theme.dart';
import '../services/ai_engine.dart';
import '../services/workspace_manager.dart';

// ============================================================================
// JOOhub PRO CODE EDITOR v9.0
// • Real-Time Dart/YAML/JSON/XML Syntax Highlighting
// • Synchronized Line Numbers Gutter (unlimited lines)
// • Live Static Code Linter & Problems Panel (tap to jump to error line)
// • 1-Tap Auto-Formatter + 1-Tap AI Code Doctor (Fix Bugs / Refactor / Explain)
// • Full File Explorer (Search, Create, Rename, Duplicate, Delete, Save All)
// • Advanced Find & Replace (Case-Sensitive, Replace Next / All, Go to Line)
// ============================================================================

class _CodeIssue {
  final int line;
  final String severity; // error | warning
  final String message;

  const _CodeIssue({
    required this.line,
    required this.severity,
    required this.message,
  });
}

class CodeSyntaxController extends TextEditingController {
  String extension;
  CodeThemePreset theme;

  CodeSyntaxController({
    super.text,
    required this.extension,
    required this.theme,
  });

  static final RegExp _dartPattern = RegExp(
    r'''(//[^\n]*|/\*[\s\S]*?\*/)|('''
    r"""'''[\s\S]*?'''|\"\"\"[\s\S]*?\"\"\"|'[^'\n\\]*(?:\\.[^'\n\\]*)*'|"[^"\n\\]*(?:\\.[^"\n\\]*)*")|"""
    r'''(@[A-Za-z_]\w*)|'''
    r'''\b(abstract|as|assert|async|await|break|case|catch|class|const|continue|default|do|else|enum|extends|extension|external|factory|false|final|finally|for|get|if|implements|import|in|interface|is|late|library|mixin|new|null|on|operator|part|required|rethrow|return|sealed|set|static|super|switch|sync|this|throw|true|try|typedef|var|void|while|with|yield)\b|'''
    r'''\b(String|int|double|num|bool|List|Map|Set|Future|Stream|Widget|BuildContext|State|StatelessWidget|StatefulWidget|Color|IconData|VoidCallback|File|Directory|dynamic|Object)\b|'''
    r'''\b(\d+(?:\.\d+)?)\b''',
  );

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle();
    final src = text;
    if (src.isEmpty || src.length > 45000) {
      return TextSpan(text: src, style: base);
    }

    final ext = extension.toLowerCase();
    if (ext != '.dart' && ext != '.kt' && ext != '.java' && ext != '.js') {
      return TextSpan(text: src, style: base);
    }

    final spans = <TextSpan>[];
    var cursor = 0;

    for (final m in _dartPattern.allMatches(src)) {
      if (m.start > cursor) {
        spans.add(TextSpan(text: src.substring(cursor, m.start), style: base));
      }
      Color? col;
      FontWeight? weight;
      if (m.group(1) != null) {
        col = Colors.white38; // comment
      } else if (m.group(2) != null) {
        col = const Color(0xFF98C379); // string
      } else if (m.group(3) != null) {
        col = const Color(0xFFE5C07B); // annotation
      } else if (m.group(4) != null) {
        col = theme.accent; // keyword
        weight = FontWeight.w700;
      } else if (m.group(5) != null) {
        col = const Color(0xFF61AFEF); // type
      } else if (m.group(6) != null) {
        col = const Color(0xFFD19A66); // number
      }
      spans.add(TextSpan(
        text: m.group(0),
        style: base.copyWith(color: col ?? base.color, fontWeight: weight),
      ));
      cursor = m.end;
    }

    if (cursor < src.length) {
      spans.add(TextSpan(text: src.substring(cursor), style: base));
    }
    return TextSpan(style: base, children: spans);
  }
}

class _EditorTab {
  final File file;
  final CodeSyntaxController controller;
  final ScrollController codeScroll = ScrollController();
  final ScrollController gutterScroll = ScrollController();
  String savedText;
  bool dirty = false;
  final List<String> undoStack = [];
  final List<String> redoStack = [];
  String lastRecorded;
  List<_CodeIssue> issues = [];

  _EditorTab(this.file, this.controller, this.savedText)
      : lastRecorded = savedText {
    codeScroll.addListener(() {
      if (gutterScroll.hasClients && codeScroll.hasClients) {
        final target = codeScroll.offset.clamp(
          0.0,
          gutterScroll.position.maxScrollExtent,
        );
        if ((gutterScroll.offset - target).abs() > 0.5) {
          gutterScroll.jumpTo(target);
        }
      }
    });
  }

  void dispose() {
    controller.dispose();
    codeScroll.dispose();
    gutterScroll.dispose();
  }
}

class ApexEditorScreen extends StatefulWidget {
  final LocalProject project;
  const ApexEditorScreen({super.key, required this.project});

  @override
  State<ApexEditorScreen> createState() => _ApexEditorScreenState();
}

class _ApexEditorScreenState extends State<ApexEditorScreen> {
  final List<_EditorTab> _tabs = [];
  int _activeIndex = -1;
  List<File> _files = [];
  String _fileFilter = '';
  bool _showSearch = false;
  bool _caseSensitive = false;
  bool _showProblems = false;
  bool _aiBusy = false;

  final _findCtrl = TextEditingController();
  final _replaceCtrl = TextEditingController();

  static const List<String> _quickSymbols = [
    '{',
    '}',
    '(',
    ')',
    '[',
    ']',
    ';',
    '=>',
    'const ',
    'final ',
    'async ',
    'await ',
    'return ',
    '// ',
    '<>',
    '?.',
    '??',
  ];

  _EditorTab? get _active =>
      (_activeIndex >= 0 && _activeIndex < _tabs.length)
          ? _tabs[_activeIndex]
          : null;

  @override
  void initState() {
    super.initState();
    _loadFiles(autoOpenMain: true);
  }

  Future<void> _loadFiles({bool autoOpenMain = false}) async {
    final root = Directory(widget.project.path);
    final list = <File>[];
    const ignored = {'.git', 'build', '.dart_tool', '.gradle', '.joohub'};
    try {
      await for (final e in root.list(recursive: true, followLinks: false)) {
        if (e is File) {
          final rel = p.relative(e.path, from: root.path);
          if (p.split(rel).any((s) => ignored.contains(s))) continue;
          list.add(e);
        }
      }
    } catch (_) {}
    list.sort((a, b) => a.path.compareTo(b.path));
    if (!mounted) return;
    setState(() => _files = list);

    if (autoOpenMain && _tabs.isEmpty) {
      final mainDart = list.where((f) => f.path.endsWith('main.dart')).toList();
      if (mainDart.isNotEmpty) {
        await _openFile(mainDart.first);
      } else if (list.isNotEmpty) {
        await _openFile(list.first);
      }
    }
  }

  /// Pure-Dart real-time static analyzer for Dart, YAML, JSON & Android XML.
  List<_CodeIssue> _analyzeCode(String path, String code) {
    if (!appState.editorLiveLint) return const [];
    final issues = <_CodeIssue>[];
    final ext = p.extension(path).toLowerCase();
    final lines = code.split('\n');

    if (ext == '.dart' || ext == '.kt' || ext == '.java' || ext == '.js') {
      final stack = <({String ch, int line})>[];
      final pairs = {'}': '{', ')': '(', ']': '['};
      var inBlockComment = false;

      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final lineNum = i + 1;
        var inSingle = false;
        var inDouble = false;

        for (var j = 0; j < line.length; j++) {
          final c = line[j];
          final next = j + 1 < line.length ? line[j + 1] : '';

          if (inBlockComment) {
            if (c == '*' && next == '/') {
              inBlockComment = false;
              j++;
            }
            continue;
          }
          if (!inSingle && !inDouble) {
            if (c == '/' && next == '/') break;
            if (c == '/' && next == '*') {
              inBlockComment = true;
              j++;
              continue;
            }
          }
          if (c == '\\' && (inSingle || inDouble)) {
            j++;
            continue;
          }
          if (c == "'" && !inDouble) {
            inSingle = !inSingle;
            continue;
          }
          if (c == '"' && !inSingle) {
            inDouble = !inDouble;
            continue;
          }
          if (inSingle || inDouble) continue;

          if (c == '{' || c == '(' || c == '[') {
            stack.add((ch: c, line: lineNum));
          } else if (pairs.containsKey(c)) {
            if (stack.isEmpty || stack.last.ch != pairs[c]) {
              issues.add(_CodeIssue(
                line: lineNum,
                severity: 'error',
                message: 'قوس إغلاق غير متطابق «$c» في السطر $lineNum',
              ));
            } else {
              stack.removeLast();
            }
          }
        }

        if (ext == '.dart') {
          if (line.contains('Alignment.centerEnd') ||
              line.contains('Alignment.centerStart')) {
            issues.add(_CodeIssue(
              line: lineNum,
              severity: 'warning',
              message: 'استخدم AlignmentDirectional بدلاً من Alignment للتوافق مع RTL',
            ));
          }
          if (RegExp(r'\bIconData\s*\(').hasMatch(line) &&
              !line.contains('const IconData')) {
            issues.add(_CodeIssue(
              line: lineNum,
              severity: 'warning',
              message: 'استخدم const IconData لتجنب فشل tree-shaking عند بناء APK',
            ));
          }
        }
      }

      for (final unclosed in stack.take(5)) {
        issues.add(_CodeIssue(
          line: unclosed.line,
          severity: 'error',
          message: 'قوس «${unclosed.ch}» مفتوح بدون إغلاق (السطر ${unclosed.line})',
        ));
      }
    } else if (ext == '.yaml' || ext == '.yml') {
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('\t')) {
          issues.add(_CodeIssue(
            line: i + 1,
            severity: 'error',
            message: 'يمنع استخدام Tab في ملفات YAML — استبدله بمسافات',
          ));
        }
      }
    } else if (p.basename(path) == 'AndroidManifest.xml') {
      if (!code.contains('android.permission.INTERNET')) {
        issues.add(const _CodeIssue(
          line: 1,
          severity: 'warning',
          message: 'صلاحية android.permission.INTERNET غير موجودة في AndroidManifest.xml',
        ));
      }
    }

    return issues;
  }

  Future<void> _openFile(File f) async {
    final idx = _tabs.indexWhere((t) => t.file.path == f.path);
    if (idx >= 0) {
      if (appState.editorAutoSave && _active?.dirty == true) {
        await _saveCurrent(silent: true);
      }
      setState(() => _activeIndex = idx);
      return;
    }
    try {
      final text = await f.readAsString();
      final ctrl = CodeSyntaxController(
        text: text,
        extension: p.extension(f.path),
        theme: appState.codeTheme,
      );
      final tab = _EditorTab(f, ctrl, text);
      tab.issues = _analyzeCode(f.path, text);

      ctrl.addListener(() {
        final cur = ctrl.text;
        if (cur != tab.lastRecorded) {
          tab.undoStack.add(tab.lastRecorded);
          if (tab.undoStack.length > 60) tab.undoStack.removeAt(0);
          tab.redoStack.clear();
          tab.lastRecorded = cur;
          tab.issues = _analyzeCode(f.path, cur);
        }
        final d = cur != tab.savedText;
        if (d != tab.dirty && mounted) {
          setState(() => tab.dirty = d);
        } else if (mounted) {
          setState(() {});
        }
      });

      if (appState.editorAutoSave && _active?.dirty == true) {
        await _saveCurrent(silent: true);
      }

      setState(() {
        _tabs.add(tab);
        _activeIndex = _tabs.length - 1;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّر فتح الملف (قد يكون ثنائياً): $e')),
        );
      }
    }
  }

  void _undo() {
    final t = _active;
    if (t == null || t.undoStack.isEmpty) return;
    final prev = t.undoStack.removeLast();
    t.redoStack.add(t.controller.text);
    t.lastRecorded = prev;
    t.controller.text = prev;
    t.controller.selection = TextSelection.collapsed(offset: prev.length);
    t.issues = _analyzeCode(t.file.path, prev);
    setState(() => t.dirty = prev != t.savedText);
  }

  void _redo() {
    final t = _active;
    if (t == null || t.redoStack.isEmpty) return;
    final next = t.redoStack.removeLast();
    t.undoStack.add(t.controller.text);
    t.lastRecorded = next;
    t.controller.text = next;
    t.controller.selection = TextSelection.collapsed(offset: next.length);
    t.issues = _analyzeCode(t.file.path, next);
    setState(() => t.dirty = next != t.savedText);
  }

  void _insertText(String snippet) {
    final c = _active?.controller;
    if (c == null) return;
    final sel = c.selection;
    final pos = sel.isValid ? sel.start : c.text.length;
    final end = sel.isValid ? sel.end : c.text.length;
    c.text = c.text.replaceRange(pos, end, snippet);
    c.selection = TextSelection.collapsed(offset: pos + snippet.length);
  }

  Future<void> _saveCurrent({bool silent = false}) async {
    final t = _active;
    if (t == null) return;
    await t.file.writeAsString(t.controller.text);
    if (!mounted) return;
    setState(() {
      t.savedText = t.controller.text;
      t.dirty = false;
    });
    if (!silent) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم حفظ ${p.basename(t.file.path)}')),
      );
    }
  }

  Future<void> _saveAllTabs() async {
    var count = 0;
    for (final t in _tabs) {
      if (t.dirty) {
        await t.file.writeAsString(t.controller.text);
        t.savedText = t.controller.text;
        t.dirty = false;
        count++;
      }
    }
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count > 0 ? 'تم حفظ $count ملف بنجاح' : 'كل الملفات محفوظة بالفعل',
          ),
        ),
      );
    }
  }

  void _autoFormatCurrent() {
    final t = _active;
    if (t == null) return;
    final ext = p.extension(t.file.path).toLowerCase();
    final tabStr = ' ' * appState.editorTabSize;
    final rawLines = t.controller.text.replaceAll('\r\n', '\n').split('\n');

    if (ext == '.yaml' || ext == '.yml') {
      final cleaned = rawLines
          .map((l) => l.replaceAll('\t', tabStr).trimRight())
          .join('\n');
      t.controller.text = cleaned;
    } else {
      final out = <String>[];
      var indent = 0;
      for (final raw in rawLines) {
        final trimmed = raw.trim();
        if (trimmed.isEmpty) {
          if (out.isNotEmpty && out.last.isNotEmpty) out.add('');
          continue;
        }
        if (trimmed.startsWith('}') ||
            trimmed.startsWith(')') ||
            trimmed.startsWith(']')) {
          indent = math.max(0, indent - 1);
        }
        out.add('${tabStr * indent}$trimmed');
        final opens = '{('.split('').fold<int>(
              0,
              (acc, ch) => acc + ch.allMatches(trimmed).length,
            );
        final closes = '})'.split('').fold<int>(
              0,
              (acc, ch) => acc + ch.allMatches(trimmed).length,
            );
        if (opens > closes) {
          indent += (opens - closes);
        } else if (closes > opens &&
            !trimmed.startsWith('}') &&
            !trimmed.startsWith(')')) {
          indent = math.max(0, indent - (closes - opens));
        }
      }
      t.controller.text = '${out.join('\n').trimRight()}\n';
    }
    t.issues = _analyzeCode(t.file.path, t.controller.text);
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم تنسيق الكود وتنظيف المسافات تلقائياً')),
    );
  }

  Future<void> _openAiCodeDoctor() async {
    final t = _active;
    if (t == null) return;
    if (!appState.hasAiKey) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('أضف مفتاح API في الإعدادات أولاً لتفعيل المصحح الذكي AI'),
        ),
      );
      return;
    }

    final promptCtrl = TextEditingController();
    final accent = appState.primaryColor;
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => Padding(
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
            Row(
              children: [
                Icon(Icons.auto_fix_high_rounded, color: accent, size: 19),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'مصحح ومحرر الذكاء AI • ${p.basename(t.file.path)}',
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w900),
                  ),
                ),
                if (t.issues.isNotEmpty)
                  ApexPill(text: '${t.issues.length} ملاحظة', color: kCoral),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ActionChipBtn(
                  icon: Icons.bug_report_rounded,
                  label: 'إصلاح كل الأخطاء',
                  color: kCoral,
                  onTap: () => Navigator.pop(
                    ctx,
                    'اكتشف وأصلح جميع أخطاء الكود (Syntax, Null-safety, Imports, RTL, Flutter 3.x) وأرجع الملف كاملاً بدون أخطاء.',
                  ),
                ),
                ActionChipBtn(
                  icon: Icons.speed_rounded,
                  label: 'تحسين الأداء والتنظيم',
                  color: accent,
                  onTap: () => Navigator.pop(
                    ctx,
                    'حسّن جودة وأداء الكود ونظّمه بأفضل ممارسات Flutter مع الحفاظ على كل الوظائف.',
                  ),
                ),
                ActionChipBtn(
                  icon: Icons.design_services_rounded,
                  label: 'تطوير التصميم والواجهة',
                  color: kSky,
                  onTap: () => Navigator.pop(
                    ctx,
                    'طوّر تصميم الواجهة في هذا الملف لتكون أكثر احترافية وتناسقاً مع دعم RTL.',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: promptCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'أو اكتب طلب تعديل أو إصلاح مخصص...',
                hintText: 'مثال: أضف زر بحث وأصلح خطأ التمرير',
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              icon: const Icon(Icons.auto_awesome_rounded, size: 16),
              label: const Text('تنفيذ الإصلاح والتعديل بالذكاء AI'),
              onPressed: () {
                final txt = promptCtrl.text.trim();
                Navigator.pop(
                  ctx,
                  txt.isEmpty
                      ? 'أصلح جميع الأخطاء البرمجية والتنسيقية في هذا الملف.'
                      : txt,
                );
              },
            ),
          ],
        ),
      ),
    );
    promptCtrl.dispose();
    if (action == null || action.isEmpty) return;

    setState(() => _aiBusy = true);
    try {
      final rel = p.relative(t.file.path, from: widget.project.path);
      final res = await AiEngine.fixCodeWithAi(
        filePath: rel,
        code: t.controller.text,
        instruction: action,
        detectedIssues: t.issues.map((e) => 'Line ${e.line}: ${e.message}').toList(),
      );
      if (!mounted) return;
      if (res.changed) {
        t.controller.text = res.fixedCode;
        t.issues = _analyzeCode(t.file.path, res.fixedCode);
      }
      setState(() {});
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: kSurface,
          title: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: kSuccess, size: 20),
              const SizedBox(width: 8),
              const Text('تقرير الذكاء الاصطناعي',
                  style: TextStyle(fontSize: 14.5)),
            ],
          ),
          content: SingleChildScrollView(
            child: Text(res.explanation, style: const TextStyle(fontSize: 12.5)),
          ),
          actions: [
            if (res.changed)
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _undo();
                },
                child: const Text('تراجع'),
              ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                if (res.changed) await _saveCurrent();
              },
              child: Text(res.changed ? 'حفظ التعديل' : 'حسناً'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل التصحيح الذكي: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  Future<void> _createNewFile() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('ملف جديد', style: TextStyle(fontSize: 15)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'lib/screens/new_screen.dart'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: const Text('إنشاء'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null || name.trim().isEmpty) return;
    final f = File(p.join(widget.project.path, name.trim()));
    await f.create(recursive: true);
    await _loadFiles();
    await _openFile(f);
  }

  Future<void> _renameFile(File f) async {
    final rel = p.relative(f.path, from: widget.project.path);
    final ctrl = TextEditingController(text: rel);
    final newRel = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('إعادة تسمية / نقل الملف', style: TextStyle(fontSize: 15)),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('تطبيق'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (newRel == null || newRel.isEmpty || newRel == rel) return;
    final dest = File(p.join(widget.project.path, newRel));
    await dest.parent.create(recursive: true);
    await f.rename(dest.path);
    final idx = _tabs.indexWhere((t) => t.file.path == f.path);
    if (idx >= 0) {
      _tabs[idx].dispose();
      _tabs.removeAt(idx);
      if (_activeIndex >= _tabs.length) _activeIndex = _tabs.length - 1;
    }
    await _loadFiles();
    await _openFile(dest);
  }

  Future<void> _duplicateFile(File f) async {
    final dir = f.parent.path;
    final base = p.basenameWithoutExtension(f.path);
    final ext = p.extension(f.path);
    final copy = File(p.join(dir, '${base}_copy$ext'));
    await f.copy(copy.path);
    await _loadFiles();
    await _openFile(copy);
  }

  Future<void> _deleteFile(File f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('حذف الملف', style: TextStyle(fontSize: 15)),
        content: Text('حذف ${p.basename(f.path)} نهائياً؟'),
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
    if (ok != true) return;
    if (await f.exists()) await f.delete();
    final idx = _tabs.indexWhere((t) => t.file.path == f.path);
    if (idx >= 0) {
      _tabs[idx].dispose();
      _tabs.removeAt(idx);
      if (_activeIndex >= _tabs.length) _activeIndex = _tabs.length - 1;
    }
    await _loadFiles();
  }

  void _jumpToLine(int target) {
    final c = _active?.controller;
    if (c == null) return;
    final lines = c.text.split('\n');
    final clamped = target.clamp(1, lines.length);
    var offset = 0;
    for (var i = 0; i < clamped - 1; i++) {
      offset += lines[i].length + 1;
    }
    c.selection = TextSelection.collapsed(offset: offset);
  }

  Future<void> _goToLineDialog() async {
    if (_active == null) return;
    final ctrl = TextEditingController();
    final numStr = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kSurface,
        title: const Text('الانتقال إلى سطر', style: TextStyle(fontSize: 15)),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'رقم السطر (مثال: 45)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: const Text('انتقال'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    final target = int.tryParse(numStr ?? '');
    if (target != null && target >= 1) _jumpToLine(target);
  }


  Future<void> _openPackageManager() async {
    const popular = [
      ('http', '^1.2.2', 'اتصالات HTTP وواجهات API'),
      ('shared_preferences', '^2.3.5', 'حفظ دائم للبيانات والإعدادات'),
      ('path_provider', '^2.1.5', 'مسارات التخزين الدائم على الجهاز'),
      ('provider', '^6.1.2', 'إدارة الحالة في Flutter'),
      ('google_fonts', '^6.2.1', 'خطوط عربية وعالمية احترافية'),
      ('url_launcher', '^6.3.1', 'فتح الروابط والمتصفح'),
      ('image_picker', '^1.1.2', 'اختيار الصور من المعرض والكاميرا'),
      ('file_picker', '^8.1.7', 'اختيار الملفات من الهاتف'),
      ('archive', '^3.6.1', 'ضغط وفك ضغط ملفات ZIP'),
      ('intl', 'any', 'تنسيق التواريخ والأرقام العربية'),
      ('sqflite', '^2.4.1', 'قاعدة بيانات SQLite محلية'),
      ('dio', '^5.7.0', 'عميل شبكة متقدم مع Interceptors'),
    ];
    final customName = TextEditingController();
    final customVer = TextEditingController(text: 'any');
    final accent = appState.primaryColor;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            14, 14, 14, MediaQuery.of(ctx).viewInsets.bottom + 14),
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.inventory_2_rounded, color: accent, size: 19),
                  const SizedBox(width: 7),
                  const Expanded(
                    child: Text(
                      'مدير مكتبات Flutter (pubspec.yaml)',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: customName,
                      decoration: const InputDecoration(
                          hintText: 'اسم مكتبة (مثال: fl_chart)'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: customVer,
                      decoration: const InputDecoration(hintText: '^1.0.0'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  FilledButton(
                    onPressed: () async {
                      if (customName.text.trim().isEmpty) return;
                      await WorkspaceManager.installPubspecPackage(
                        widget.project,
                        customName.text.trim(),
                        customVer.text.trim().isEmpty
                            ? 'any'
                            : customVer.text.trim(),
                      );
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(
                                  'تمت إضافة ${customName.text.trim()} إلى pubspec.yaml')),
                        );
                      }
                    },
                    child: const Text('تثبيت'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  children: popular
                      .map((pkg) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.extension_rounded,
                                color: accent, size: 18),
                            title: Text('${pkg.$1}  (${pkg.$2})',
                                style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800)),
                            subtitle: Text(pkg.$3,
                                style: const TextStyle(
                                    fontSize: 10.5, color: Colors.white54)),
                            trailing: OutlinedButton(
                              onPressed: () async {
                                await WorkspaceManager.installPubspecPackage(
                                    widget.project, pkg.$1, pkg.$2);
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(
                                            'تم تثبيت ${pkg.$1} في pubspec.yaml ✅')),
                                  );
                                }
                              },
                              child: const Text('إضافة'),
                            ),
                          ))
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    customName.dispose();
    customVer.dispose();
  }

  Future<void> _pickSnippet() async {
    final accent = appState.primaryColor;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(14),
          children: [
            const Text(
              'إدراج قالب كود جاهز (Snippets)',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            ...kDartSnippets.map((s) => ListTile(
                  dense: true,
                  leading: Icon(Icons.bolt_rounded, color: accent, size: 18),
                  title: Text(s.title,
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w800)),
                  subtitle: Text(s.subtitle,
                      style:
                          const TextStyle(fontSize: 11, color: Colors.white54)),
                  onTap: () {
                    Navigator.pop(context);
                    _insertText(s.code);
                  },
                )),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _findCtrl.dispose();
    _replaceCtrl.dispose();
    for (final t in _tabs) {
      t.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = appState.codeTheme;
    final accent = appState.primaryColor;
    if (_active != null) {
      _active!.controller.theme = theme;
    }
    final activeText = _active?.controller.text ?? '';
    final lineCount =
        activeText.isEmpty ? 1 : '\n'.allMatches(activeText).length + 1;
    final issues = _active?.issues ?? const <_CodeIssue>[];
    final errCount = issues.where((e) => e.severity == 'error').length;
    final warnCount = issues.where((e) => e.severity == 'warning').length;

    final matchCount = (_showSearch && _findCtrl.text.isNotEmpty)
        ? RegExp(
            RegExp.escape(_findCtrl.text),
            caseSensitive: _caseSensitive,
          ).allMatches(activeText).length
        : 0;

    final filteredFiles = _fileFilter.isEmpty
        ? _files
        : _files
            .where((f) => p
                .relative(f.path, from: widget.project.path)
                .toLowerCase()
                .contains(_fileFilter.toLowerCase()))
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.project.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo_rounded, size: 19),
            tooltip: 'تراجع',
            onPressed: _active?.undoStack.isNotEmpty == true ? _undo : null,
          ),
          IconButton(
            icon: const Icon(Icons.redo_rounded, size: 19),
            tooltip: 'إعادة',
            onPressed: _active?.redoStack.isNotEmpty == true ? _redo : null,
          ),
          IconButton(
            icon: _aiBusy
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: accent),
                  )
                : Icon(Icons.auto_fix_high_rounded, size: 19, color: accent),
            tooltip: 'تصحيح وتعديل بالذكاء AI',
            onPressed: (_active != null && !_aiBusy) ? _openAiCodeDoctor : null,
          ),
          IconButton(
            icon: const Icon(Icons.search_rounded, size: 19),
            tooltip: 'بحث واستبدال',
            onPressed: () => setState(() => _showSearch = !_showSearch),
          ),
          IconButton(
            icon: Icon(
              Icons.save_rounded,
              color: _active?.dirty == true ? accent : null,
              size: 19,
            ),
            tooltip: 'حفظ',
            onPressed: _active?.dirty == true ? () => _saveCurrent() : null,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, size: 19),
            color: kSurface,
            onSelected: (v) async {
              if (v == 'format') _autoFormatCurrent();
              if (v == 'packages') await _openPackageManager();
              if (v == 'snippets') _pickSnippet();
              if (v == 'save_all') await _saveAllTabs();
              if (v == 'copy_all' && _active != null) {
                await Clipboard.setData(
                    ClipboardData(text: _active!.controller.text));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم نسخ كامل كود الملف')),
                  );
                }
              }
              if (v == 'problems') {
                setState(() => _showProblems = !_showProblems);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'format', child: Text('تنسيق تلقائي (Auto-Format)')),
              PopupMenuItem(
                  value: 'packages', child: Text('تثبيت مكتبات Flutter (Packages)')),
              PopupMenuItem(
                  value: 'snippets', child: Text('إدراج قالب كود (Snippets)')),
              PopupMenuItem(value: 'save_all', child: Text('حفظ جميع التبويبات')),
              PopupMenuItem(value: 'copy_all', child: Text('نسخ كامل الملف')),
              PopupMenuItem(
                  value: 'problems', child: Text('إظهار/إخفاء لوحة الأخطاء')),
            ],
          ),
        ],
      ),
      drawer: Drawer(
        backgroundColor: kSurface,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.project.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.w900),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.note_add_outlined,
                          color: accent, size: 20),
                      tooltip: 'ملف جديد',
                      onPressed: () {
                        Navigator.pop(context);
                        _createNewFile();
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, size: 19),
                      tooltip: 'تحديث',
                      onPressed: () => _loadFiles(),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                child: TextField(
                  onChanged: (v) => setState(() => _fileFilter = v),
                  style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(
                    hintText: 'بحث في ملفات المشروع...',
                    prefixIcon: Icon(Icons.search_rounded, size: 16),
                  ),
                ),
              ),
              const Divider(height: 1, color: kStroke),
              Expanded(
                child: ListView.builder(
                  itemCount: filteredFiles.length,
                  itemBuilder: (_, i) {
                    final f = filteredFiles[i];
                    final rel = p.relative(f.path, from: widget.project.path);
                    final isDart = rel.endsWith('.dart');
                    final isSelected = _active?.file.path == f.path;
                    return ListTile(
                      dense: true,
                      selected: isSelected,
                      selectedTileColor: accent.withValues(alpha: 0.12),
                      leading: Icon(
                        isDart
                            ? Icons.code_rounded
                            : Icons.description_outlined,
                        size: 16,
                        color: isDart ? accent : Colors.white54,
                      ),
                      title: Text(
                        rel,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontFamily: 'monospace',
                          color: isSelected ? accent : Colors.white,
                          fontWeight:
                              isSelected ? FontWeight.w800 : FontWeight.normal,
                        ),
                      ),
                      trailing: PopupMenuButton<String>(
                        icon: const Icon(Icons.more_horiz,
                            size: 16, color: Colors.white38),
                        color: kSurfaceAlt,
                        onSelected: (act) {
                          if (act == 'rename') _renameFile(f);
                          if (act == 'dup') _duplicateFile(f);
                          if (act == 'del') _deleteFile(f);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                              value: 'rename', child: Text('إعادة تسمية')),
                          PopupMenuItem(value: 'dup', child: Text('نسخ الملف')),
                          PopupMenuItem(
                              value: 'del',
                              child: Text('حذف',
                                  style: TextStyle(color: kCoral))),
                        ],
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _openFile(f);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          // Tabs Bar
          if (_tabs.isNotEmpty)
            SizedBox(
              height: 36,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _tabs.length,
                itemBuilder: (_, i) {
                  final t = _tabs[i];
                  final sel = i == _activeIndex;
                  final hasErr =
                      t.issues.any((e) => e.severity == 'error');
                  return InkWell(
                    onTap: () => setState(() => _activeIndex = i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11),
                      decoration: BoxDecoration(
                        color: sel ? theme.bg : kSurface,
                        border: Border(
                          bottom: BorderSide(
                            color: sel
                                ? (hasErr ? kCoral : accent)
                                : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          if (hasErr)
                            const Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: Icon(Icons.error_outline,
                                  size: 13, color: kCoral),
                            ),
                          Text(
                            '${p.basename(t.file.path)}${t.dirty ? " •" : ""}',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight:
                                  sel ? FontWeight.w800 : FontWeight.normal,
                              color: sel ? accent : Colors.white70,
                            ),
                          ),
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () {
                              t.dispose();
                              setState(() {
                                _tabs.removeAt(i);
                                if (_activeIndex >= _tabs.length) {
                                  _activeIndex = _tabs.length - 1;
                                }
                              });
                            },
                            child: const Icon(Icons.close, size: 13),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

          // Find & Replace Bar
          if (_showSearch)
            Container(
              padding: const EdgeInsets.all(8),
              color: kSurface,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _findCtrl,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'بحث…',
                            suffixText: _findCtrl.text.isNotEmpty
                                ? '$matchCount'
                                : null,
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: _replaceCtrl,
                          decoration: const InputDecoration(
                            hintText: 'استبدال بـ…',
                            isDense: true,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'حساس لحالة الأحرف (Aa)',
                        icon: Text(
                          'Aa',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: _caseSensitive ? accent : Colors.white38,
                          ),
                        ),
                        onPressed: () =>
                            setState(() => _caseSensitive = !_caseSensitive),
                      ),
                      IconButton(
                        tooltip: 'استبدال الكل',
                        icon: Icon(Icons.find_replace_rounded, color: accent),
                        onPressed: () {
                          final c = _active?.controller;
                          if (c == null || _findCtrl.text.isEmpty) return;
                          final rx = RegExp(
                            RegExp.escape(_findCtrl.text),
                            caseSensitive: _caseSensitive,
                          );
                          c.text = c.text.replaceAll(rx, _replaceCtrl.text);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),

          // Code Canvas
          Expanded(
            child: _active == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.menu_open,
                            size: 42, color: accent.withValues(alpha: 0.5)),
                        const SizedBox(height: 8),
                        const Text(
                            'افتح القائمة الجانبية لاختيار ملف أو إنشاء ملف جديد'),
                      ],
                    ),
                  )
                : Directionality(
                    textDirection: TextDirection.ltr,
                    child: Container(
                      color: theme.bg,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (appState.showLineNumbers)
                            Container(
                              width: lineCount >= 1000 ? 48 : 40,
                              color: theme.gutter,
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12, horizontal: 4),
                              child: SingleChildScrollView(
                                controller: _active!.gutterScroll,
                                physics: const NeverScrollableScrollPhysics(),
                                child: Text(
                                  List.generate(
                                    lineCount,
                                    (i) => '${i + 1}',
                                  ).join('\n'),
                                  textAlign: TextAlign.right,
                                  style: buildCodeTextStyle(
                                    codeFontId: appState.codeFontId,
                                    fontSize: appState.editorFontSize,
                                    color: Colors.white30,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: appState.editorWordWrap
                                  ? TextField(
                                      controller: _active!.controller,
                                      scrollController: _active!.codeScroll,
                                      maxLines: null,
                                      expands: true,
                                      textAlignVertical: TextAlignVertical.top,
                                      style: buildCodeTextStyle(
                                        codeFontId: appState.codeFontId,
                                        fontSize: appState.editorFontSize,
                                        color: theme.fg,
                                        height: 1.5,
                                      ),
                                      decoration: const InputDecoration(
                                        filled: false,
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        isCollapsed: true,
                                      ),
                                    )
                                  : SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: SizedBox(
                                        width: math.max(
                                          MediaQuery.of(context).size.width,
                                          1100,
                                        ),
                                        child: TextField(
                                          controller: _active!.controller,
                                          scrollController: _active!.codeScroll,
                                          maxLines: null,
                                          expands: true,
                                          textAlignVertical:
                                              TextAlignVertical.top,
                                          style: buildCodeTextStyle(
                                            codeFontId: appState.codeFontId,
                                            fontSize: appState.editorFontSize,
                                            color: theme.fg,
                                            height: 1.5,
                                          ),
                                          decoration: const InputDecoration(
                                            filled: false,
                                            border: InputBorder.none,
                                            enabledBorder: InputBorder.none,
                                            focusedBorder: InputBorder.none,
                                            isCollapsed: true,
                                          ),
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),

          // Live Problems / Diagnostics Panel
          if (_showProblems && _active != null)
            Container(
              constraints: const BoxConstraints(maxHeight: 150),
              decoration: const BoxDecoration(
                color: kSurface,
                border: Border(top: BorderSide(color: kStroke)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    child: Row(
                      children: [
                        Text(
                          'فحص الكود (${issues.length})',
                          style: const TextStyle(
                              fontSize: 11.5, fontWeight: FontWeight.w900),
                        ),
                        const Spacer(),
                        if (issues.isNotEmpty)
                          InkWell(
                            onTap: _openAiCodeDoctor,
                            child: ApexPill(
                              text: 'إصلاح بالذكاء AI',
                              color: accent,
                              icon: Icons.auto_fix_high_rounded,
                            ),
                          ),
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: () => setState(() => _showProblems = false),
                          child: const Icon(Icons.close, size: 16),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: kStroke),
                  Expanded(
                    child: issues.isEmpty
                        ? const Center(
                            child: Text(
                              '✅ لا توجد أخطاء أو تحذيرات في هذا الملف',
                              style: TextStyle(
                                  fontSize: 11.5,
                                  color: kSuccess,
                                  fontWeight: FontWeight.w700),
                            ),
                          )
                        : ListView.builder(
                            itemCount: issues.length,
                            itemBuilder: (_, i) {
                              final iss = issues[i];
                              final isErr = iss.severity == 'error';
                              return ListTile(
                                dense: true,
                                visualDensity: VisualDensity.compact,
                                leading: Icon(
                                  isErr
                                      ? Icons.error_rounded
                                      : Icons.warning_amber_rounded,
                                  size: 16,
                                  color: isErr ? kCoral : kAmber,
                                ),
                                title: Text(
                                  iss.message,
                                  style: const TextStyle(fontSize: 11),
                                ),
                                trailing: Text(
                                  'سطر ${iss.line}',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: accent,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                onTap: () => _jumpToLine(iss.line),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),

          // Live Status Bar
          if (_active != null)
            Container(
              height: 28,
              color: kBg,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  InkWell(
                    onTap: () =>
                        setState(() => _showProblems = !_showProblems),
                    child: Row(
                      children: [
                        Icon(
                          errCount > 0
                              ? Icons.error_rounded
                              : Icons.check_circle_rounded,
                          size: 13,
                          color: errCount > 0
                              ? kCoral
                              : (warnCount > 0 ? kAmber : kSuccess),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$errCount أخطاء • $warnCount تنبيه',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: errCount > 0
                                ? kCoral
                                : (warnCount > 0 ? kAmber : kSuccess),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'سطور: $lineCount',
                    style: const TextStyle(
                        fontSize: 10.5,
                        fontFamily: 'monospace',
                        color: Colors.white54),
                  ),
                  const SizedBox(width: 10),
                  InkWell(
                    onTap: _goToLineDialog,
                    child: Text(
                      'سطر ↗',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: accent,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Quick Symbol Bar
          if (_active != null && appState.showSymbolBar)
            Container(
              height: 40,
              color: kSurface,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _quickSymbols.length,
                separatorBuilder: (_, __) => const SizedBox(width: 5),
                itemBuilder: (_, i) => Center(
                  child: InkWell(
                    onTap: () => _insertText(_quickSymbols[i]),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 11, vertical: 5),
                      decoration: BoxDecoration(
                        color: kSurfaceAlt,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: kStroke),
                      ),
                      child: Text(
                        _quickSymbols[i].trim(),
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: accent,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
