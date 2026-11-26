import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/app_state.dart';
import '../core/app_theme.dart';
import 'zip_engine.dart';

// ============================================================================
// WORKSPACE MANAGER — TEMPLATES, DOCTOR, PERMISSIONS & PUBSPEC
// ============================================================================

class ProjectTemplate {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String mainDartCode;

  const ProjectTemplate({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.mainDartCode,
  });
}

const List<ProjectTemplate> kTemplates = [
  ProjectTemplate(
    id: 'orange_saas',
    title: 'تطبيق برتقالي حديث',
    subtitle: 'واجهة داكنة عصرية باللون البرتقالي مع بطاقات وتبويبات',
    icon: Icons.local_fire_department_rounded,
    color: kOrange,
    mainDartCode: r'''import 'package:flutter/material.dart';

void main() => runApp(const OrangeProApp());

class OrangeProApp extends StatelessWidget {
  const OrangeProApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '__APP_NAME__',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0E0D0C),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFF6B00),
          secondary: Color(0xFFFF9248),
          surface: Color(0xFF171513),
        ),
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: _HomeScreen(),
      ),
    );
  }
}

class _HomeScreen extends StatefulWidget {
  const _HomeScreen();
  @override
  State<_HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<_HomeScreen> {
  int _counter = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('__APP_NAME__'),
        backgroundColor: const Color(0xFF0E0D0C),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF6B00), Color(0xFFEA580C)],
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'مرحباً بك في __APP_NAME__',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  Text('العداد التفاعلي: $_counter', style: const TextStyle(fontSize: 14)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF6B00)),
              onPressed: () => setState(() => _counter++),
              icon: const Icon(Icons.add),
              label: const Text('زيادة العداد'),
            ),
          ],
        ),
      ),
    );
  }
}
''',
  ),
  ProjectTemplate(
    id: 'starter',
    title: 'تطبيق عصري جاهز',
    subtitle: 'هيكل Material 3 داكن مع دعم RTL كامل',
    icon: Icons.rocket_launch_rounded,
    color: kOrangeLight,
    mainDartCode: r'''import 'package:flutter/material.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '__APP_NAME__',
      theme: ThemeData.dark(useMaterial3: true),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: const Text('__APP_NAME__')),
          body: const Center(
            child: Text(
              'جاهز للتطوير — __APP_NAME__',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }
}
''',
  ),
  ProjectTemplate(
    id: 'dashboard',
    title: 'لوحة تحكم وإحصائيات',
    subtitle: 'بطاقات KPI ومؤشرات أداء احترافية',
    icon: Icons.analytics_rounded,
    color: kAmber,
    mainDartCode: r'''import 'package:flutter/material.dart';

void main() => runApp(const DashboardApp());

class DashboardApp extends StatelessWidget {
  const DashboardApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: const Color(0xFF0E0D0C)),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: const Text('__APP_NAME__')),
          body: GridView.count(
            padding: const EdgeInsets.all(16),
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            children: const [
              _KpiCard('المستخدمون', '0', Color(0xFFFF6B00)),
              _KpiCard('الإيرادات', '0', Color(0xFF22C55E)),
              _KpiCard('الطلبات', '0', Color(0xFF38BDF8)),
              _KpiCard('التقييم', '—', Color(0xFFF59E0B)),
            ],
          ),
        ),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _KpiCard(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF171513),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: const TextStyle(color: Colors.white60)),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color)),
        ],
      ),
    );
  }
}
''',
  ),
  ProjectTemplate(
    id: 'store',
    title: 'متجر إلكتروني',
    subtitle: 'شبكة منتجات مع سلة تسوق تفاعلية',
    icon: Icons.shopping_bag_rounded,
    color: kSky,
    mainDartCode: r'''import 'package:flutter/material.dart';

void main() => runApp(const StoreApp());

class StoreApp extends StatefulWidget {
  const StoreApp({super.key});
  @override
  State<StoreApp> createState() => _StoreAppState();
}

class _StoreAppState extends State<StoreApp> {
  int _cart = 0;
  final List<(String, String)> _items = [];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: const Color(0xFF0E0D0C)),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('__APP_NAME__'),
            actions: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Chip(label: Text('السلة: $_cart')),
              ),
            ],
          ),
          body: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _items.length,
            itemBuilder: (_, i) => Card(
              color: const Color(0xFF171513),
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                title: Text(_items[i].$1, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(_items[i].$2, style: const TextStyle(color: Color(0xFFFF6B00))),
                trailing: IconButton(
                  icon: const Icon(Icons.add_shopping_cart, color: Color(0xFFFF6B00)),
                  onPressed: () => setState(() => _cart++),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
''',
  ),
  ProjectTemplate(
    id: 'tasks',
    title: 'مدير مهام ذكي',
    subtitle: 'إضافة، إنجاز، وحذف المهام اليومية',
    icon: Icons.task_alt_rounded,
    color: kSuccess,
    mainDartCode: r'''import 'package:flutter/material.dart';

void main() => runApp(const TasksApp());

class TasksApp extends StatefulWidget {
  const TasksApp({super.key});
  @override
  State<TasksApp> createState() => _TasksAppState();
}

class _TasksAppState extends State<TasksApp> {
  final _ctrl = TextEditingController();
  final List<(String, bool)> _tasks = [];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: const Color(0xFF0E0D0C)),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: const Text('__APP_NAME__')),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        decoration: const InputDecoration(hintText: 'أضف مهمة جديدة...'),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle, color: Color(0xFFFF6B00)),
                      onPressed: () {
                        if (_ctrl.text.trim().isEmpty) return;
                        setState(() {
                          _tasks.insert(0, (_ctrl.text.trim(), false));
                          _ctrl.clear();
                        });
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _tasks.length,
                  itemBuilder: (_, i) => CheckboxListTile(
                    value: _tasks[i].$2,
                    activeColor: const Color(0xFFFF6B00),
                    title: Text(_tasks[i].$1),
                    onChanged: (v) => setState(() => _tasks[i] = (_tasks[i].$1, v ?? false)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
''',
  ),
  ProjectTemplate(
    id: 'chat',
    title: 'تطبيق محادثة فورية',
    subtitle: 'واجهة رسائل أنيقة مع إرسال فوري',
    icon: Icons.chat_bubble_rounded,
    color: kOrangeDeep,
    mainDartCode: r'''import 'package:flutter/material.dart';

void main() => runApp(const ChatApp());

class ChatApp extends StatefulWidget {
  const ChatApp({super.key});
  @override
  State<ChatApp> createState() => _ChatAppState();
}

class _ChatAppState extends State<ChatApp> {
  final _ctrl = TextEditingController();
  final List<(String, bool)> _msgs = [];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: const Color(0xFF0E0D0C)),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: const Text('__APP_NAME__')),
          body: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(14),
                  itemCount: _msgs.length,
                  itemBuilder: (_, i) {
                    final me = _msgs[i].$2;
                    return Align(
                      alignment: me ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: me ? const Color(0xFFFF6B00) : const Color(0xFF1F1C19),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(_msgs[i].$1),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        decoration: const InputDecoration(hintText: 'اكتب رسالة...'),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send, color: Color(0xFFFF6B00)),
                      onPressed: () {
                        if (_ctrl.text.trim().isEmpty) return;
                        setState(() {
                          _msgs.add((_ctrl.text.trim(), true));
                          _ctrl.clear();
                        });
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
''',
  ),
  ProjectTemplate(
    id: 'api',
    title: 'مستكشف REST API',
    subtitle: 'اختبار الروابط وعرض JSON مباشرة',
    icon: Icons.http_rounded,
    color: kSky,
    mainDartCode: r'''import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

void main() => runApp(const ApiApp());

class ApiApp extends StatefulWidget {
  const ApiApp({super.key});
  @override
  State<ApiApp> createState() => _ApiAppState();
}

class _ApiAppState extends State<ApiApp> {
  final _urlCtrl = TextEditingController(text: 'https://api.github.com/zen');
  String _output = 'اضغط «إرسال» لاختبار الاتصال';

  Future<void> _send() async {
    setState(() => _output = 'جاري الاتصال...');
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(_urlCtrl.text.trim()));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      setState(() => _output = 'HTTP ${res.statusCode}\n\n$body');
    } catch (e) {
      setState(() => _output = 'خطأ: $e');
    } finally {
      client.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: const Color(0xFF0E0D0C)),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: const Text('__APP_NAME__')),
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(controller: _urlCtrl, decoration: const InputDecoration(labelText: 'الرابط')),
                const SizedBox(height: 10),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF6B00)),
                  onPressed: _send,
                  child: const Text('إرسال الطلب'),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: SingleChildScrollView(
                    child: SelectableText(_output, style: const TextStyle(fontFamily: 'monospace')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
''',
  ),
  ProjectTemplate(
    id: 'portfolio',
    title: 'تطبيق تعريفي / بورتفوليو',
    subtitle: 'بطاقة مطور وروابط تواصل جاهزة',
    icon: Icons.badge_rounded,
    color: kAmber,
    mainDartCode: r'''import 'package:flutter/material.dart';

void main() => runApp(const PortfolioApp());

class PortfolioApp extends StatelessWidget {
  const PortfolioApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: const Color(0xFF0E0D0C)),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: const Text('__APP_NAME__')),
          body: const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 42,
                    backgroundColor: Color(0xFFFF6B00),
                    child: Icon(Icons.person, size: 44, color: Colors.white),
                  ),
                  SizedBox(height: 14),
                  Text('__APP_NAME__', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                  SizedBox(height: 6),
                  Text('تطبيق Flutter مبني بالكامل عبر JOOhub', style: TextStyle(color: Colors.white60)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
''',
  ),
];

