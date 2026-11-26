import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/github_engine.dart';

// ============================================================================
// JOOhub — COMPACT SOLID DESIGN SYSTEM
// Matte Carbon Obsidian (#0B0B0D / #131316 / #1B1B20) + Crisp Hairline Borders
// ============================================================================

const Color kBg = Color(0xFF0B0B0D);
const Color kSurface = Color(0xFF131316);
const Color kSurfaceAlt = Color(0xFF1B1B20);
const Color kStroke = Color(0xFF282830);

const Color kOrange = Color(0xFFFF6B00);
const Color kOrangeLight = Color(0xFFFF8F3F);
const Color kOrangeDeep = Color(0xFFEA580C);
const Color kAmber = Color(0xFFF59E0B);
const Color kSky = Color(0xFF38BDF8);
const Color kSuccess = Color(0xFF22C55E);
const Color kCoral = Color(0xFFEF4444);
const Color kViolet = Color(0xFFA78BFA);

// ============================================================================
// UI FONTS & CODE EDITOR FONTS
// ============================================================================

class UiFontPreset {
  final String id;
  final String name;
  final String sample;

  const UiFontPreset({
    required this.id,
    required this.name,
    required this.sample,
  });
}

const List<UiFontPreset> kUiFonts = [
  UiFontPreset(
    id: 'cairo',
    name: 'Cairo (افتراضي)',
    sample: 'خط عربي واضح ومناسب للواجهات',
  ),
  UiFontPreset(
    id: 'tajawal',
    name: 'Tajawal',
    sample: 'خط ناعم ومريح للقراءة',
  ),
  UiFontPreset(
    id: 'readex',
    name: 'Readex Pro',
    sample: 'خط هندسي متوازن للواجهات الحديثة',
  ),
  UiFontPreset(
    id: 'ibm',
    name: 'IBM Plex Arabic',
    sample: 'خط تقني دقيق لبيئات البرمجة',
  ),
  UiFontPreset(
    id: 'system',
    name: 'خط النظام الافتراضي',
    sample: 'يعمل بدون اتصال بالإنترنت',
  ),
];

class CodeFontPreset {
  final String id;
  final String name;

  const CodeFontPreset({required this.id, required this.name});
}

const List<CodeFontPreset> kCodeFonts = [
  CodeFontPreset(id: 'jetbrains', name: 'JetBrains Mono'),
  CodeFontPreset(id: 'fira', name: 'Fira Code'),
  CodeFontPreset(id: 'source', name: 'Source Code Pro'),
  CodeFontPreset(id: 'system', name: 'System Monospace'),
];

TextTheme buildApexTextTheme(String fontId, {double scale = 0.94}) {
  final base = ThemeData.dark().textTheme;
  TextTheme themed;
  switch (fontId) {
    case 'tajawal':
      themed = GoogleFonts.tajawalTextTheme(base);
      break;
    case 'readex':
      themed = GoogleFonts.readexProTextTheme(base);
      break;
    case 'ibm':
      themed = GoogleFonts.ibmPlexSansArabicTextTheme(base);
      break;
    case 'system':
      themed = base;
      break;
    case 'cairo':
    default:
      themed = GoogleFonts.cairoTextTheme(base);
      break;
  }
  return themed.apply(
    bodyColor: const Color(0xFFF1F1F4),
    displayColor: Colors.white,
    fontSizeFactor: scale.clamp(0.82, 1.18),
  );
}

TextStyle buildCodeTextStyle({
  required String codeFontId,
  required double fontSize,
  required Color color,
  double height = 1.48,
}) {
  switch (codeFontId) {
    case 'fira':
      return GoogleFonts.firaCode(
        fontSize: fontSize,
        color: color,
        height: height,
      );
    case 'source':
      return GoogleFonts.sourceCodePro(
        fontSize: fontSize,
        color: color,
        height: height,
      );
    case 'system':
      return TextStyle(
        fontFamily: 'monospace',
        fontSize: fontSize,
        color: color,
        height: height,
      );
    case 'jetbrains':
    default:
      return GoogleFonts.jetBrainsMono(
        fontSize: fontSize,
        color: color,
        height: height,
      );
  }
}

