package com.review.x

import android.content.Context
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.Credentials
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.MediaType.Companion.toMediaType
import org.json.JSONObject
import org.json.JSONArray
import java.net.URI
import java.net.URLEncoder

class BackupService(private val context: Context, private val settings: AppSettings,
    private val session:SessionVault=SessionVault(context),private val dav:SessionVault=SessionVault(context,"compose-webdav-v1"),
    private val journal:SessionVault=SessionVault(context,"compose-restore-journal-v1")) {
    private val transport = WebDavTransport(AppNetwork.http, MAX_BYTES.toLong())
    fun config(): JSONObject = JSONObject(dav.readSecret() ?: "{}")
    fun saveConfig(config: JSONObject) { endpoint(config); dav.writeSecret(config.toString()) }
    fun export(includeCredentials: Boolean = false): JSONObject {
        val revision=SessionVault.revision.get()
        val all = settings.snapshot(); val config = config()
        val result = JSONObject().put("app", "com.review.x").put("schema", 1).put("backup_mode", if (includeCredentials) "full" else "safe")
            .put("appearance", JSONObject().apply { AppSettings.appearanceKeys.forEach { if (all.has(it)) put(it, all.get(it)) } })
            .put("reading", settings.reading()).put("cache", JSONObject().put("auto_clear_cache_threshold_mb", settings.int("auto_clear_cache_threshold_mb", 200)))
            .put("local", JSONObject().apply { all.keys().asSequence().filter(AppSettings::localBackupKey).forEach { put(it, all.get(it)) } })
            .put("webdav", JSONObject().apply { listOf("url", "user", "directory").forEach { if (config.has(it)) put(it, config.get(it)) } })
        if (includeCredentials) result.put("credentials", JSONObject().apply {
            session.read()?.let { put("session", JSONObject().put("cookie", it.cookie).put("userId", it.userId)) }
            if (config.has("password")) put("webdav_password", config.getString("password"))
        })
        require(result.toString().toByteArray(Charsets.UTF_8).size <= MAX_BYTES) { "备份文件过大" }
        result.put("accountMode",if(session.read()==null)"GUEST"else"COOKIE")
        check(revision==SessionVault.revision.get()){ "账号已改变，请重新备份" }
        return result
    }
    fun recoverInterruptedRestore():Unit = SessionVault.atomic { settings.atomic {
        val raw = journal.readSecret() ?: return@atomic
        val old = JSONObject(raw)
        settings.replace(old.getJSONObject("settings"))
        if(old.has("encrypted")) {
            val encrypted=old.getJSONObject("encrypted")
            session.restoreEncrypted(encrypted.optString("session").takeIf{it.isNotBlank()}?.let{android.util.Base64.decode(it,android.util.Base64.NO_WRAP)})
            dav.restoreEncrypted(encrypted.optString("webdav").takeIf{it.isNotBlank()}?.let{android.util.Base64.decode(it,android.util.Base64.NO_WRAP)})
        } else {
            if (old.has("session")) session.writeSecret(old.getString("session")) else session.clear()
            if (old.has("webdav")) dav.writeSecret(old.getString("webdav")) else dav.clear()
        }
        journal.clear()
    } }
    suspend fun restore(raw: JSONObject, allowCredentials: Boolean, verify: suspend (Session)->Session = { ReaderRepository(context).validate(it.cookie).first }):String = restoreMutex.withLock {
        val revision=SessionVault.revision.get()
        val oldSettings=settings.snapshot()
        val oldSession=session.encryptedSnapshot();val oldDav=dav.encryptedSnapshot()
        require(raw.toString().toByteArray(Charsets.UTF_8).size <= MAX_BYTES) { "备份文件过大" }
        require(raw.str("app") == "com.review.x" && raw.optInt("schema") == 1 && raw.optJSONObject("reading") != null && raw.optJSONObject("appearance") != null) { "这不是 ReviewX 的有效设置备份" }
        require(!raw.has("backup_mode") || raw.opt("backup_mode") in setOf("safe","full")){"备份模式无效"}
        val full = raw.str("backup_mode") == "full"
        require(full || !raw.has("credentials")){"安全备份包含不应有的凭据"}
        require(!full || allowCredentials) { "恢复全量备份需要确认替换登录凭据" }
        val restoredSession = if (full) raw.obj("credentials").optJSONObject("session")?.let(LegacyImport::validatedSession) else null
        val credentials = raw.obj("credentials")
        if (credentials.has("webdav_password")) require(credentials.get("webdav_password") is String)
        val next = JSONObject(oldSettings.toString())
        raw.optJSONObject("local")?.let { local -> local.keys().asSequence().forEach { key ->
            require(AppSettings.localBackupKey(key)) { "备份中的本地数据无效" }
            val value = local.get(key)
            require(value is String || value is Boolean || value is Number || value is JSONArray) { "备份数据类型无效" }
            if (value is JSONArray) require((0 until value.length()).all { value.get(it) is String })
            when {
                key == "network_config" -> NetworkConfig.parse(JSONObject(value as String))
                key == "refresh_rate" -> require(value is Number)
                key.startsWith("notification_") && !key.startsWith("notification_seen_") -> require(value is Boolean)
                key !in AppSettings.appearanceKeys && key != "auto_clear_cache_threshold_mb" -> org.json.JSONTokener(value as String).nextValue()
            }
            if (key !in AppSettings.appearanceKeys && key !in listOf("reading_settings", "auto_clear_cache_threshold_mb")) next.put(key, value)
        } }
        val appearance = raw.obj("appearance")
        AppSettings.appearanceKeys.forEach { key ->
            if(!appearance.has(key))return@forEach
            val value=appearance.get(key)
            val range=when(key){"theme_mode"->0..2;"key_theme_color_index"->0..7;"font_weight_delta"->-300..300;else->null}
            require(if(range!=null)(value is Int || value is Long) && (value as Number).toLong() in range.first.toLong()..range.last.toLong() else value is Boolean){"备份外观字段类型或范围无效"}
            next.put(key,if(value is Number)value.toInt()else value)
        }
        val cache=raw.optJSONObject("cache")
        if(cache?.has("auto_clear_cache_threshold_mb")==true){
            val value=cache.get("auto_clear_cache_threshold_mb")
            require(value is Int && value in AppSettings.cacheThresholds){"备份缓存上限无效"}
            next.put("auto_clear_cache_threshold_mb",value)
        }
        val reading=raw.getJSONObject("reading")
        val normalized=AppSettings.validatedReading(reading)
        for(key in reading.keys()){
            if(!normalized.has(key))continue
            val value=reading.get(key);val result=normalized.get(key)
            require(when(result){is Number->value is Number && value.toDouble().isFinite() && value.toDouble()==result.toDouble()
                is Boolean->value is Boolean;else->value is String && value==result}){"备份阅读字段类型或范围无效"}
        }
        next.put("reading_settings",normalized.toString())
        val config = try{config()}catch(e:SecretReadFailure){if(!full || !e.recoverable)throw e;JSONObject()}
        val previousServer=config.str("url");val previousUser=config.str("user")
        raw.optJSONObject("webdav")?.let { incoming -> listOf("url", "user", "directory").forEach { if(incoming.has(it)){require(incoming.get(it) is String){"WebDAV 配置字段类型无效"};config.put(it, incoming.getString(it))} } }
        if(!full && (previousServer!=config.str("url") || previousUser!=config.str("user")))config.remove("password")
        if (full && credentials.has("webdav_password")) config.put("password", credentials.getString("webdav_password"))
        if (config.str("url").isNotBlank()) endpoint(config)
        var verified:Session?=null
        if(restoredSession!=null) {
            try{verified=verify(restoredSession).also{check(it.userId==restoredSession.userId){"登录校验账号不匹配"}}}
            catch(e:kotlinx.coroutines.CancellationException){throw e}
            catch(_:Exception){}
        }
        kotlinx.coroutines.currentCoroutineContext().ensureActive()
        SessionVault.atomic { settings.atomic {
            check(revision==SessionVault.revision.get() && oldSession.contentEquals(session.encryptedSnapshot()) && oldDav.contentEquals(dav.encryptedSnapshot()) && oldSettings.toString()==settings.snapshot().toString()) {"账号或设置已改变，请重新恢复"}
            journal.writeSecret(JSONObject().put("settings",oldSettings).put("encrypted",JSONObject()
                .put("session",oldSession?.let{android.util.Base64.encodeToString(it,android.util.Base64.NO_WRAP)}?:"")
                .put("webdav",oldDav?.let{android.util.Base64.encodeToString(it,android.util.Base64.NO_WRAP)}?:"")).toString())
            try {
                settings.replace(next)
                dav.writeSecret(config.toString(),recoverUnreadable=full)
                verified?.let{session.writeSecret(it.cookie,recoverUnreadable=true)}
                journal.clear()
            }catch(error:Exception){recoverInterruptedRestore();throw error}
        } }
        when {
            verified!=null->"设置和本地资料已恢复，账号登录已通过验证并恢复。"
            restoredSession!=null->"资料已恢复，但账号登录未恢复，请重试或重新登录。当前会话保持不变。"
            full->"设置和本地资料已恢复。备份未包含有效登录凭据，当前会话保持不变。"
            else->"设置和本地资料已恢复，当前账号登录保持不变。"
        }
    }
    suspend fun test(config: JSONObject): String {
        execute(config, "PROPFIND", endpoint(config)).requireStatus("连接测试", setOf(200, 207))
        return "WebDAV 连接成功"
    }
    suspend fun upload(config: JSONObject, full: Boolean) {
        val target = endpoint(config)
        val data = export(full).toString()
        if (config.str("directory").isNotBlank()) execute(config, "MKCOL", target).requireStatus("创建目录", setOf(200, 201, 204, 405))
        execute(config, "PUT", target + "Review_X_settings.json", data).requireStatus("上传", setOf(200, 201, 204))
    }
    suspend fun download(config: JSONObject): JSONObject =
        execute(config, "GET", endpoint(config) + "Review_X_settings.json").requireStatus("下载", setOf(200)).json()
    private suspend fun execute(config: JSONObject, method: String, url: String, body: String? = null) = transport.request(
        url.toHttpUrl(), method,
        Credentials.basic(config.str("user"), config.str("password"), Charsets.UTF_8), body?.toByteArray(Charsets.UTF_8))
    companion object {
        private val restoreMutex=kotlinx.coroutines.sync.Mutex()
        const val MAX_BYTES = 8 * 1024 * 1024
        fun endpoint(config: JSONObject): String {
            val raw = config.str("url").trim().trimEnd('/') + "/"
            val uri = URI(raw)
            require(uri.scheme == "https" && !uri.host.isNullOrBlank() && uri.userInfo == null && uri.query == null && uri.fragment == null) { "WebDAV 地址需要无查询参数的 HTTPS 地址" }
            val dir = config.str("directory").trim()
            require(dir !in listOf(".", "..") && !dir.contains('/') && !dir.contains('\\')) { "目录名称不能包含路径分隔符" }
            return if (dir.isBlank()) uri.toString() else uri.resolve(URLEncoder.encode(dir, "UTF-8").replace("+", "%20") + "/").toString()
        }
    }
}
