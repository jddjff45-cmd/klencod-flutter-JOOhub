import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/app_state.dart';
import 'core/app_theme.dart';
import 'screens/ai_studio_tab.dart';
import 'screens/github_hub_tab.dart';
import 'screens/projects_home_tab.dart';
import 'screens/settings_tab.dart';
import 'screens/zip_apk_studio_tab.dart';
import 'services/background_build_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await appState.loadAll();
  runApp(const JooHubApp());
}

class JooHubApp extends StatelessWidget {
  const JooHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appState,
      builder: (context, _) {
        final primary = appState.primaryColor;
        final secondary = appState.accent.light;
        final textTheme = buildApexTextTheme(
          appState.uiFontId,
          scale: appState.uiFontScale,
        );

        return MaterialApp(
          title: 'JOOhub',
          debugShowCheckedModeBanner: false,
          theme: ThemeData.dark().copyWith(
            scaffoldBackgroundColor: kBg,
            visualDensity: VisualDensity.compact,
            textTheme: textTheme,
            primaryTextTheme: textTheme,
            colorScheme: ColorScheme.dark(
              primary: primary,
              secondary: secondary,
              surface: kSurface,
              error: kCoral,
            ),
            appBarTheme: AppBarTheme(
              backgroundColor: kSurface,
              elevation: 0,
              scrolledUnderElevation: 0,
              toolbarHeight: 48,
              titleTextStyle: textTheme.titleMedium?.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
            snackBarTheme: SnackBarThemeData(
              backgroundColor: kSurfaceAlt,
              contentTextStyle: textTheme.bodySmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: primary.withValues(alpha: 0.45)),
              ),
            ),
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: const Color(0xFF140800),
                minimumSize: const Size(0, 38),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding:
                    const EdgeInsets.symmetric(vertical: 9, horizontal: 13),
                textStyle: textTheme.labelMedium?.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 38),
                side: const BorderSide(color: kStroke),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding:
                    const EdgeInsets.symmetric(vertical: 9, horizontal: 13),
                textStyle: textTheme.labelMedium?.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: kSurfaceAlt,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
              labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: kStroke),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: kStroke),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: primary, width: 1.3),
              ),
            ),
          ),
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: child ?? const SizedBox.shrink(),
          ),
          home: const JooHubShellScreen(),
        );
      },
    );
  }
}

class JooHubShellScreen extends StatefulWidget {
  const JooHubShellScreen({super.key});
  @override
  State<JooHubShellScreen> createState() => _JooHubShellScreenState();
}

class _JooHubShellScreenState extends State<JooHubShellScreen>
    with WidgetsBindingObserver {
  int _tab = 0;
  int _homeReloadKey = 0;
  BgBuildStatus _bgStatus = BgBuildStatus.idle;
  Timer? _bgTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkBgStatus();
    _bgTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _checkBgStatus(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bgTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkBgStatus();
    }
  }

  Future<void> _checkBgStatus() async {
    final st = await BackgroundBuildService.getStatus();
    if (!mounted) return;
    if (st.isRunning != _bgStatus.isRunning ||
        st.statusText != _bgStatus.statusText ||
        st.progress != _bgStatus.progress ||
        st.lastApkUrl != _bgStatus.lastApkUrl) {
      setState(() => _bgStatus = st);
    }
  }

  void _refreshHome() {
    setState(() => _homeReloadKey++);
  }

  @override
  Widget build(BuildContext context) {
    final accent = appState.primaryColor;
    final pages = <Widget>[
      ProjectsHomeTab(
        key: ValueKey(_homeReloadKey),
        onSwitchTab: (i) => setState(() => _tab = i),
      ),
      AiStudioTab(
        onProjectChanged: _refreshHome,
        onSwitchTab: (i) => setState(() => _tab = i),
      ),
      ZipApkStudioTab(
        onProjectExtracted: _refreshHome,
      ),
      const GitHubCloudHubTab(),
      const ApexSettingsTab(),
    ];

    return Scaffold(
      body: Column(
        children: [
          if (_bgStatus.isRunning)
            SafeArea(
              bottom: false,
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  border: Border(
                    bottom: BorderSide(color: accent.withValues(alpha: 0.45)),
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        value: _bgStatus.progress >= 0
                            ? _bgStatus.progress / 100.0
                            : null,
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _bgStatus.statusText.isEmpty
                            ? 'جاري البناء في الخلفية...'
                            : _bgStatus.statusText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: accent,
                        ),
                      ),
                    ),
                    if (_bgStatus.lastApkUrl.isNotEmpty)
                      InkWell(
                        onTap: () => launchUrl(
                          Uri.parse(_bgStatus.lastApkUrl),
                          mode: LaunchMode.externalApplication,
                        ),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: Icon(Icons.download_rounded,
                              size: 16, color: kSuccess),
                        ),
                      ),
                    InkWell(
                      onTap: () async {
                        await BackgroundBuildService.stop();
                        await _checkBgStatus();
                      },
                      child: const Icon(Icons.close_rounded,
                          size: 16, color: Colors.white60),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(child: IndexedStack(index: _tab, children: pages)),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: kSurface,
          border: Border(top: BorderSide(color: kStroke, width: 1)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 54,
            child: Row(
              children: [
                _DockNavItem(
                  icon: Icons.folder_copy_outlined,
                  activeIcon: Icons.folder_copy_rounded,
                  label: 'مشاريعي',
                  selected: _tab == 0,
                  accent: accent,
                  onTap: () => setState(() => _tab = 0),
                ),
                _DockNavItem(
                  icon: Icons.auto_awesome_outlined,
                  activeIcon: Icons.auto_awesome_rounded,
                  label: 'الذكاء AI',
                  selected: _tab == 1,
                  accent: accent,
                  onTap: () => setState(() => _tab = 1),
                ),
                _DockNavItem(
                  icon: Icons.cloud_upload_outlined,
                  activeIcon: Icons.cloud_upload_rounded,
                  label: 'رفع و APK',
                  selected: _tab == 2,
                  accent: accent,
                  onTap: () => setState(() => _tab = 2),
                ),
                _DockNavItem(
                  icon: Icons.hub_outlined,
                  activeIcon: Icons.hub_rounded,
                  label: 'GitHub',
                  selected: _tab == 3,
                  accent: accent,
                  onTap: () => setState(() => _tab = 3),
                ),
                _DockNavItem(
                  icon: Icons.tune_outlined,
                  activeIcon: Icons.tune_rounded,
                  label: 'الإعدادات',
                  selected: _tab == 4,
                  accent: accent,
                  onTap: () => setState(() => _tab = 4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DockNavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _DockNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: selected ? 26 : 0,
              height: 2.5,
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Icon(
              selected ? activeIcon : icon,
              size: 19,
              color: selected ? accent : Colors.white54,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9.8,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? accent : Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}