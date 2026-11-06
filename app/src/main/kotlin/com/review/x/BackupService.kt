package com.review.x

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.Credentials
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.MediaType.Companion.toMediaType
import org.json.JSONObject
import org.json.JSONArray
import java.net.URI
import java.net.URLEncoder

class BackupService(private val context: Context, private val settings: AppSettings) {
    private val session = SessionVault(context)
    private val dav = SessionVault(context, "compose-webdav-v1")
    private val journal = SessionVault(context, "compose-restore-journal-v1")
    fun config(): JSONObject = JSONObject(dav.readSecret() ?: "{}")
    fun saveConfig(config: JSONObject) { endpoint(config); dav.writeSecret(config.toString()) }
    fun export(includeCredentials: Boolean = false): JSONObject {
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
        return result
    }
    fun recoverInterruptedRestore():Unit = settings.atomic {
        val raw = journal.readSecret() ?: return@atomic
        val old = JSONObject(raw)
        settings.replace(old.getJSONObject("settings"))
        if (old.has("session")) session.writeSecret(old.getString("session")) else session.clear()
        if (old.has("webdav")) dav.writeSecret(old.getString("webdav")) else dav.clear()
        journal.clear()
    }
    fun restore(raw: JSONObject, allowCredentials: Boolean):Unit = settings.atomic {
        require(raw.toString().toByteArray(Charsets.UTF_8).size <= MAX_BYTES) { "备份文件过大" }
        require(raw.str("app") == "com.review.x" && raw.optInt("schema") == 1 && raw.optJSONObject("reading") != null && raw.optJSONObject("appearance") != null) { "这不是 ReviewX 的有效设置备份" }
        val full = raw.str("backup_mode") == "full"
        require(!full || allowCredentials) { "恢复全量备份需要确认替换登录凭据" }
        val restoredSession = if (full) raw.obj("credentials").optJSONObject("session")?.let(LegacyImport::validatedSession) else null
        val credentials = raw.obj("credentials")
        if (credentials.has("webdav_password")) require(credentials.get("webdav_password") is String)
        val next = settings.snapshot()
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
            val value = appearance.opt(key)
            when (key) {
                "theme_mode" -> if (value is Number && value.toInt() in 0..2) next.put(key, value.toInt())
                "key_theme_color_index" -> if (value is Number && value.toInt() in 0..7) next.put(key, value.toInt())
                "font_weight_delta" -> if (value is Number && value.toInt() in -300..300) next.put(key, value.toInt())
                else -> if (value is Boolean) next.put(key, value)
            }
        }
        val threshold = raw.obj("cache").optInt("auto_clear_cache_threshold_mb", -1)
        if (threshold in AppSettings.cacheThresholds) next.put("auto_clear_cache_threshold_mb", threshold)
        next.put("reading_settings", AppSettings.validatedReading(raw.obj("reading")).toString())
        val config = config(); raw.optJSONObject("webdav")?.let { incoming -> listOf("url", "user", "directory").forEach { if (incoming.opt(it) is String) config.put(it, incoming.getString(it)) } }
        if (full && credentials.has("webdav_password")) config.put("password", credentials.getString("webdav_password"))
        if (config.str("url").isNotBlank()) endpoint(config)
        journal.writeSecret(JSONObject().put("settings", settings.snapshot()).apply { session.readSecret()?.let { put("session", it) }; dav.readSecret()?.let { put("webdav", it) } }.toString())
        try {
            settings.replace(next)
            dav.writeSecret(config.toString())
            restoredSession?.let(session::save)
            journal.clear()
        } catch (error: Exception) { recoverInterruptedRestore(); throw error }
    }
    suspend fun test(config: JSONObject): String = withContext(Dispatchers.IO) {
        execute(config, "PROPFIND", endpoint(config), "").use { require(it.code in 200..299) { "连接失败，请检查服务器地址、账号与授权密码" } }
        "WebDAV 连接成功"
    }
    suspend fun upload(config: JSONObject, full: Boolean) = withContext(Dispatchers.IO) {
        val endpoint = endpoint(config)
        if (config.str("directory").isNotBlank()) execute(config, "MKCOL", endpoint, "").use { require(it.code in listOf(200, 201, 204, 405)) { "无法创建备份目录" } }
        execute(config, "PUT", endpoint + "Review_X_settings.json", export(full).toString()).use { require(it.code in 200..299) { "备份提交未确认，请检查 WebDAV 文件后再操作" } }
    }
    suspend fun download(config: JSONObject): JSONObject = withContext(Dispatchers.IO) {
        execute(config, "GET", endpoint(config) + "Review_X_settings.json").use {
            require(it.code == 200) { "无法读取 WebDAV 备份，请检查地址和账号" }
            val body = it.body ?: throw ApiFailure("备份文件为空")
            require(body.contentLength() <= MAX_BYTES) { "备份文件过大" }
            val source = body.source(); source.request(MAX_BYTES.toLong() + 1)
            require(source.buffer.size <= MAX_BYTES) { "备份文件过大" }
            JSONObject(source.readUtf8())
        }
    }
    private fun execute(config: JSONObject, method: String, url: String, body: String? = null) = AppNetwork.http.newCall(Request.Builder().url(url)
        .header("Authorization", Credentials.basic(config.str("user"), config.str("password"), Charsets.UTF_8)).header("Depth", "0")
        .method(method, body?.toRequestBody("application/json".toMediaType())).build()).execute()
    companion object {
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