class AndroidPermissionDef {
  final String key;
  final String permission;
  final String label;
  final IconData icon;

  const AndroidPermissionDef({
    required this.key,
    required this.permission,
    required this.label,
    required this.icon,
  });
}

const List<AndroidPermissionDef> kAndroidPermissions = [
  AndroidPermissionDef(
    key: 'internet',
    permission: 'android.permission.INTERNET',
    label: 'الإنترنت (INTERNET)',
    icon: Icons.wifi,
  ),
  AndroidPermissionDef(
    key: 'network',
    permission: 'android.permission.ACCESS_NETWORK_STATE',
    label: 'حالة الشبكة',
    icon: Icons.network_check,
  ),
  AndroidPermissionDef(
    key: 'camera',
    permission: 'android.permission.CAMERA',
    label: 'الكاميرا',
    icon: Icons.camera_alt_outlined,
  ),
  AndroidPermissionDef(
    key: 'audio',
    permission: 'android.permission.RECORD_AUDIO',
    label: 'الميكروفون',
    icon: Icons.mic_none,
  ),
  AndroidPermissionDef(
    key: 'storage_r',
    permission: 'android.permission.READ_EXTERNAL_STORAGE',
    label: 'قراءة الملفات',
    icon: Icons.folder_open,
  ),
  AndroidPermissionDef(
    key: 'media_img',
    permission: 'android.permission.READ_MEDIA_IMAGES',
    label: 'قراءة الصور (Android 13+)',
    icon: Icons.photo_library_outlined,
  ),
  AndroidPermissionDef(
    key: 'location',
    permission: 'android.permission.ACCESS_FINE_LOCATION',
    label: 'الموقع الجغرافي (GPS)',
    icon: Icons.location_on_outlined,
  ),
  AndroidPermissionDef(
    key: 'notify',
    permission: 'android.permission.POST_NOTIFICATIONS',
    label: 'الإشعارات',
    icon: Icons.notifications_none,
  ),
  AndroidPermissionDef(
    key: 'vibrate',
    permission: 'android.permission.VIBRATE',
    label: 'الاهتزاز',
    icon: Icons.vibration,
  ),
];