// ============================================================================
// ACCENT & CODE THEME PRESETS
// ============================================================================

class OrangeAccentPreset {
  final String id;
  final String name;
  final Color primary;
  final Color light;
  final Color heroStart;

  const OrangeAccentPreset({
    required this.id,
    required this.name,
    required this.primary,
    required this.light,
    required this.heroStart,
  });
}

const List<OrangeAccentPreset> kOrangeAccents = [
  OrangeAccentPreset(
    id: 'solar',
    name: 'برتقالي شمسي',
    primary: Color(0xFFFF6B00),
    light: Color(0xFFFF9248),
    heroStart: Color(0xFF22140A),
  ),
  OrangeAccentPreset(
    id: 'tangerine',
    name: 'يوسفي دافئ',
    primary: Color(0xFFF97316),
    light: Color(0xFFFB923C),
    heroStart: Color(0xFF21150B),
  ),
  OrangeAccentPreset(
    id: 'ember',
    name: 'جمر عميق',
    primary: Color(0xFFEA580C),
    light: Color(0xFFF97316),
    heroStart: Color(0xFF24110A),
  ),
  OrangeAccentPreset(
    id: 'amber',
    name: 'عنبر ذهبي',
    primary: Color(0xFFF59E0B),
    light: Color(0xFFFBBF24),
    heroStart: Color(0xFF221A09),
  ),
  OrangeAccentPreset(
    id: 'copper',
    name: 'نحاسي',
    primary: Color(0xFFD97706),
    light: Color(0xFFF59E0B),
    heroStart: Color(0xFF1F160A),
  ),
];

class CodeThemePreset {
  final String id;
  final String name;
  final Color bg;
  final Color fg;
  final Color accent;
  final Color gutter;

  const CodeThemePreset({
    required this.id,
    required this.name,
    required this.bg,
    required this.fg,
    required this.accent,
    required this.gutter,
  });
}

const List<CodeThemePreset> kCodeThemes = [
  CodeThemePreset(
    id: 'orange_obsidian',
    name: 'Obsidian Orange',
    bg: Color(0xFF0E0E11),
    fg: Color(0xFFF1F1F4),
    accent: Color(0xFFFF6B00),
    gutter: Color(0xFF151519),
  ),
  CodeThemePreset(
    id: 'ember_carbon',
    name: 'Carbon',
    bg: Color(0xFF121215),
    fg: Color(0xFFEDE8E2),
    accent: Color(0xFFF97316),
    gutter: Color(0xFF1A1A1E),
  ),
  CodeThemePreset(
    id: 'dracula',
    name: 'Dracula',
    bg: Color(0xFF1E1F29),
    fg: Color(0xFFF8F8F2),
    accent: Color(0xFFFFB86C),
    gutter: Color(0xFF252734),
  ),
  CodeThemePreset(
    id: 'monokai',
    name: 'Monokai',
    bg: Color(0xFF1F201B),
    fg: Color(0xFFF8F8F2),
    accent: Color(0xFFFD971F),
    gutter: Color(0xFF272822),
  ),
  CodeThemePreset(
    id: 'nord',
    name: 'Nord',
    bg: Color(0xFF242933),
    fg: Color(0xFFECEFF4),
    accent: Color(0xFFD08770),
    gutter: Color(0xFF2E3440),
  ),
  CodeThemePreset(
    id: 'tokyo',
    name: 'Tokyo Night',
    bg: Color(0xFF1A1B26),
    fg: Color(0xFFC0CAF5),
    accent: Color(0xFFFF9E64),
    gutter: Color(0xFF212333),
  ),
  CodeThemePreset(
    id: 'amber_paper',
    name: 'Light Paper',
    bg: Color(0xFFFAF6F0),
    fg: Color(0xFF231F1B),
    accent: Color(0xFFEA580C),
    gutter: Color(0xFFF0E8DD),
  ),
];

class CodeSnippet {
  final String title;
  final String subtitle;
  final String code;

