package com.review.x

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import org.json.JSONObject
import org.json.JSONArray

class AppSettings(context: Context) {
    private val preferences = context.applicationContext.getSharedPreferences("compose-preferences-v1", 0)
    private val mutable = synchronized(stores) { stores.getOrPut(context.applicationContext.filesDir.absolutePath) { MutableStateFlow(read()) } }
    val changes = mutable.asStateFlow()
    fun <T> atomic(block:()->T):T = synchronized(mutable,block)
    fun snapshot() = JSONObject(mutable.value.toString())
    private fun read() = runCatching { JSONObject(preferences.getString("data", "{}")!!) }.getOrDefault(JSONObject())
    fun set(key: String, value: Any) = synchronized(mutable) { replace(snapshot().put(key, value)) }
    fun replace(data: JSONObject) = synchronized(mutable) {
        check(preferences.edit().putString("data", data.toString()).commit()) { "保存设置失败" }
        mutable.value = JSONObject(data.toString())
    }
    fun reading() = validatedReading(runCatching { JSONObject(mutable.value.str("reading_settings", "{}")) }.getOrDefault(JSONObject()))
    fun setReading(key: String, value: Any) = synchronized(mutable) {set("reading_settings", validatedReading(reading().put(key, value)).toString())}
    fun bool(key: String, fallback: Boolean = false) = mutable.value.optBoolean(key, fallback)
    fun int(key: String, fallback: Int = 0) = mutable.value.optInt(key, fallback)
    fun string(key: String, fallback: String = "") = mutable.value.str(key, fallback)
    fun history(account: String): List<JSONObject> = runCatching { JSONArray(string("history_$account", "[]")).objects().take(200) }.getOrDefault(emptyList())
    fun addHistory(account: String, post: Post) = synchronized(mutable) {
        if (!reading().optBoolean("saveHistory", true)) return@synchronized
        val item = JSONObject().put("id", post.id).put("url", "https://x.com/${post.author.handle}/status/${post.id}")
            .put("title", post.text.take(140)).put("author", post.author.name).put("time", java.time.Instant.now().toString())
        set("history_$account", JSONArray((listOf(item) + history(account).filter { it.str("id") != post.id }).take(200)).toString())
    }
    fun searches(account: String): List<String> = runCatching {
        val items = JSONArray(string("search_history_$account", "[]")); (0 until items.length()).map { items.optString(it) }.filter(String::isNotBlank).take(10)
    }.getOrDefault(emptyList())
    fun addSearch(account: String, query: String) = synchronized(mutable) {set("search_history_$account", JSONArray((listOf(query.trim()) + searches(account).filterNot { it.equals(query.trim(), true) }).filter(String::isNotBlank).take(10)).toString())}
    fun removeSearch(account: String, query: String) = synchronized(mutable) {set("search_history_$account", JSONArray(searches(account).filterNot { it.equals(query, true) }).toString())}
    fun importFlutter(context: Context) {
        if (bool("flutter_preferences_imported")) return
        val old = context.getSharedPreferences("FlutterSharedPreferences", 0)
        val data = snapshot()
        old.all.forEach { (key, value) ->
            val name = key.removePrefix("flutter.")
            if (key.startsWith("flutter.") && localBackupKey(name) && !data.has(name) && value != null) data.put(name, value)
        }
        data.put("reading_settings", validatedReading(runCatching { JSONObject(data.str("reading_settings", "{}")) }.getOrDefault(JSONObject())).toString())
        data.put("flutter_preferences_imported", true)
        replace(data)
    }
    companion object {
        private val stores = mutableMapOf<String,MutableStateFlow<JSONObject>>()
        val appearanceKeys = setOf("theme_mode", "use_dynamic_color", "key_theme_color_index", "key_is_pure_black_dark", "haptics", "floating_nav", "use_liquid_glass_effect", "translucentNavigationGlass", "custom_font_weight", "font_weight_delta")
        val cacheThresholds = listOf(0, 50, 100, 200, 500, 1024, 2048)
        fun localBackupKey(key: String): Boolean = key in appearanceKeys || key in setOf("reading_settings", "network_config", "refresh_rate", "notification_enabled", "notification_likes", "notification_reposts", "notification_followers", "notification_replies", "notification_mentions", "notification_other", "auto_clear_cache_threshold_mb") ||
            Regex("^(history_|search_history_|notification_seen_)\\d+$").matches(key) || Regex("^reviewx_xcache_v1_\\d+_(profile|timeline_for_you|timeline_following)$").matches(key)
        fun validatedReading(input: JSONObject): JSONObject {
            val defaults = JSONObject("""{"relativeTime":true,"showYear":false,"showWeekday":false,"showSeconds":false,"utcTime":false,"showSource":false,"grokAutoTranslate":false,"showBanner":true,"cardBackground":true,"fontSize":16.0,"appTextScale":1.0,"lineHeight":1.5,"largeImages":true,"defaultMutedVideo":false,"imageRadius":16.0,"coloredLinks":true,"saveHistory":true,"storageFolder":"default","imageStorageFolder":"default","videoStorageFolder":"default","videoQuality":"balanced","showSensitive":false}""")
            defaults.keys().asSequence().toList().forEach { key ->
                val value = input.opt(key)
                when (defaults.get(key)) {
                    is Boolean -> if (value is Boolean) defaults.put(key, value)
                    is Number -> if (value is Number && value.toDouble().isFinite()) defaults.put(key, value.toDouble())
                    is String -> if (key.endsWith("StorageFolder") || key == "storageFolder") {
                        if (value in listOf("default", "me", "author")) defaults.put(key, value)
                    } else if (key == "videoQuality" && value in listOf("balanced", "high", "data_saver")) defaults.put(key, value)
                }
            }
            listOf("imageStorageFolder", "videoStorageFolder").forEach { if (input.str(it) !in listOf("default", "me", "author")) defaults.put(it, defaults.str("storageFolder")) }
            mapOf("fontSize" to 12.0..24.0, "appTextScale" to 0.8..1.5, "lineHeight" to 1.1..2.0, "imageRadius" to 0.0..28.0).forEach { (key, range) -> defaults.put(key, defaults.optDouble(key).coerceIn(range)) }
            return defaults
        }
    }
}
