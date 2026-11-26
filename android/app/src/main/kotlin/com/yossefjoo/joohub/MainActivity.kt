package com.yossefjoo.joohub

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.yossefjoo.joohub/bg_build"
        private const val REQ_NOTIF_PERM = 9055
    }

    private var pendingPermResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestNotificationPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            val granted = checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                                PackageManager.PERMISSION_GRANTED
                            if (granted) {
                                result.success(true)
                            } else {
                                pendingPermResult = result
                                requestPermissions(
                                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                    REQ_NOTIF_PERM
                                )
                            }
                        } else {
                            result.success(true)
                        }
                    }

                    "startUploadNotification" -> {
                        val title = call.argument<String>("title") ?: "JOOhub • جاري الرفع"
                        val subtitle = call.argument<String>("subtitle") ?: "جاري رفع الملفات..."
                        val progress = call.argument<Int>("progress") ?: -1
                        val indeterminate = call.argument<Boolean>("indeterminate") ?: true
                        val intent = Intent(this, BuildForegroundService::class.java).apply {
                            action = BuildForegroundService.ACTION_START_UPLOAD
                            putExtra("title", title)
                            putExtra("subtitle", subtitle)
                            putExtra("progress", progress)
                            putExtra("indeterminate", indeterminate)
                        }
                        startBgService(intent)
                        result.success(true)
                    }

                    "updateProgress" -> {
                        val title = call.argument<String>("title") ?: "JOOhub • جاري البناء"
                        val subtitle = call.argument<String>("subtitle") ?: ""
                        val progress = call.argument<Int>("progress") ?: -1
                        val indeterminate = call.argument<Boolean>("indeterminate") ?: (progress < 0)
                        val intent = Intent(this, BuildForegroundService::class.java).apply {
                            action = BuildForegroundService.ACTION_UPDATE_PROGRESS
                            putExtra("title", title)
                            putExtra("subtitle", subtitle)
                            putExtra("progress", progress)
                            putExtra("indeterminate", indeterminate)
                        }
                        startBgService(intent)
                        result.success(true)
                    }

                    "startBuildMonitor" -> {
                        val owner = call.argument<String>("owner") ?: ""
                        val repo = call.argument<String>("repo") ?: ""
                        val token = call.argument<String>("token") ?: ""
                        val appName = call.argument<String>("appName") ?: repo
                        val pollSeconds = call.argument<Int>("pollSeconds") ?: 10
                        val intent = Intent(this, BuildForegroundService::class.java).apply {
                            action = BuildForegroundService.ACTION_START_BUILD_MONITOR
                            putExtra("owner", owner)
                            putExtra("repo", repo)
                            putExtra("token", token)
                            putExtra("appName", appName)
                            putExtra("pollSeconds", pollSeconds)
                        }
                        startBgService(intent)
                        result.success(true)
                    }

                    "testAnimation" -> {
                        val intent = Intent(this, BuildForegroundService::class.java).apply {
                            action = BuildForegroundService.ACTION_TEST_ANIMATION
                        }
                        startBgService(intent)
                        result.success(true)
                    }

                    "stopService" -> {
                        val intent = Intent(this, BuildForegroundService::class.java).apply {
                            action = BuildForegroundService.ACTION_STOP
                        }
                        startService(intent)
                        result.success(true)
                    }

                    "getStatus" -> {
                        result.success(
                            mapOf(
                                "isRunning" to BuildForegroundService.isRunning,
                                "statusText" to BuildForegroundService.currentStatusText,
                                "repoFull" to BuildForegroundService.currentRepoFull,
                                "progress" to BuildForegroundService.currentProgress,
                                "lastApkUrl" to BuildForegroundService.lastApkUrl
                            )
                        )
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun startBgService(intent: Intent) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (_: Throwable) {}
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_NOTIF_PERM) {
            val ok = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermResult?.success(ok)
            pendingPermResult = null
        }
    }
}