  const CodeSnippet(this.title, this.subtitle, this.code);
}

const List<CodeSnippet> kDartSnippets = [
  CodeSnippet(
    'StatelessWidget',
    'ودجت ثابت',
    'class MyWidget extends StatelessWidget {\n'
        '  const MyWidget({super.key});\n\n'
        '  @override\n'
        '  Widget build(BuildContext context) {\n'
        '    return const SizedBox.shrink();\n'
        '  }\n'
        '}\n',
  ),
  CodeSnippet(
    'StatefulWidget',
    'شاشة بحالة متغيرة',
    'class MyScreen extends StatefulWidget {\n'
        '  const MyScreen({super.key});\n'
        '  @override\n'
        '  State<MyScreen> createState() => _MyScreenState();\n'
        '}\n\n'
        'class _MyScreenState extends State<MyScreen> {\n'
        '  @override\n'
        '  Widget build(BuildContext context) {\n'
        '    return Scaffold(\n'
        '      appBar: AppBar(title: const Text(\'Screen\')),\n'
        '      body: const Center(child: SizedBox.shrink()),\n'
        '    );\n'
        '  }\n'
        '}\n',
  ),
  CodeSnippet(
    'HTTP GET (Pure Dart)',
    'طلب API مباشر',
    'Future<String> fetchUrl(String url) async {\n'
        '  final client = HttpClient();\n'
        '  try {\n'
        '    final req = await client.getUrl(Uri.parse(url));\n'
        '    final res = await req.close();\n'
        '    return await res.transform(utf8.decoder).join();\n'
        '  } finally {\n'
        '    client.close();\n'
        '  }\n'
        '}\n',
  ),
  CodeSnippet(
    'FutureBuilder',
    'عرض بيانات غير متزامنة',
    'FutureBuilder<String>(\n'
        '  future: myFuture,\n'
        '  builder: (context, snapshot) {\n'
        '    if (snapshot.connectionState == ConnectionState.waiting) {\n'
        '      return const Center(child: CircularProgressIndicator());\n'
        '    }\n'
        '    if (snapshot.hasError) {\n'
        '      return Center(child: Text(\'\${snapshot.error}\'));\n'
        '    }\n'
        '    return Text(snapshot.data ?? \'\');\n'
        '  },\n'
        ')\n',
  ),
  CodeSnippet(
    'ListView.builder',
    'قائمة عناصر',
    'ListView.builder(\n'
        '  itemCount: items.length,\n'
        '  itemBuilder: (context, index) {\n'
        '    final item = items[index];\n'
        '    return ListTile(title: Text(item.toString()));\n'
        '  },\n'
        ')\n',
  ),
  CodeSnippet(
    'BottomSheet',
    'نافذة سفلية',
    'showModalBottomSheet<void>(\n'
        '  context: context,\n'
        '  shape: const RoundedRectangleBorder(\n'
        '    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),\n'
        '  ),\n'
        '  builder: (_) => const Padding(\n'
        '    padding: EdgeInsets.all(16),\n'
        '    child: SizedBox.shrink(),\n'
        '  ),\n'
        ');\n',
  ),
  CodeSnippet(
    'AlertDialog',
    'مربع حوار',
    'showDialog<void>(\n'
        '  context: context,\n'
        '  builder: (_) => AlertDialog(\n'
        '    title: const Text(\'تنبيه\'),\n'
        '    actions: [\n'
        '      TextButton(onPressed: () => Navigator.pop(context), child: const Text(\'حسناً\')),\n'
        '    ],\n'
        '  ),\n'
        ');\n',
  ),
  CodeSnippet(
    'JSON Parse',
    'تحليل JSON',
    'final data = jsonDecode(rawString) as Map<String, dynamic>;\n'
        'final name = (data[\'name\'] ?? \'\').toString();\n',
  ),
  CodeSnippet(
    'Navigator.push',
    'انتقال لشاشة',
    'Navigator.of(context).push(\n'
        '  MaterialPageRoute(builder: (_) => const NextScreen()),\n'
        ');\n',
  ),
];