class PopularPackageDef {
  final String name;
  final String version;
  final String desc;
  const PopularPackageDef(this.name, this.version, this.desc);
}

const List<PopularPackageDef> kPopularPackages = [
  PopularPackageDef('http', '^1.2.2', 'طلبات HTTP و REST APIs'),
  PopularPackageDef('dio', '^5.7.0', 'عميل شبكة متقدم مع Interceptors'),
  PopularPackageDef('provider', '^6.1.2', 'إدارة الحالة (State Management)'),
  PopularPackageDef('shared_preferences', '^2.3.3', 'تخزين البيانات المحلي'),
  PopularPackageDef('url_launcher', '^6.3.1', 'فتح الروابط والتطبيقات'),
  PopularPackageDef('image_picker', '^1.1.2', 'اختيار الصور من المعرض والكاميرا'),
  PopularPackageDef('file_picker', '^8.1.7', 'اختيار الملفات و ZIP'),
  PopularPackageDef('path', '^1.9.0', 'التعامل مع مسارات الملفات'),
  PopularPackageDef('google_fonts', '^6.2.1', 'خطوط جوجل (Cairo / Tajawal)'),
  PopularPackageDef('fl_chart', '^0.69.0', 'رسوم بيانية تفاعلية'),
  PopularPackageDef('sqflite', '^2.4.1', 'قاعدة بيانات SQLite محلية'),
  PopularPackageDef('intl', 'any', 'تنسيق التواريخ والأرقام واللغات'),
];

class ProjectHealthStats {
  final int totalFiles;
  final int dartFiles;
  final int totalLines;
  final int totalBytes;
  final bool hasInternetPermission;
  final bool hasApkWorkflow;
  final bool hasPubspec;
  final bool hasAppIcon;
  final Map<String, int> extensionCounts;

  ProjectHealthStats({
    required this.totalFiles,
    required this.dartFiles,
    required this.totalLines,
    required this.totalBytes,
    required this.hasInternetPermission,
    required this.hasApkWorkflow,
    required this.hasPubspec,
    required this.hasAppIcon,
    required this.extensionCounts,
  });

  int get score {
    var s = 40;
    if (hasPubspec) s += 15;
    if (hasInternetPermission) s += 15;
    if (hasApkWorkflow) s += 15;
    if (hasAppIcon) s += 15;
    return s;
  }
}

class WorkspaceManager {
  static const List<String> _mipmapFolders = [
    'mipmap-mdpi',
    'mipmap-hdpi',
    'mipmap-xhdpi',
    'mipmap-xxhdpi',
    'mipmap-xxxhdpi',
  ];

  static Directory? _cachedRoot;

  static Future<Directory> workspaceRoot() async {
    if (_cachedRoot != null && await _cachedRoot!.exists()) {
      return _cachedRoot!;
    }
    try {
      final docs = await getApplicationDocumentsDirectory();
      final d = Directory(p.join(docs.path, 'JOOhub_Workspace'));
      await d.create(recursive: true);
      _cachedRoot = d;
      return d;
    } catch (_) {}

    final fallback = Directory(p.join(Directory.systemTemp.path, 'joohub'));
    await fallback.create(recursive: true);
    _cachedRoot = fallback;
    return fallback;
  }

