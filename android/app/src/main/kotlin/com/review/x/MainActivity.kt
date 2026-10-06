package com.review.x

import android.content.res.Configuration
import android.os.Build
import android.Manifest
import android.content.ContentValues
import android.content.Intent
import android.app.Activity
import android.app.NotificationManager
import androidx.work.WorkManager
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.Constraints
import androidx.work.NetworkType
import java.util.concurrent.TimeUnit
import android.content.pm.PackageManager
import android.os.Environment
import android.provider.MediaStore
import android.media.MediaScannerConnection
import android.provider.Settings
import java.io.File
import java.util.concurrent.Executors
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var themeChannel: MethodChannel? = null
    private val mediaExecutor = Executors.newSingleThreadExecutor()
    private var pendingSave: Pair<Map<String, String>, MethodChannel.Result>? = null
    private var notificationChannel: MethodChannel? = null
    private var deepLinkChannel: MethodChannel? = null
    private var xAuthChannel: MethodChannel? = null
    private var pendingXAuthResult: MethodChannel.Result? = null
    private var pendingDeepLink: String? = null
    private var pendingPermission: MethodChannel.Result? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        NetworkRouting.register(flutterEngine, applicationContext)
        pendingDeepLink = intent?.dataString
        deepLinkChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.review.x/deep_links")
        deepLinkChannel!!.setMethodCallHandler { call, result ->
            if (call.method == "consumeInitialLink") {
                val link = pendingDeepLink
                pendingDeepLink = null
                result.success(link)
            } else result.notImplemented()
        }
        xAuthChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.review.x/x_auth")
        XLoginActivity.candidateValidator = { cookies, reply ->
            xAuthChannel?.invokeMethod("validateCandidate", cookies, object : MethodChannel.Result {
                override fun success(result: Any?) = reply(result == true)
                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) = reply(false)
                override fun notImplemented() = reply(false)
            }) ?: reply(false)
        }
        xAuthChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "startLogin" -> {
                    if (pendingXAuthResult != null) {
                        result.error("BUSY", "登录流程正在进行", null)
                    } else {
                        XLoginDiagnostics.begin(this)
                        XLoginDiagnostics.record(this, "activity.launch_requested")
                        pendingXAuthResult = result
                        try {
                            startActivityForResult(
                                Intent(this, XLoginActivity::class.java), X_LOGIN_REQUEST)
                        } catch (_: Exception) {
                            XLoginDiagnostics.record(this, "activity.launch_failed")
                            pendingXAuthResult = null
                            result.error("UNAVAILABLE", "无法打开 X 登录页面", null)
                        }
                    }
                }
                "getLoginDiagnostics" -> result.success(XLoginDiagnostics.read(this))
                "recordFlutterLifecycle" -> {
                    val state = call.arguments as? String
                    if (pendingXAuthResult != null && state != null && state in FLUTTER_LIFECYCLE_STATES) {
                        XLoginDiagnostics.record(this, "flutter.app_$state")
                        result.success(true)
                    } else result.success(false)
                }
                "validateCandidate" -> {
                    val supplied = call.arguments as? Map<*, *>
                    val cookies = mutableMapOf<String, String>()
                    supplied?.forEach { (key, value) ->
                        if (key is String && value is String && key in SESSION_COOKIE_NAMES) {
                            cookies[key] = value
                        }
                    }
                    if (cookies["auth_token"].isNullOrEmpty() || cookies["ct0"].isNullOrEmpty()) {
                        result.success(false)
                    } else {
                        XLoginActivity.validateCandidate(cookies, result)
                    }
                }
                else -> result.notImplemented()
            }
        }
        notificationChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.review.x/notifications")
        notificationChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "consumeOpenNotifications" -> {
                    val open = intent.getBooleanExtra("open_notifications", false)
                    intent.removeExtra("open_notifications")
                    result.success(open)
                }
                "requestPermission" -> {
                    if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        if (pendingPermission != null) result.error("BUSY", "权限请求正在进行", null)
                        else { pendingPermission = result; requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 713) }
                    } else result.success((getSystemService(NOTIFICATION_SERVICE) as NotificationManager).areNotificationsEnabled())
                }
                "sync" -> {
                    val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                    val active = prefs.getBoolean("flutter.notification_enabled", false) && call.argument<Boolean>("loggedIn") == true
                    val generations = getSharedPreferences("ReviewXWorker", MODE_PRIVATE)
                    generations.edit().putLong("generation", generations.getLong("generation", 0) + 1).apply()
                    val worker = WorkManager.getInstance(applicationContext)
                    if (active) worker.enqueueUniquePeriodicWork("ReviewXNotifications", ExistingPeriodicWorkPolicy.UPDATE,
                        PeriodicWorkRequestBuilder<NotificationWorker>(15, TimeUnit.MINUTES)
                            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()).build())
                    else { worker.cancelUniqueWork("ReviewXNotifications"); (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).cancelAll() }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.review.x/media")
            .setMethodCallHandler { call, result ->
                // Adapted from Review's player controls; brightness affects this window only.
                when (call.method) {
                    "getPlayerLevels" -> {
                        val original = window.attributes.screenBrightness
                        val brightness = if (original >= 0) original else
                            Settings.System.getInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS, 128) / 255f
                        result.success(mapOf("windowBrightness" to original.toDouble(),
                            "brightness" to brightness.coerceIn(0.01f, 1f).toDouble()))
                        return@setMethodCallHandler
                    }
                    "setBrightness", "restorePlayerBrightness" -> {
                        val value = call.argument<Double>("brightness") ?: -1.0
                        val attributes = window.attributes
                        attributes.screenBrightness = if (call.method == "restorePlayerBrightness" && value < 0) -1f
                            else value.toFloat().coerceIn(0.01f, 1f)
                        window.attributes = attributes
                        result.success(true)
                        return@setMethodCallHandler
                    }
                    "shareText" -> {
                        val text = call.argument<String>("text") ?: ""
                        if (text.isBlank()) result.error("EMPTY", "分享内容为空", null)
                        else {
                            val share = Intent(Intent.ACTION_SEND).apply {
                                type = "text/plain"
                                putExtra(Intent.EXTRA_TEXT, text)
                            }
                            startActivity(Intent.createChooser(share, call.argument<String>("title") ?: "分享"))
                            result.success(true)
                        }
                        return@setMethodCallHandler
                    }
                }
                if (call.method != "saveMedia") { result.notImplemented(); return@setMethodCallHandler }
                val args = mapOf("path" to (call.argument<String>("path") ?: ""), "name" to (call.argument<String>("name") ?: ""),
                    "mime" to (call.argument<String>("mime") ?: ""), "folder" to (call.argument<String>("folder") ?: ""))
                if (pendingSave != null) { result.error("BUSY", "保存正在进行", null); return@setMethodCallHandler }
                if (Build.VERSION.SDK_INT < 29 && checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
                    pendingSave = Pair(args, result)
                    requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), 712)
                } else saveMedia(args, result)
            }
        themeChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.review.x/theme")
        themeChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "getFontWeightAdjustment" -> result.success(fontWeightAdjustment(resources.configuration))
                "getDisplayModes" -> result.success(windowManager.defaultDisplay.supportedModes.map { mapOf("id" to it.modeId,
                    "width" to it.physicalWidth, "height" to it.physicalHeight, "rate" to it.refreshRate.toDouble()) })
                "setScreenRefreshRateMode" -> {
                    val mode = call.argument<Int>("mode") ?: 0
                    val attributes = window.attributes
                    if (mode == 0) { attributes.preferredDisplayModeId = 0; attributes.preferredRefreshRate = 0f }
                    else {
                        val actual = windowManager.defaultDisplay.supportedModes.find { it.modeId == mode }
                        if (actual == null) { result.error("UNSUPPORTED", "不支持的屏幕模式", null); return@setMethodCallHandler }
                        attributes.preferredDisplayModeId = actual.modeId
                        attributes.preferredRefreshRate = actual.refreshRate
                    }
                    window.attributes = attributes
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 712) {
            val pending = pendingSave
            pendingSave = null
            if (pending != null) {
                if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) saveMedia(pending.first, pending.second)
                else pending.second.error("PERMISSION", "没有授予相册保存权限", null)
            }
        }
        if (requestCode == 713) {
            pendingPermission?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
            pendingPermission = null
        }
    }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val deepLink = intent.dataString
        if (deepLink != null) {
            pendingDeepLink = deepLink
            deepLinkChannel?.invokeMethod("openLink", deepLink, object : MethodChannel.Result {
                override fun success(result: Any?) {
                    if (result == true && pendingDeepLink == deepLink) pendingDeepLink = null
                }
                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) = Unit
                override fun notImplemented() = Unit
            })
        }
        if (intent.getBooleanExtra("open_notifications", false)) {
            intent.removeExtra("open_notifications")
            notificationChannel?.invokeMethod("openNotifications", null)
        }
    }
    @Deprecated("Deprecated in Android, retained for FlutterActivity result compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == X_LOGIN_REQUEST) {
            XLoginDiagnostics.record(this, "activity.result", code = if (resultCode == Activity.RESULT_OK) 1 else 0)
            XLoginDiagnostics.record(this, "activity.result_reason", code = data?.getIntExtra(XLoginActivity.EXTRA_EXIT_REASON, -1) ?: -1)
            val result = pendingXAuthResult
            pendingXAuthResult = null
            result?.success(resultCode == Activity.RESULT_OK)
        }
    }

    override fun onPause() {
        super.onPause()
        if (pendingXAuthResult != null) XLoginDiagnostics.record(this, "main.activity_pause")
    }

    override fun onResume() {
        super.onResume()
        if (pendingXAuthResult != null) XLoginDiagnostics.record(this, "main.activity_resume")
    }
    private fun saveMedia(args: Map<String, String>, result: MethodChannel.Result) {
        mediaExecutor.execute {
            try {
                val source = File(args.getValue("path")).canonicalFile
                require(source.path.startsWith(cacheDir.canonicalPath + File.separator) && source.isFile)
                val name = args.getValue("name")
                require(Regex("Review_X_[0-9]+\\.(jpg|png|webp|mp4)").matches(name))
                val mime = args.getValue("mime")
                require(mime in listOf("image/jpeg", "image/png", "image/webp", "video/mp4"))
                val folder = args.getValue("folder")
                require(folder.length <= 80 && Regex("[A-Za-z0-9_\\-]*").matches(folder))
                val video = mime.startsWith("video/")
                val base = if (video) Environment.DIRECTORY_MOVIES else Environment.DIRECTORY_PICTURES
                val relative = "$base/ReviewX" + if (folder.isEmpty()) "" else "/$folder"
                if (Build.VERSION.SDK_INT >= 29) {
                    val collection = if (video) MediaStore.Video.Media.EXTERNAL_CONTENT_URI else MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                    val values = ContentValues().apply {
                        put(MediaStore.MediaColumns.DISPLAY_NAME, name); put(MediaStore.MediaColumns.MIME_TYPE, mime)
                        put(MediaStore.MediaColumns.RELATIVE_PATH, relative); put(MediaStore.MediaColumns.IS_PENDING, 1)
                    }
                    val uri = contentResolver.insert(collection, values) ?: error("相册创建失败")
                    try {
                        contentResolver.openOutputStream(uri)?.use { out -> source.inputStream().use { it.copyTo(out) } } ?: error("相册写入失败")
                        contentResolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
                    } catch (error: Exception) { contentResolver.delete(uri, null, null); throw error }
                } else {
                    val directory = File(Environment.getExternalStoragePublicDirectory(base), "ReviewX" + if (folder.isEmpty()) "" else "/$folder")
                    require(directory.exists() || directory.mkdirs())
                    val destination = File(directory, name)
                    try { source.copyTo(destination, overwrite = false) }
                    catch (error: Exception) { destination.delete(); throw error }
                    MediaScannerConnection.scanFile(this, arrayOf(destination.path), arrayOf(mime), null)
                }
                runOnUiThread { result.success(true) }
            } catch (_: Exception) { runOnUiThread { result.error("SAVE_FAILED", "保存到相册失败", null) } }
        }
    }
    private fun fontWeightAdjustment(config: Configuration): Int =
        if (Build.VERSION.SDK_INT >= 31 && config.fontWeightAdjustment != Configuration.FONT_WEIGHT_ADJUSTMENT_UNDEFINED)
            config.fontWeightAdjustment else 0
    override fun onDestroy() {
        if (pendingXAuthResult != null) XLoginDiagnostics.record(this, "main.activity_destroy")
        XLoginActivity.candidateValidator = null
        mediaExecutor.shutdown()
        super.onDestroy()
    }
    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        themeChannel?.invokeMethod("onFontWeightAdjustmentChanged", fontWeightAdjustment(newConfig))
    }

    private companion object {
        const val X_LOGIN_REQUEST = 721
        val SESSION_COOKIE_NAMES = setOf("auth_token", "ct0", "twid", "gt")
        val FLUTTER_LIFECYCLE_STATES = setOf("resumed", "inactive", "hidden", "paused", "detached")
    }
}
