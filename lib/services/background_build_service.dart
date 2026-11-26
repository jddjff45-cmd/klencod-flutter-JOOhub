import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// ============================================================================
// JOOhub — BACKGROUND BUILD & ANIMATED NOTIFICATION SERVICE
// Bridges Flutter to native Android BuildForegroundService (dataSync)
// Keeps tracking GitHub Actions builds & showing animated "جاري البناء"
// even when the app is closed or swiped away.
// ============================================================================

class BgBuildStatus {
  final bool isRunning;
  final String statusText;
  final String repoFull;
  final int progress;
  final String lastApkUrl;

  const BgBuildStatus({
    required this.isRunning,
    required this.statusText,
    required this.repoFull,
    required this.progress,
    required this.lastApkUrl,
  });

  static const BgBuildStatus idle = BgBuildStatus(
    isRunning: false,
    statusText: '',
    repoFull: '',
    progress: -1,
    lastApkUrl: '',
  );
}

class BackgroundBuildService {
  static const MethodChannel _ch = MethodChannel('com.yossefjoo.joohub/bg_build');

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  static Future<bool> requestNotificationPermission() async {
    if (!_supported) return true;
    try {
      final ok = await _ch.invokeMethod<bool>('requestNotificationPermission');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> startUploadNotification({
    required String title,
    required String subtitle,
    int progress = -1,
    bool indeterminate = true,
  }) async {
    if (!_supported) return;
    try {
      await requestNotificationPermission();
      await _ch.invokeMethod('startUploadNotification', {
        'title': title,
        'subtitle': subtitle,
        'progress': progress,
        'indeterminate': indeterminate,
      });
    } catch (_) {}
  }

  static Future<void> updateProgress({
    required String title,
    required String subtitle,
    int progress = -1,
    bool indeterminate = false,
  }) async {
    if (!_supported) return;
    try {
      await _ch.invokeMethod('updateProgress', {
        'title': title,
        'subtitle': subtitle,
        'progress': progress,
        'indeterminate': indeterminate || progress < 0,
      });
    } catch (_) {}
  }

  static Future<void> startCloudBuildMonitor({
    required String owner,
    required String repo,
    required String token,
    required String appName,
    int pollSeconds = 10,
  }) async {
    if (!_supported) return;
    try {
      await requestNotificationPermission();
      await _ch.invokeMethod('startBuildMonitor', {
        'owner': owner,
        'repo': repo,
        'token': token,
        'appName': appName,
        'pollSeconds': pollSeconds,
      });
    } catch (_) {}
  }

  static Future<void> testAnimatedNotification() async {
    if (!_supported) return;
    try {
      await requestNotificationPermission();
      await _ch.invokeMethod('testAnimation');
    } catch (_) {}
  }

  static Future<void> stop() async {
    if (!_supported) return;
    try {
      await _ch.invokeMethod('stopService');
    } catch (_) {}
  }

  static Future<BgBuildStatus> getStatus() async {
    if (!_supported) return BgBuildStatus.idle;
    try {
      final res = await _ch.invokeMapMethod<String, dynamic>('getStatus');
      if (res == null) return BgBuildStatus.idle;
      return BgBuildStatus(
        isRunning: res['isRunning'] == true,
        statusText: (res['statusText'] ?? '').toString(),
        repoFull: (res['repoFull'] ?? '').toString(),
        progress: (res['progress'] as num?)?.toInt() ?? -1,
        lastApkUrl: (res['lastApkUrl'] ?? '').toString(),
      );
    } catch (_) {
      return BgBuildStatus.idle;
    }
  }
}