// ============================================================================
// COMPACT SOLID UI PRIMITIVES
// ============================================================================

class ApexCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? bgColor;
  final Color? borderColor;
  final VoidCallback? onTap;
  final double radius;

  const ApexCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(11),
    this.bgColor,
    this.borderColor,
    this.onTap,
    this.radius = 12,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bgColor ?? kSurface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? kStroke, width: 1),
      ),
      child: child,
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: content,
      ),
    );
  }
}

class ApexPill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;

  const ApexPill({
    super.key,
    required this.text,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.34), width: 0.9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class StatMiniBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const StatMiniBox({
    super.key,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, color: Colors.white60),
          ),
        ],
      ),
    );
  }
}

class ActionChipBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const ActionChipBtn({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.28), width: 0.9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// STAGED UPLOAD CARD (5-STEP COMPACT PIPELINE + PAUSE / RESUME / CANCEL)
// ============================================================================

class StagedUploadCard extends StatelessWidget {
  final UploadProgress progress;
  final Color accent;
  final VoidCallback? onTogglePause;
  final VoidCallback? onCancel;

  const StagedUploadCard({
    super.key,
    required this.progress,
    required this.accent,
    this.onTogglePause,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final step = progress.stageEnum.stepNumber;
    final isDone = progress.stageEnum == UploadStage.done;
    const stages = [
      (1, 'فحص'),
      (2, 'بصمات'),
      (3, 'دفعات'),
      (4, 'تثبيت'),
      (5, 'تحقق'),
    ];

    return ApexCard(
      borderColor: isDone ? kSuccess : accent,
      bgColor: kSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                isDone
                    ? Icons.verified_rounded
                    : (progress.isPaused
                        ? Icons.pause_circle_filled
                        : Icons.cloud_upload_rounded),
                color: isDone
                    ? kSuccess
                    : (progress.isPaused ? kAmber : accent),
                size: 18,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  progress.stage,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              ApexPill(
                text: '${(progress.fraction * 100).toStringAsFixed(0)}%',
                color: isDone ? kSuccess : accent,
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: stages.map((s) {
              final num = s.$1;
              final lbl = s.$2;
              final completed = isDone || num < step;
              final active = !isDone && num == step;
              final col = completed
                  ? kSuccess
                  : (active ? accent : Colors.white24);
              return Expanded(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 1.5,
                            color: num == 1
                                ? Colors.transparent
                                : (completed || active
                                    ? col
                                    : Colors.white12),
                          ),
                        ),
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: completed || active
                                ? col.withValues(alpha: 0.2)
                                : kSurfaceAlt,
                            shape: BoxShape.circle,
                            border: Border.all(color: col, width: 1.2),
                          ),
                          child: Center(
                            child: completed
                                ? const Icon(Icons.check,
                                    size: 11, color: kSuccess)
                                : Text(
                                    '$num',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w900,
                                      color: col,
                                    ),
                                  ),
                          ),
                        ),
                        Expanded(
                          child: Container(
                            height: 1.5,
                            color: num == 5
                                ? Colors.transparent
                                : (completed ? kSuccess : Colors.white12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      lbl,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight:
                            active ? FontWeight.w800 : FontWeight.w600,
                        color: active
                            ? Colors.white
                            : (completed ? kSuccess : Colors.white38),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              minHeight: 5,
              value: progress.fraction,
              backgroundColor: kSurfaceAlt,
              color: isDone
                  ? kSuccess
                  : (progress.isPaused ? kAmber : accent),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            progress.currentFile,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10.5,
              color: Colors.white60,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              ApexPill(
                text:
                    '${GitHubApiClient.fmtBytes(progress.uploadedBytes)} / ${GitHubApiClient.fmtBytes(progress.totalBytes)}',
                color: kSky,
              ),
              ApexPill(
                text: 'ملفات: ${progress.completedFiles}/${progress.totalFiles}',
                color: accent,
              ),
              if (progress.totalBatches > 0)
                ApexPill(
                  text: 'دفعة ${progress.currentBatch}/${progress.totalBatches}',
                  color: kAmber,
                ),
              if (progress.speedBytesPerSec > 0)
                ApexPill(
                  text:
                      '${GitHubApiClient.fmtBytes(progress.speedBytesPerSec.round())}/ث',
                  color: kSuccess,
                ),
              if (progress.eta != null && !isDone)
                ApexPill(
                  text: 'متبقي: ${GitHubApiClient.fmtDuration(progress.eta)}',
                  color: Colors.white70,
                ),
              if (progress.skippedFiles > 0)
                ApexPill(
                  text: 'متطابق: ${progress.skippedFiles}',
                  color: kSuccess,
                ),
              if (progress.retriedCount > 0)
                ApexPill(
                  text: 'محاولات: ${progress.retriedCount}',
                  color: kAmber,
                ),
            ],
          ),
          if (!isDone && (onTogglePause != null || onCancel != null)) ...[
            const SizedBox(height: 9),
            Row(
              children: [
                if (onTogglePause != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: Icon(
                        progress.isPaused
                            ? Icons.play_arrow_rounded
                            : Icons.pause_rounded,
                        size: 16,
                      ),
                      label: Text(
                        progress.isPaused ? 'استئناف' : 'إيقاف مؤقت',
                      ),
                      onPressed: onTogglePause,
                    ),
                  ),
                if (onTogglePause != null && onCancel != null)
                  const SizedBox(width: 6),
                if (onCancel != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kCoral,
                        side: BorderSide(color: kCoral.withValues(alpha: 0.5)),
                      ),
                      icon: const Icon(Icons.stop_circle_outlined, size: 16),
                      label: const Text('إلغاء'),
                      onPressed: onCancel,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================================
// COMPACT ERROR DIAGNOSTIC CARD
// ============================================================================

class ErrorDiagnosticCard extends StatefulWidget {
  final GitHubException error;
  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;

  const ErrorDiagnosticCard({
    super.key,
    required this.error,
    this.onRetry,
    this.onDismiss,
  });

  @override
  State<ErrorDiagnosticCard> createState() => _ErrorDiagnosticCardState();
}

class _ErrorDiagnosticCardState extends State<ErrorDiagnosticCard> {
  bool _showTech = false;

  @override
  Widget build(BuildContext context) {
    final err = widget.error;
    return ApexCard(
      borderColor: kCoral.withValues(alpha: 0.6),
      bgColor: const Color(0xFF1A1112),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: kCoral, size: 18),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  err.title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: kCoral,
                  ),
                ),
              ),
              if (err.statusCode != 0)
                ApexPill(text: '${err.statusCode}', color: kCoral),
              if (widget.onDismiss != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.close, size: 16, color: Colors.white54),
                  onPressed: widget.onDismiss,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  err.reason,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Colors.white70,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'الحل: ${err.solution}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: kAmber,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (widget.onRetry != null)
                ActionChipBtn(
                  icon: Icons.refresh_rounded,
                  label: 'إعادة المحاولة',
                  color: kSuccess,
                  onTap: widget.onRetry!,
                ),
              ActionChipBtn(
                icon: _showTech
                    ? Icons.expand_less_rounded
                    : Icons.bug_report_outlined,
                label: _showTech ? 'إخفاء' : 'التفاصيل',
                color: kSky,
                onTap: () => setState(() => _showTech = !_showTech),
              ),
              ActionChipBtn(
                icon: Icons.copy_rounded,
                label: 'نسخ',
                color: Colors.white70,
                onTap: () async {
                  final report = 'JOOhub Error Report\n'
                      'Title: ${err.title}\n'
                      'Code: ${err.statusCode}\n'
                      'Reason: ${err.reason}\n'
                      'Technical:\n${err.technicalDetail}';
                  await Clipboard.setData(ClipboardData(text: report));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تم نسخ تقرير الخطأ')),
                    );
                  }
                },
              ),
            ],
          ),
          if (_showTech) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kStroke),
              ),
              child: SelectableText(
                err.technicalDetail,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10.5,
                  color: Colors.white70,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