  static Future<void> installPubspecPackage(
    LocalProject proj,
    String packageName,
    String versionSpec,
  ) async {
    final f = File(p.join(proj.path, 'pubspec.yaml'));
    if (!await f.exists()) {
      throw Exception('ملف pubspec.yaml غير موجود في المشروع.');
    }
    var txt = await f.readAsString();
    final rx = RegExp('^  ${RegExp.escape(packageName)}:.*\$', multiLine: true);
    if (rx.hasMatch(txt)) {
      txt = txt.replaceFirst(rx, '  $packageName: $versionSpec');
    } else if (txt.contains('sdk: flutter')) {
      txt = txt.replaceFirst(
        'sdk: flutter',
        'sdk: flutter
  $packageName: $versionSpec',
      );
    } else if (txt.contains('dependencies:')) {
      txt = txt.replaceFirst(
        'dependencies:',
        'dependencies:
  $packageName: $versionSpec',
      );
    } else {
      txt = '$txt
dependencies:
  $packageName: $versionSpec
';
    }
    await f.writeAsString(txt, flush: true);
  }

  static String sanitizeFolderName(String raw) {
    final clean = raw.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_\-\u0600-\u06FF ]'), '');
    final ascii = clean.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_').replaceAll(RegExp(r'_+'), '_');
    final trimmed = ascii.replaceAll(RegExp(r'^_+|_+$'), '');
    return trimmed.isEmpty ? 'JOOhub_App_${DateTime.now().millisecondsSinceEpoch % 10000}' : trimmed;
  }

  static String suggestPackageName(String appName) {
    final safe = appName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
    return 'com.yossefjoo.${safe.isEmpty ? "myapp" : safe}';
  }

  static bool isValidPackageName(String pkg) {
    return RegExp(r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$').hasMatch(pkg.trim());
  }

  static Future<List<LocalProject>> listProjects() async {
    final root = await workspaceRoot();
    final items = <LocalProject>[];
    try {
      await for (final ent in root.list(recursive: false)) {
        if (ent is Directory) {
          final folderName = p.basename(ent.path);
          if (folderName.startsWith('.')) continue;
          final stat = await ent.stat();
          var appName = folderName;
          var pkg = suggestPackageName(folderName);
          var ver = '1.0.0';
          String? iconPath;

          final cfgFile =
              File(p.join(ent.path, '.joohub', 'project_config.json'));
          if (await cfgFile.exists()) {
            try {
              final j = jsonDecode(await cfgFile.readAsString())
                  as Map<String, dynamic>;
              if (j['appName'] != null && j['appName'].toString().trim().isNotEmpty) {
                appName = j['appName'].toString();
              }
              if (j['packageName'] != null) pkg = j['packageName'].toString();
              if (j['version'] != null) ver = j['version'].toString();
              if (j['iconPath'] != null) iconPath = j['iconPath'].toString();
            } catch (_) {}
          }

          // Fallback check for bundled icon inside project
          if (iconPath == null || !await File(iconPath).exists()) {
            final localIcon = File(p.join(ent.path, 'assets', 'icon', 'app_icon.png'));
            if (await localIcon.exists()) {
              iconPath = localIcon.path;
            } else {
              final mip = File(p.join(
                ent.path,
                'android',
                'app',
                'src',
                'main',
                'res',
                'mipmap-xxxhdpi',
                'ic_launcher.png',
              ));
              if (await mip.exists()) iconPath = mip.path;
            }
          }

          items.add(LocalProject(
            name: appName,
            path: ent.path,
            packageName: pkg,
            version: ver,
            iconPath: iconPath,
            modifiedAt: stat.modified,
          ));
        }
      }
    } catch (_) {}
    items.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return items;
  }

  /// Creates a complete new Flutter project with App Name, Package Name, App Icon,
  /// chosen permissions, template, and auto-injected GitHub Actions APK workflow.
  static Future<LocalProject> createProject(
    String rawAppName, {
    String? packageName,
    String? iconSourcePath,
    String version = '1.0.0',
    String buildNumber = '1',
    ProjectTemplate? template,
    List<String>? permissions,
    bool injectApkWorkflow = true,
  }) async {
    final appName = rawAppName.trim().isEmpty ? 'JOOhub App' : rawAppName.trim();
    final folderName = sanitizeFolderName(appName);
    final safeId = folderName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
    final pubName = safeId.isEmpty || RegExp(r'^[0-9]').hasMatch(safeId)
        ? 'app_$safeId'
        : safeId;
    final pkg = (packageName != null && packageName.trim().isNotEmpty)
        ? packageName.trim()
        : suggestPackageName(appName);

    final root = await workspaceRoot();
    var dir = Directory(p.join(root.path, folderName));
    if (await dir.exists()) {
      dir = Directory(
        p.join(root.path, '${folderName}_${DateTime.now().millisecondsSinceEpoch % 1000}'),
      );
    }
    await dir.create(recursive: true);

    final pubspec = File(p.join(dir.path, 'pubspec.yaml'));
    await pubspec.writeAsString(
      'name: $pubName\n'
      'description: "$appName — Created with JOOhub"\n'
      'publish_to: \'none\'\n'
      'version: $version+$buildNumber\n\n'
      'environment:\n'
      '  sdk: ">=3.2.0 <4.0.0"\n\n'
      'dependencies:\n'
      '  flutter:\n'
      '    sdk: flutter\n\n'
      'flutter:\n'
      '  uses-material-design: true\n',
    );

    final mainFile = File(p.join(dir.path, 'lib', 'main.dart'));
    await mainFile.parent.create(recursive: true);
    final tplCode = (template?.mainDartCode ?? kTemplates.first.mainDartCode)
        .replaceAll('__APP_NAME__', appName.replaceAll("'", ''));
    await mainFile.writeAsString(tplCode);

    // AndroidManifest.xml with chosen permissions
    final perms = permissions ??
        const [
          'android.permission.INTERNET',
          'android.permission.ACCESS_NETWORK_STATE',
        ];
    final permXml = perms
        .map((perm) => '    <uses-permission android:name="$perm"/>')
        .join('\n');

    final manifest = File(
      p.join(dir.path, 'android', 'app', 'src', 'main', 'AndroidManifest.xml'),
    );
    await manifest.parent.create(recursive: true);
    await manifest.writeAsString(
      '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
      '$permXml\n'
      '    <application\n'
      '        android:label="$appName"\n'
      '        android:icon="@mipmap/ic_launcher"\n'
      '        android:usesCleartextTraffic="true">\n'
      '    </application>\n'
      '</manifest>\n',
    );

    String? savedIconPath;
    if (iconSourcePath != null && iconSourcePath.trim().isNotEmpty) {
      savedIconPath = await applyAppIconToDirectory(dir, iconSourcePath);
    }

    if (injectApkWorkflow) {
      await injectApkBuilderWorkflow(
        dir,
        appName: appName,
        packageName: pkg,
        buildMode: 'release_apk',
      );
    }

    final proj = LocalProject(
      name: appName,
      path: dir.path,
      packageName: pkg,
      version: version,
      iconPath: savedIconPath,
      modifiedAt: DateTime.now(),
    );
    await ProjectConfigService(proj).save(
      ProjectConfig(
        appName: appName,
        packageName: pkg,
        version: version,
        buildNumber: buildNumber,
        iconPath: savedIconPath,
      ),
    );
    return proj;
  }

  /// Copies the user-selected icon image into assets/icon/app_icon.png
  /// AND all 5 Android mipmap-*/ic_launcher.png folders.
  static Future<String?> applyAppIconToDirectory(
    Directory projectDir,
    String sourceIconPath,
  ) async {
    final src = File(sourceIconPath);
    if (!await src.exists()) return null;
    final bytes = await src.readAsBytes();

    final assetIcon = File(p.join(projectDir.path, 'assets', 'icon', 'app_icon.png'));
    await assetIcon.parent.create(recursive: true);
    await assetIcon.writeAsBytes(bytes, flush: true);

    for (final folder in _mipmapFolders) {
      final mip = File(p.join(
        projectDir.path,
        'android',
        'app',
        'src',
        'main',
        'res',
        folder,
        'ic_launcher.png',
      ));
      await mip.parent.create(recursive: true);
      await mip.writeAsBytes(bytes, flush: true);
    }
    return assetIcon.path;
  }

  /// Applies App Name, Package Name, Version, and App Icon to ANY local or extracted project.
  static Future<LocalProject> applyProjectIdentity({
    required Directory projectDir,
    required String appName,
    required String packageName,
    String version = '1.0.0',
    String buildNumber = '1',
    String? iconSourcePath,
  }) async {
    final cleanName = appName.trim().isEmpty ? p.basename(projectDir.path) : appName.trim();
    final cleanPkg = packageName.trim().isEmpty
        ? suggestPackageName(cleanName)
        : packageName.trim();

    // 1. Update AndroidManifest.xml android:label
    final manifest = File(
      p.join(projectDir.path, 'android', 'app', 'src', 'main', 'AndroidManifest.xml'),
    );
    if (await manifest.exists()) {
      var xml = await manifest.readAsString();
      if (xml.contains('android:label=')) {
        xml = xml.replaceFirst(
          RegExp(r'android:label="[^"]*"'),
          'android:label="$cleanName"',
        );
      }
      await manifest.writeAsString(xml);
    }

    // 2. Update build.gradle / build.gradle.kts applicationId & namespace if present
    for (final gfName in ['build.gradle.kts', 'build.gradle']) {
      final gf = File(p.join(projectDir.path, 'android', 'app', gfName));
      if (await gf.exists()) {
        var txt = await gf.readAsString();
        txt = txt.replaceAllMapped(
          RegExp(r'''(applicationId\s*=?\s*)(["'])([^"']+)(["'])'''),
          (m) => '${m.group(1)}${m.group(2)}$cleanPkg${m.group(4)}',
        );
        txt = txt.replaceAllMapped(
          RegExp(r'''(namespace\s*=?\s*)(["'])([^"']+)(["'])'''),
          (m) => '${m.group(1)}${m.group(2)}$cleanPkg${m.group(4)}',
        );
        await gf.writeAsString(txt);
      }
    }

    // 3. Update pubspec.yaml version if present
    final pub = File(p.join(projectDir.path, 'pubspec.yaml'));
    if (await pub.exists()) {
      var yaml = await pub.readAsString();
      if (RegExp(r'^version:', multiLine: true).hasMatch(yaml)) {
        yaml = yaml.replaceFirst(
          RegExp(r'^version:.*$', multiLine: true),
          'version: $version+$buildNumber',
        );
        await pub.writeAsString(yaml);
      }
    }

    // 4. Apply icon if provided
    String? savedIcon;
    if (iconSourcePath != null && iconSourcePath.trim().isNotEmpty) {
      savedIcon = await applyAppIconToDirectory(projectDir, iconSourcePath);
    }

    final proj = LocalProject(
      name: cleanName,
      path: projectDir.path,
      packageName: cleanPkg,
      version: version,
      iconPath: savedIcon,
      modifiedAt: DateTime.now(),
    );
    await ProjectConfigService(proj).save(
      ProjectConfig(
        appName: cleanName,
        packageName: cleanPkg,
        version: version,
        buildNumber: buildNumber,
        iconPath: savedIcon,
      ),
    );
    return proj;
  }

  /// Injects a rock-solid GitHub Actions workflow that auto-scaffolds missing Android
  /// files, builds APK/AAB, uploads Artifacts, and publishes a direct GitHub Release.
  static Future<File> injectApkBuilderWorkflow(
    Directory projectDir, {
    required String appName,
    required String packageName,
    String buildMode = 'release_apk', // release_apk | split_apk | appbundle | debug_apk
  }) async {
    final orgParts = packageName.split('.');
    final org = orgParts.length > 1
        ? orgParts.sublist(0, orgParts.length - 1).join('.')
        : 'com.yossefjoo';
    final safeProject = sanitizeFolderName(appName).toLowerCase();

    String buildCmd;
    String artifactPath;
    if (buildMode == 'split_apk') {
      buildCmd = 'flutter build apk --release --split-per-abi --android-skip-build-dependency-validation';
      artifactPath = 'build/app/outputs/flutter-apk/*.apk';
    } else if (buildMode == 'appbundle') {
      buildCmd = 'flutter build appbundle --release --android-skip-build-dependency-validation';
      artifactPath = 'build/app/outputs/bundle/release/app-release.aab';
    } else if (buildMode == 'debug_apk') {
      buildCmd = 'flutter build apk --debug';
      artifactPath = 'build/app/outputs/flutter-apk/app-debug.apk';
    } else {
      buildCmd = 'flutter build apk --release --android-skip-build-dependency-validation';
      artifactPath = 'build/app/outputs/flutter-apk/app-release.apk';
    }

    final workflowYaml = '''name: JOOhub Cloud APK Builder

on:
  push:
    branches: [ main, master ]
  workflow_dispatch:

permissions:
  contents: write

jobs:
  build_apk:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Project
        uses: actions/checkout@v4

      - name: Setup Java 17
        uses: actions/setup-java@v4
        with:
          distribution: 'zulu'
          java-version: '17'

      - name: Setup Flutter Stable
        uses: subosito/flutter-action@v2
        with:
          channel: 'stable'
          cache: true

      - name: Auto-Scaffold Missing Android Gradle Files
        run: |
          if [ ! -f "android/build.gradle" ] && [ ! -f "android/build.gradle.kts" ]; then
            echo "Scaffolding Android platform files for $packageName..."
            mkdir -p /tmp/joohub_backup
            if [ -f "android/app/src/main/AndroidManifest.xml" ]; then
              cp android/app/src/main/AndroidManifest.xml /tmp/joohub_backup/AndroidManifest.xml
            fi
            if [ -d "android/app/src/main/res" ]; then
              cp -r android/app/src/main/res /tmp/joohub_backup/res
            fi
            flutter create . --platforms=android --org "$org" --project-name "$safeProject"
            if [ -d "/tmp/joohub_backup/res" ]; then
              cp -rf /tmp/joohub_backup/res/* android/app/src/main/res/ || true
            fi
          fi

      - name: Apply App Name & Package ID
        run: |
          if [ -f "android/app/src/main/AndroidManifest.xml" ]; then
            sed -i 's/android:label="[^"]*"/android:label="${appName.replaceAll('"', '')}"/g' android/app/src/main/AndroidManifest.xml || true
          fi

      - name: Auto-Upgrade Gradle to 9.3.1 & Permissions
        run: |
          if [ -f "android/gradle/wrapper/gradle-wrapper.properties" ]; then
            sed -i 's|gradle-[0-9.]*-bin.zip|gradle-9.3.1-bin.zip|g' android/gradle/wrapper/gradle-wrapper.properties || true
            sed -i 's|gradle-[0-9.]*-all.zip|gradle-9.3.1-bin.zip|g' android/gradle/wrapper/gradle-wrapper.properties || true
          fi
          chmod +x android/gradlew || true

      - name: Install Dependencies
        run: flutter pub get

      - name: Build Android Output
        run: $buildCmd

      - name: Upload Build Artifact
        uses: actions/upload-artifact@v4
        with:
          name: joohub-build-output
          path: $artifactPath
          retention-days: 30

      - name: Publish Direct APK Release
        if: \${{ success() }}
        uses: softprops/action-gh-release@v2
        with:
          tag_name: build-\${{ github.run_number }}
          name: "$appName — Build #\${{ github.run_number }}"
          files: $artifactPath
        env:
          GITHUB_TOKEN: \${{ secrets.GITHUB_TOKEN }}
''';

    final wfFile = File(
      p.join(projectDir.path, '.github', 'workflows', 'joohub_build_apk.yml'),
    );
    await wfFile.parent.create(recursive: true);
    await wfFile.writeAsString(workflowYaml);
    return wfFile;
  }

  static Future<ProjectHealthStats> analyzeProject(LocalProject proj) async {
    final dir = Directory(proj.path);
    var totalFiles = 0;
    var dartFiles = 0;
    var totalLines = 0;
    var totalBytes = 0;
    var hasInternet = false;
    var hasWorkflow = false;
    var hasPubspec = false;
    var hasIcon = false;
    final extCounts = <String, int>{};

    const ignored = {'.git', 'build', '.dart_tool', '.gradle'};
    try {
      await for (final ent in dir.list(recursive: true, followLinks: false)) {
        if (ent is! File) continue;
        final rel = p.relative(ent.path, from: dir.path).replaceAll('\\', '/');
        if (p.split(rel).any((s) => ignored.contains(s))) continue;
        totalFiles++;
        totalBytes += await ent.length();

        final ext = p.extension(ent.path).toLowerCase();
        final extKey = ext.isEmpty ? 'other' : ext;
        extCounts[extKey] = (extCounts[extKey] ?? 0) + 1;

        if (ext == '.dart') {
          dartFiles++;
          try {
            totalLines += (await ent.readAsLines()).length;
          } catch (_) {}
        }
        if (p.basename(ent.path) == 'pubspec.yaml') hasPubspec = true;
        if (rel.startsWith('.github/workflows/') &&
            (rel.endsWith('.yml') || rel.endsWith('.yaml'))) {
          hasWorkflow = true;
        }
        if (rel.endsWith('ic_launcher.png') || rel.endsWith('app_icon.png')) {
          hasIcon = true;
        }
        if (p.basename(ent.path) == 'AndroidManifest.xml') {
          try {
            final c = await ent.readAsString();
            if (c.contains('android.permission.INTERNET')) hasInternet = true;
          } catch (_) {}
        }
      }
    } catch (_) {}

    return ProjectHealthStats(
      totalFiles: totalFiles,
      dartFiles: dartFiles,
      totalLines: totalLines,
      totalBytes: totalBytes,
      hasInternetPermission: hasInternet,
      hasApkWorkflow: hasWorkflow,
      hasPubspec: hasPubspec,
      hasAppIcon: hasIcon,
      extensionCounts: extCounts,
    );
  }

  /// Auto-fixes common issues (missing INTERNET permission & missing APK workflow).
  static Future<List<String>> autoFixProject(LocalProject proj) async {
    final fixed = <String>[];
    final dir = Directory(proj.path);

    // 1. Ensure INTERNET permission in AndroidManifest.xml
    final manifest = File(
      p.join(dir.path, 'android', 'app', 'src', 'main', 'AndroidManifest.xml'),
    );
    if (await manifest.exists()) {
      var xml = await manifest.readAsString();
      if (!xml.contains('android.permission.INTERNET')) {
        xml = xml.replaceFirstMapped(
          RegExp(r'<manifest[^>]*>'),
          (m) => '${m.group(0)}\n    <uses-permission android:name="android.permission.INTERNET"/>',
        );
        await manifest.writeAsString(xml);
        fixed.add('تمت إضافة صلاحية INTERNET إلى AndroidManifest.xml');
      }
    } else {
      await manifest.parent.create(recursive: true);
      await manifest.writeAsString(
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <uses-permission android:name="android.permission.INTERNET"/>\n'
        '    <application android:label="${proj.name}" android:icon="@mipmap/ic_launcher"/>\n'
        '</manifest>\n',
      );
      fixed.add('تم إنشاء AndroidManifest.xml بصلاحية الإنترنت');
    }

    // 2. Ensure GitHub Actions APK workflow exists
    final wfDir = Directory(p.join(dir.path, '.github', 'workflows'));
    var hasWf = false;
    if (await wfDir.exists()) {
      await for (final f in wfDir.list()) {
        if (f is File && (f.path.endsWith('.yml') || f.path.endsWith('.yaml'))) {
          hasWf = true;
          break;
        }
      }
    }
    if (!hasWf) {
      await injectApkBuilderWorkflow(
        dir,
        appName: proj.name,
        packageName: proj.packageName,
      );
      fixed.add('تم حقن ملف بناء APK التلقائي (joohub_build_apk.yml)');
    }

    return fixed;
  }

  /// Reads active Android permissions from AndroidManifest.xml
  static Future<Set<String>> readManifestPermissions(LocalProject proj) async {
    final result = <String>{};
    final manifest = File(
      p.join(proj.path, 'android', 'app', 'src', 'main', 'AndroidManifest.xml'),
    );
    if (!await manifest.exists()) return result;
    final xml = await manifest.readAsString();
    for (final m in RegExp(r'android:name="([^"]+)"').allMatches(xml)) {
      final val = m.group(1);
      if (val != null && val.startsWith('android.permission.')) {
        result.add(val);
      }
    }
    return result;
  }

  /// Toggles an Android permission inside AndroidManifest.xml
  static Future<void> toggleManifestPermission(
    LocalProject proj,
    String permission,
    bool enable,
  ) async {
    final manifest = File(
      p.join(proj.path, 'android', 'app', 'src', 'main', 'AndroidManifest.xml'),
    );
    if (!await manifest.exists()) {
      await manifest.parent.create(recursive: true);
      await manifest.writeAsString(
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <application android:label="${proj.name}" android:icon="@mipmap/ic_launcher"/>\n'
        '</manifest>\n',
      );
    }
    var xml = await manifest.readAsString();
    final tag = '    <uses-permission android:name="$permission"/>';
    if (enable) {
      if (!xml.contains(permission)) {
        final match = RegExp(r'<manifest[^>]*>').firstMatch(xml);
        if (match != null) {
          xml = xml.replaceRange(match.end, match.end, '\n$tag');
        }
      }
    } else {
      xml = xml.replaceAll(
        RegExp(r'\s*<uses-permission[^>]*android:name="' +
            RegExp.escape(permission) +
            r'"[^>]*/>'),
        '',
      );
    }
    await manifest.writeAsString(xml);
  }

  /// Reads dependencies from pubspec.yaml
  static Future<Map<String, String>> readPubspecDependencies(LocalProject proj) async {
    final result = <String, String>{};
    final f = File(p.join(proj.path, 'pubspec.yaml'));
    if (!await f.exists()) return result;
    final lines = await f.readAsLines();
    var inDeps = false;
    for (final line in lines) {
      if (line.trim() == 'dependencies:') {
        inDeps = true;
        continue;
      }
      if (inDeps) {
        if (line.isNotEmpty && !line.startsWith(' ')) break;
        final m = RegExp(r'^  ([a-zA-Z0-9_]+):\s*(.*)$').firstMatch(line);
        if (m != null) {
          final name = m.group(1)!;
          final ver = m.group(2)!.trim();
          if (name != 'flutter') {
            result[name] = ver.isEmpty ? 'sdk' : ver;
          }
        }
      }
    }
    return result;
  }

  /// Adds or updates a dependency in pubspec.yaml
  static Future<void> addPubspecDependency(
    LocalProject proj,
    String pkgName,
    String version,
  ) async {
    final f = File(p.join(proj.path, 'pubspec.yaml'));
    if (!await f.exists()) return;
    final lines = await f.readAsLines();
    final cleanName = pkgName.trim();
    final cleanVer = version.trim().isEmpty ? 'any' : version.trim();

    // Update if exists
    for (var i = 0; i < lines.length; i++) {
      if (RegExp(r'^  ' + RegExp.escape(cleanName) + r':').hasMatch(lines[i])) {
        lines[i] = '  $cleanName: $cleanVer';
        await f.writeAsString('${lines.join('\n')}\n');
        return;
      }
    }

    // Insert right after sdk: flutter or dependencies:
    var insertAt = -1;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].trim() == 'sdk: flutter') {
        insertAt = i + 1;
        break;
      }
      if (lines[i].trim() == 'dependencies:') {
        insertAt = i + 1;
      }
    }
    if (insertAt < 0) {
      lines.addAll(['dependencies:', '  $cleanName: $cleanVer']);
    } else {
      lines.insert(insertAt, '  $cleanName: $cleanVer');
    }
    await f.writeAsString('${lines.join('\n')}\n');
  }

  /// Removes a dependency from pubspec.yaml
  static Future<void> removePubspecDependency(
    LocalProject proj,
    String pkgName,
  ) async {
    final f = File(p.join(proj.path, 'pubspec.yaml'));
    if (!await f.exists()) return;
    final lines = await f.readAsLines();
    lines.removeWhere(
      (l) => RegExp(r'^  ' + RegExp.escape(pkgName.trim()) + r':').hasMatch(l),
    );
    await f.writeAsString('${lines.join('\n')}\n');
  }

  /// Exports a local project into a clean ZIP archive in Downloads or workspace root.
  static Future<File> exportProjectToZip(LocalProject proj) async {
    final safe = sanitizeFolderName(proj.name);
    final stamp = DateTime.now().millisecondsSinceEpoch % 100000;
    String outPath;
    if (Platform.isAndroid && await Directory('/storage/emulated/0/Download').exists()) {
      outPath = '/storage/emulated/0/Download/${safe}_$stamp.zip';
    } else {
      final root = await workspaceRoot();
      outPath = p.join(root.path, '${safe}_$stamp.zip');
    }
    final outFile = File(outPath);
    await PureZipEngine.zipDirectory(Directory(proj.path), outFile);
    return outFile;
  }

  static Future<void> deleteProject(LocalProject proj) async {
    final d = Directory(proj.path);
    if (await d.exists()) {
      await d.delete(recursive: true);
    }
  }

  static String formatRelativeArabic(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} د';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} س';
    return 'منذ ${diff.inDays} ي';
  }
}
