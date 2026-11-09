package com.review.x

import android.content.Context
import android.os.Build
import android.util.AtomicFile
import java.io.File
import org.json.JSONArray
import org.json.JSONObject

object DiagnosticLog {
    private var destination:AtomicFile?=null
    private val entries=ArrayDeque<JSONObject>()
    private val writer = java.util.concurrent.Executors.newSingleThreadExecutor { task ->
        Thread(task, "reviewx-diagnostics").apply { isDaemon = true }
    }
    private val writeLock = Any()
    private var pendingWrite: Pair<AtomicFile, ByteArray>? = null
    private var writing = false
    private fun persist(file: AtomicFile, bytes: ByteArray) {
        runCatching {
            val stream = file.startWrite()
            try { stream.write(bytes); file.finishWrite(stream) }
            catch (error: Exception) { file.failWrite(stream) }
        }
    }
    @Synchronized fun initialize(context:Context) {
        if(destination!=null)return
        destination=AtomicFile(File(context.noBackupFilesDir,"compose-diagnostics-v1.json"))
        runCatching { val data=destination!!.openRead().bufferedReader().use {it.readText()};if(data.length<256*1024)JSONArray(data).objects().takeLast(300).forEach(entries::addLast) }
        val previous=Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread,error -> record("crash",error=error);previous?.uncaughtException(thread,error) }
    }
    @Synchronized fun record(event:String,status:Int?=null,duration:Long?=null,error:Throwable?=null) {
        val item=JSONObject().put("time",java.time.Instant.now().toString()).put("event",event.replace(Regex("[^A-Za-z0-9_.-]"),"_").take(80))
        status?.let {item.put("status",it)};duration?.let {item.put("duration_ms",it)}
        error?.let {item.put("type",it.javaClass.simpleName);item.put("location",JSONArray(it.stackTrace.filter {frame->frame.className.startsWith("com.review.x.")}.take(5).map {frame->"${frame.className.substringAfterLast('.')}.${frame.methodName}:${frame.lineNumber}"}))}
        entries.addLast(item);while(entries.size>300)entries.removeFirst()
        val file=destination ?: return
        val bytes = JSONArray(entries.toList()).toString().toByteArray()
        if (error != null) {
            runCatching { writer.submit { persist(file, bytes) }.get() }
        } else synchronized(writeLock) {
            pendingWrite = file to bytes
            if (!writing) {
                writing = true
                writer.execute {
                    while (true) {
                        val next = synchronized(writeLock) {
                            pendingWrite.also { pendingWrite = null; if (it == null) writing = false }
                        } ?: break
                        persist(next.first, next.second)
                    }
                }
            }
        }
    }
    @Synchronized fun export(context:Context):String="ReviewX ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})\nAndroid ${Build.VERSION.RELEASE} / API ${Build.VERSION.SDK_INT}\n"+JSONArray(entries.toList()).toString(2)+"\n"+XLoginDiagnostics.read(context)
}
