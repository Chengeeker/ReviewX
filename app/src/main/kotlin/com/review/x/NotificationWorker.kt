package com.review.x

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.os.Build
import androidx.work.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.CancellationException
import org.json.JSONArray
import java.util.concurrent.TimeUnit

class NotificationWorker(context:Context,parameters:WorkerParameters):CoroutineWorker(context,parameters) {
    override suspend fun doWork():Result=withContext(Dispatchers.IO) {
        try {
            val context=applicationContext
            var settings=AppSettings(context)
            if(!settings.bool("notification_enabled")) return@withContext Result.success()
            val manager=context.getSystemService(NotificationManager::class.java)
            if(!manager.areNotificationsEnabled() || (Build.VERSION.SDK_INT>=33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)!=PackageManager.PERMISSION_GRANTED)) return@withContext Result.success()
            val generation=context.getSharedPreferences("ReviewXWorker",0).getLong("generation",0)
            val vault=SessionVault(context); val session=vault.read() ?: return@withContext Result.success()
            AppNetwork.initialize(context)
            val page=ReaderRepository(context).notifications(session,null)
            settings=AppSettings(context)
            val current=vault.read()
            if(isStopped || !settings.bool("notification_enabled") || current?.cookie!=session.cookie || current.userId!=session.userId || generation!=context.getSharedPreferences("ReviewXWorker",0).getLong("generation",0)) return@withContext Result.success()
            val key="notification_seen_${session.userId}"; val raw=settings.string(key)
            val seen=runCatching { val array=JSONArray(raw); (0 until array.length()).map { array.getString(it) }.toSet() }.getOrDefault(emptySet())
            val pending=if(raw.isBlank()) emptyList() else page.notifications.filter { it.id !in seen && settings.bool("notification_${category(it)}",true) }.take(10)
            settings.set(key,JSONArray((page.notifications.map { it.id }+seen).distinct().take(500)).toString())
            if(Build.VERSION.SDK_INT>=26) manager.createNotificationChannel(NotificationChannel("x_activity","X 消息提醒",NotificationManager.IMPORTANCE_DEFAULT))
            for(item in pending) {
                if(isStopped || vault.read()?.cookie!=session.cookie || !settings.bool("notification_enabled") || generation!=context.getSharedPreferences("ReviewXWorker",0).getLong("generation",0)) break
                val intent=Intent(context,MainActivity::class.java).putExtra("open_notifications",true).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                val action=PendingIntent.getActivity(context,item.id.hashCode(),intent,PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
                val builder=if(Build.VERSION.SDK_INT>=26) Notification.Builder(context,"x_activity") else Notification.Builder(context)
                val message=item.message.ifBlank { item.posts.firstOrNull()?.text ?: "X 有新通知" }.take(240)
                manager.notify(item.id.hashCode(),builder.setSmallIcon(android.R.drawable.ic_dialog_info).setContentTitle("ReviewX").setContentText(message).setStyle(Notification.BigTextStyle().bigText(message)).setAutoCancel(true).setContentIntent(action).build())
            }
            Result.success()
        } catch(cancelled:CancellationException) { throw cancelled } catch(_:Exception) { Result.success() }
    }
    companion object {
        fun category(n:SocialNotification)=when { "heart" in n.icon->"likes";"retweet" in n.icon->"reposts";"person" in n.icon->"followers";n.posts.isNotEmpty()->"mentions";else->"other" }
        fun sync(context:Context,loggedIn:Boolean) {
            val prefs=context.getSharedPreferences("ReviewXWorker",0)
            prefs.edit().putLong("generation",prefs.getLong("generation",0)+1).apply()
            val manager=WorkManager.getInstance(context)
            if(!loggedIn || !AppSettings(context).bool("notification_enabled")) { manager.cancelUniqueWork("ReviewXNotifications"); context.getSystemService(NotificationManager::class.java).cancelAll(); return }
            manager.enqueueUniquePeriodicWork("ReviewXNotifications",ExistingPeriodicWorkPolicy.UPDATE,PeriodicWorkRequestBuilder<NotificationWorker>(15,TimeUnit.MINUTES).setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()).build())
        }
    }
}
