package com.yossefjoo.joohub

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.atomic.AtomicBoolean

class BuildForegroundService : Service() {

    companion object {
        const val CHANNEL_ID_ONGOING = "joohub_bg_build_ongoing"
        const val CHANNEL_ID_RESULT = "joohub_bg_build_result"
        const val NOTIF_ID_ONGOING = 9001
        const val NOTIF_ID_RESULT = 9002

        const val ACTION_START_UPLOAD = "com.yossefjoo.joohub.START_UPLOAD"
        const val ACTION_UPDATE_PROGRESS = "com.yossefjoo.joohub.UPDATE_PROGRESS"
        const val ACTION_START_BUILD_MONITOR = "com.yossefjoo.joohub.START_BUILD_MONITOR"
        const val ACTION_TEST_ANIMATION = "com.yossefjoo.joohub.TEST_ANIMATION"
        const val ACTION_STOP = "com.yossefjoo.joohub.STOP_BUILD"

        @Volatile
        var isRunning: Boolean = false
        @Volatile
        var currentStatusText: String = ""
        @Volatile
        var currentRepoFull: String = ""
        @Volatile
        var currentProgress: Int = -1
        @Volatile
        var lastApkUrl: String = ""
    }

    private val monitoring = AtomicBoolean(false)
    private val animating = AtomicBoolean(false)
    private var monitorThread: Thread? = null
    private var animThread: Thread? = null
    private var wakeLock: PowerManager.WakeLock? = null

    private var activeTitle = "JOOhub • جاري البناء"
    private var activeSubtitle = "جاري تجهيز البناء في الخلفية..."
    private var activeProgress = -1
    private var activeIndeterminate = true
    private var startTimeMs = 0L

