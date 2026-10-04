package com.review.x

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/** Executes the shared Dart X adapter, without duplicating or exporting session credentials. */
class NotificationWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result = withContext(Dispatchers.Main) {
        val prefs = applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        if (!prefs.getBoolean("flutter.notification_enabled", false)) return@withContext Result.success()
        val manager = applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (!manager.areNotificationsEnabled()) return@withContext Result.success()
        if (Build.VERSION.SDK_INT >= 33 && applicationContext.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return@withContext Result.success()
        val generation = applicationContext.getSharedPreferences("ReviewXWorker", Context.MODE_PRIVATE).getLong("generation", 0)
        val completed = CompletableDeferred<List<Map<String, Any?>>>()
        val engine = FlutterEngine(applicationContext)
        NetworkRouting.register(engine, applicationContext)
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "com.review.x/notifications")
        try {
            channel.setMethodCallHandler { call, result ->
                if (call.method == "pollComplete") {
                    val items = (call.arguments as? List<*>)?.mapNotNull { item ->
                        (item as? Map<*, *>)?.let { mapOf("id" to it["id"], "message" to it["message"]) }
                    } ?: emptyList()
                    completed.complete(items)
                    result.success(true)
                } else result.notImplemented()
            }
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(applicationContext)
            loader.ensureInitializationComplete(applicationContext, null)
            engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "notificationWorkerMain"))
            val items = withTimeoutOrNull(90000) { completed.await() } ?: emptyList()
            if (!isStopped && prefs.getBoolean("flutter.notification_enabled", false) &&
                generation == applicationContext.getSharedPreferences("ReviewXWorker", Context.MODE_PRIVATE).getLong("generation", 0)) {
                if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel("x_activity", "X 消息提醒", NotificationManager.IMPORTANCE_DEFAULT))
                for (item in items.take(10)) {
                    val id = (item["id"] as? String)?.hashCode() ?: continue
                    val intent = Intent(applicationContext, MainActivity::class.java).putExtra("open_notifications", true)
                        .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    val action = PendingIntent.getActivity(applicationContext, id, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
                    val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(applicationContext, "x_activity") else Notification.Builder(applicationContext)
                    val message = (item["message"] as? String)?.take(240) ?: "X 有新通知"
                    manager.notify(id, builder.setSmallIcon(android.R.drawable.ic_dialog_info).setContentTitle("ReviewX")
                        .setContentText(message).setStyle(Notification.BigTextStyle().bigText(message)).setAutoCancel(true)
                        .setContentIntent(action).build())
                }
            }
            Result.success()
        } catch (_: Exception) { Result.success() }
        finally { channel.setMethodCallHandler(null); engine.destroy() }
    }
}