    private val spinnerFrames = arrayOf("⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏")
    private var frameIdx = 0

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "JOOhub::BgBuildLock")
            wakeLock?.setReferenceCounted(false)
        } catch (_: Throwable) {}
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_START_UPLOAD

        if (action == ACTION_STOP) {
            stopAllAndSelf()
            return START_NOT_STICKY
        }

        if (startTimeMs == 0L) {
            startTimeMs = System.currentTimeMillis()
        }
        isRunning = true
        try {
            if (wakeLock?.isHeld != true) {
                wakeLock?.acquire(45 * 60 * 1000L) // up to 45 min
            }
        } catch (_: Throwable) {}

        when (action) {
            ACTION_START_UPLOAD -> {
                activeTitle = intent?.getStringExtra("title") ?: "JOOhub • جاري الرفع والبناء"
                activeSubtitle = intent?.getStringExtra("subtitle") ?: "جاري رفع الملفات في الخلفية..."
                activeProgress = intent?.getIntExtra("progress", -1) ?: -1
                activeIndeterminate = intent?.getBooleanExtra("indeterminate", true) ?: true
                currentStatusText = activeSubtitle
                currentProgress = activeProgress
                startForegroundCompat(buildOngoingNotification())
                startSpinnerAnimator()
            }

            ACTION_UPDATE_PROGRESS -> {
                activeTitle = intent?.getStringExtra("title") ?: activeTitle
                activeSubtitle = intent?.getStringExtra("subtitle") ?: activeSubtitle
                activeProgress = intent?.getIntExtra("progress", activeProgress) ?: activeProgress
                activeIndeterminate = intent?.getBooleanExtra("indeterminate", activeProgress < 0) ?: (activeProgress < 0)
                currentStatusText = activeSubtitle
                currentProgress = activeProgress
                if (!isRunning) {
                    startForegroundCompat(buildOngoingNotification())
                } else {
                    notifyOngoing()
                }
            }

            ACTION_START_BUILD_MONITOR -> {
                val owner = intent?.getStringExtra("owner") ?: ""
                val repo = intent?.getStringExtra("repo") ?: ""
                val token = intent?.getStringExtra("token") ?: ""
                val appName = intent?.getStringExtra("appName") ?: repo
                val pollSeconds = (intent?.getIntExtra("pollSeconds", 10) ?: 10).coerceIn(5, 30)

                currentRepoFull = "$owner/$repo"
                lastApkUrl = ""
                activeTitle = "جاري البناء • $appName"
                activeSubtitle = "متصل بـ GitHub Actions • يعمل حتى عند إغلاق التطبيق"
                activeProgress = -1
                activeIndeterminate = true
                currentStatusText = activeSubtitle
                currentProgress = -1

                startForegroundCompat(buildOngoingNotification())
                startSpinnerAnimator()
                if (owner.isNotEmpty() && repo.isNotEmpty() && token.isNotEmpty()) {
                    startGitHubBuildMonitor(owner, repo, token, appName, pollSeconds)
                }
            }

            ACTION_TEST_ANIMATION -> {
                activeTitle = "جاري البناء • اختبار JOOhub"
                activeSubtitle = "إشعار متحرك يعمل في الخلفية بنجاح..."
                activeProgress = -1
                activeIndeterminate = true
                currentStatusText = activeSubtitle
                startForegroundCompat(buildOngoingNotification())
                startSpinnerAnimator()
                Thread {
                    try {
                        for (i in 1..10) {
                            Thread.sleep(1000)
                            if (!isRunning) return@Thread
                            activeSubtitle = "اختبار البناء في الخلفية (${i * 10}%)..."
                            activeProgress = i * 10
                            activeIndeterminate = false
                            currentStatusText = activeSubtitle
                            currentProgress = activeProgress
                            notifyOngoing()
                        }
                        postResultNotification(
                            title = "✅ اختبار الإشعار المتحرك نجح!",
                            body = "نظام البناء في الخلفية جاهز ويعمل حتى عند إغلاق JOOhub.",
                            downloadUrl = null
                        )
                    } catch (_: Throwable) {
                    } finally {
                        stopAllAndSelf()
                    }
                }.start()
            }
        }

        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // Keep running even when user swipes JOOhub away from recents!
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        stopThreads()
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (_: Throwable) {}
        isRunning = false
        super.onDestroy()
    }

    private fun stopThreads() {
        monitoring.set(false)
        animating.set(false)
        monitorThread?.interrupt()
        animThread?.interrupt()
        monitorThread = null
        animThread = null
    }

    private fun stopAllAndSelf() {
        stopThreads()
        isRunning = false
        currentStatusText = ""
        currentProgress = -1
        startTimeMs = 0L
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (_: Throwable) {}
        stopSelf()
    }

    private fun startForegroundCompat(notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIF_ID_ONGOING,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            )
        } else {
            startForeground(NOTIF_ID_ONGOING, notification)
        }
    }

    private fun startSpinnerAnimator() {
        if (animating.getAndSet(true)) return
        animThread = Thread {
            while (animating.get() && isRunning) {
                try {
                    Thread.sleep(1500)
                    frameIdx = (frameIdx + 1) % spinnerFrames.size
                    notifyOngoing()
                } catch (_: InterruptedException) {
                    break
                } catch (_: Throwable) {}
            }
        }.apply {
            isDaemon = true
            start()
        }
    }

    private fun formatElapsed(): String {
        if (startTimeMs <= 0L) return "00:00"
        val secs = ((System.currentTimeMillis() - startTimeMs) / 1000L).coerceAtLeast(0L)
        val m = secs / 60
        val s = secs % 60
        return String.format("%02d:%02d", m, s)
    }

    private fun notifyOngoing() {
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.notify(NOTIF_ID_ONGOING, buildOngoingNotification())
        } catch (_: Throwable) {}
    }

    private fun buildOngoingNotification(): Notification {
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val openPending = PendingIntent.getActivity(
            this,
            101,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val stopIntent = Intent(this, BuildForegroundService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPending = PendingIntent.getService(
            this,
            102,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val frame = spinnerFrames[frameIdx % spinnerFrames.size]
        val elapsed = formatElapsed()
        val displayTitle = "$frame $activeTitle ($elapsed)"

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID_ONGOING)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        builder
            .setSmallIcon(R.drawable.ic_joohub_v7)
            .setContentTitle(displayTitle)
            .setContentText(activeSubtitle)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(openPending)
            .addAction(
                Notification.Action.Builder(
                    null,
                    "إيقاف المتابعة",
                    stopPending
                ).build()
            )

        if (activeIndeterminate || activeProgress < 0) {
            builder.setProgress(0, 0, true)
        } else {
            builder.setProgress(100, activeProgress.coerceIn(0, 100), false)
        }

        return builder.build()
    }

    private fun postResultNotification(title: String, body: String, downloadUrl: String?) {
        try {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val tapIntent = if (!downloadUrl.isNullOrEmpty()) {
                Intent(Intent.ACTION_VIEW, Uri.parse(downloadUrl))
            } else {
                Intent(this, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
            }
            val tapPending = PendingIntent.getActivity(
                this,
                201,
                tapIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, CHANNEL_ID_RESULT)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }

            builder
                .setSmallIcon(R.drawable.ic_joohub_v7)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(Notification.BigTextStyle().bigText(body))
                .setAutoCancel(true)
                .setContentIntent(tapPending)

            nm.notify(NOTIF_ID_RESULT, builder.build())
        } catch (_: Throwable) {}
    }

    private fun startGitHubBuildMonitor(
        owner: String,
        repo: String,
        token: String,
        appName: String,
        pollSeconds: Int
    ) {
        monitoring.set(false)
        monitorThread?.interrupt()
        monitoring.set(true)

        monitorThread = Thread {
            var attempts = 0
            val maxAttempts = 180 // ~30 minutes
            while (monitoring.get() && attempts < maxAttempts) {
                attempts++
                try {
                    val runsJson = githubGet(
                        "https://api.github.com/repos/$owner/$repo/actions/runs?per_page=1",
                        token
                    )
                    if (runsJson != null) {
                        val arr = runsJson.optJSONArray("workflow_runs")
                        if (arr != null && arr.length() > 0) {
                            val run = arr.getJSONObject(0)
                            val runId = run.optLong("id", 0L)
                            val status = run.optString("status", "")
                            val conclusion = run.optString("conclusion", "")
                            val htmlUrl = run.optString("html_url", "")

                            if (status == "completed") {
                                if (conclusion == "success") {
                                    val apkUrl = fetchLatestApkUrl(owner, repo, token)
                                    lastApkUrl = apkUrl ?: htmlUrl
                                    postResultNotification(
                                        title = "✅ اكتمل بناء APK • $appName",
                                        body = if (apkUrl != null)
                                            "ملف APK جاهز الآن للتحميل المباشر! اضغط للتحميل."
                                        else
                                            "اكتمل البناء بنجاح على $owner/$repo. اضغط لفتح النتيجة.",
                                        downloadUrl = apkUrl ?: htmlUrl
                                    )
                                } else {
                                    postResultNotification(
                                        title = "❌ فشل بناء APK • $appName",
                                        body = "الحالة: $conclusion على $owner/$repo. اضغط لمراجعة سجل البناء.",
                                        downloadUrl = htmlUrl.ifEmpty { null }
                                    )
                                }
                                stopAllAndSelf()
                                return@Thread
                            } else {
                                // Still queued or in_progress — try to fetch active step name!
                                var stepText = if (status == "queued") {
                                    "في قائمة الانتظار على خوادم البناء..."
                                } else {
                                    "جاري البناء السحابي على GitHub Actions..."
                                }
                                var computedPct = -1

                                if (runId > 0L) {
                                    val jobsJson = githubGet(
                                        "https://api.github.com/repos/$owner/$repo/actions/runs/$runId/jobs",
                                        token
                                    )
                                    val jobs = jobsJson?.optJSONArray("jobs")
                                    if (jobs != null && jobs.length() > 0) {
                                        val steps = jobs.getJSONObject(0).optJSONArray("steps")
                                        if (steps != null && steps.length() > 0) {
                                            var doneCount = 0
                                            var activeStepName = ""
                                            for (i in 0 until steps.length()) {
                                                val st = steps.getJSONObject(i)
                                                val sStatus = st.optString("status", "")
                                                if (sStatus == "completed") {
                                                    doneCount++
                                                } else if (sStatus == "in_progress" && activeStepName.isEmpty()) {
                                                    activeStepName = st.optString("name", "")
                                                }
                                            }
                                            computedPct = ((doneCount * 100) / steps.length()).coerceIn(5, 95)
                                            if (activeStepName.isNotEmpty()) {
                                                stepText = "جاري: $activeStepName ($computedPct%)"
                                            }
                                        }
                                    }
                                }

                                activeTitle = "جاري البناء • $appName"
                                activeSubtitle = stepText
                                activeProgress = computedPct
                                activeIndeterminate = computedPct < 0
                                currentStatusText = stepText
                                currentProgress = computedPct
                                notifyOngoing()
                            }
                        }
                    }
                    Thread.sleep(pollSeconds * 1000L)
                } catch (_: InterruptedException) {
                    break
                } catch (_: Throwable) {
                    try {
                        Thread.sleep(pollSeconds * 1000L)
                    } catch (_: InterruptedException) {
                        break
                    }
                }
            }
            if (monitoring.get()) {
                stopAllAndSelf()
            }
        }.apply {
            isDaemon = true
            start()
        }
    }

    private fun fetchLatestApkUrl(owner: String, repo: String, token: String): String? {
        val releases = githubGetArray("https://api.github.com/repos/$owner/$repo/releases?per_page=3", token)
            ?: return null
        for (i in 0 until releases.length()) {
            val rel = releases.optJSONObject(i) ?: continue
            val assets = rel.optJSONArray("assets") ?: continue
            for (j in 0 until assets.length()) {
                val a = assets.optJSONObject(j) ?: continue
                val name = a.optString("name", "").lowercase()
                if (name.endsWith(".apk") || name.endsWith(".aab")) {
                    val dl = a.optString("browser_download_url", "")
                    if (dl.isNotEmpty()) return dl
                }
            }
        }
        return null
    }

    private fun githubGet(urlStr: String, token: String): JSONObject? {
        val raw = githubGetRaw(urlStr, token) ?: return null
        return try { JSONObject(raw) } catch (_: Throwable) { null }
    }

    private fun githubGetArray(urlStr: String, token: String): org.json.JSONArray? {
        val raw = githubGetRaw(urlStr, token) ?: return null
        return try { org.json.JSONArray(raw) } catch (_: Throwable) { null }
    }

    private fun githubGetRaw(urlStr: String, token: String): String? {
        var conn: HttpURLConnection? = null
        return try {
            conn = (URL(urlStr).openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = 15000
                readTimeout = 15000
                setRequestProperty("Authorization", "Bearer $token")
                setRequestProperty("Accept", "application/vnd.github+json")
                setRequestProperty("User-Agent", "JOOhub/9.0")
            }
            if (conn.responseCode in 200..299) {
                BufferedReader(InputStreamReader(conn.inputStream)).use { it.readText() }
            } else null
        } catch (_: Throwable) {
            null
        } finally {
            conn?.disconnect()
        }
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            val ongoingChannel = NotificationChannel(
                CHANNEL_ID_ONGOING,
                "جاري البناء في الخلفية",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "يعرض حالة بناء APK المتحركة في الخلفية حتى عند إغلاق JOOhub"
                setShowBadge(false)
            }
            nm.createNotificationChannel(ongoingChannel)

            val resultChannel = NotificationChannel(
                CHANNEL_ID_RESULT,
                "نتائج بناء APK",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "إشعار فوري عند اكتمال أو فشل بناء التطبيق"
                enableVibration(true)
            }
            nm.createNotificationChannel(resultChannel)
        }
    }
}
