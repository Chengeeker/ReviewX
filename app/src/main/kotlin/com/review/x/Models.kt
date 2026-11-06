package com.review.x

import org.json.JSONArray
import org.json.JSONObject
import java.net.URI
import java.net.URLDecoder

internal fun JSONObject.obj(key: String) = optJSONObject(key) ?: JSONObject()
internal fun JSONObject.str(key: String, fallback: String = "") = if (isNull(key)) fallback else optString(key, fallback)
internal fun JSONArray.objects(): List<JSONObject> = (0 until length()).mapNotNull { optJSONObject(it) }

class Session private constructor(val cookie: String, val userId: String?) {
    val csrf: String get() = fields(cookie).getValue("ct0")
    // A session must never be interpolated into diagnostics or UI state dumps.
    override fun toString() = "Session(redacted)"
    companion object {
        fun fields(raw: String): Map<String, String> = raw.split(';').mapNotNull {
            val i = it.indexOf('=')
            if (i < 1) null else it.substring(0, i).trim() to it.substring(i + 1).trim()
        }.toMap()
        fun parse(raw: String): Session {
            require(raw.length <= 16384 && raw.none { it.code < 32 || it.code > 126 }) { "Cookie 格式不正确" }
            val values = fields(raw)
            require(!values["auth_token"].isNullOrBlank() && !values["ct0"].isNullOrBlank()) { "请完成登录后再导入 Cookie" }
            val cookie = listOf("auth_token", "ct0", "twid", "gt").mapNotNull { key ->
                values[key]?.takeIf(String::isNotBlank)?.let { "$key=$it" }
            }.joinToString("; ")
            val id = values["twid"]?.let {
                runCatching { Regex("^u=(\\d+)$").matchEntire(URLDecoder.decode(it, "UTF-8").replace("\"", ""))?.groupValues?.get(1) }.getOrNull()
            }
            return Session(cookie, id)
        }
    }
}

data class User(val id: String, val name: String, val handle: String, val avatar: String, val bio: String,
                val banner: String = "", val followers: Long = 0, val following: Long = 0, val postsCount: Long = 0,
                val isFollowing: Boolean = false, val followedBy: Boolean = false, val protected: Boolean = false,
                val followRequested: Boolean = false, val verified: Boolean = false, val location: String = "",
                val website: String = "", val created: String = "", val knownCounts: Set<String> = emptySet()) {
    fun preservingCounts(previous:User?):User = if(previous==null || previous.id!=id)this else copy(
        followers=if("followers" in knownCounts)followers else previous.followers,
        following=if("following" in knownCounts)following else previous.following,
        postsCount=if("postsCount" in knownCounts)postsCount else previous.postsCount,
        knownCounts=knownCounts+previous.knownCounts)
    companion object {
        fun parse(raw: JSONObject): User? {
            val legacy = raw.obj("legacy")
            val core = raw.obj("core")
            val id = raw.str("rest_id", legacy.str("id_str"))
            val handle = core.str("screen_name", legacy.str("screen_name"))
            if (!id.matches(Regex("\\d+")) || handle.isBlank()) return null
            return User(id, core.str("name", legacy.str("name", handle)), handle,
                raw.obj("avatar").str("image_url", legacy.str("profile_image_url_https")).replace("_normal.", "_bigger."),
                raw.obj("profile_bio").str("description", raw.obj("profile_description").str("description", legacy.str("description"))),
                raw.obj("banner").str("image_url", legacy.str("profile_banner_url")),
                raw.obj("relationship_counts").optLong("followers", legacy.optLong("followers_count")),
                raw.obj("relationship_counts").optLong("following", legacy.optLong("friends_count")),
                raw.obj("tweet_counts").optLong("tweets", legacy.optLong("statuses_count")),
                raw.obj("relationship_perspectives").optBoolean("following", legacy.optBoolean("following")),
                raw.obj("relationship_perspectives").optBoolean("followed_by", legacy.optBoolean("followed_by")),
                raw.obj("privacy").optBoolean("protected", legacy.optBoolean("protected")),
                raw.optBoolean("follow_request_sent", legacy.optBoolean("follow_request_sent")),
                raw.optBoolean("is_blue_verified") || legacy.optBoolean("verified"), raw.obj("location").str("location", legacy.str("location")),
                raw.obj("website").str("url", legacy.obj("entities").obj("url").optJSONArray("urls")?.optJSONObject(0)?.str("expanded_url") ?: legacy.str("url")),
                core.str("created_at", legacy.str("created_at")), buildSet {
                    if (raw.obj("relationship_counts").has("followers") || legacy.has("followers_count")) add("followers")
                    if (raw.obj("relationship_counts").has("following") || legacy.has("friends_count")) add("following")
                    if (raw.obj("tweet_counts").has("tweets") || legacy.has("statuses_count")) add("postsCount")
                })
        }
    }
}

fun safeMediaUrl(value: String): Boolean = runCatching {
    val uri = URI(value)
    uri.scheme == "https" && uri.userInfo == null && (uri.port == -1 || uri.port == 443) &&
        (uri.host == "pbs.twimg.com" || uri.host == "video.twimg.com")
}.getOrDefault(false)

data class VideoVariant(val url: String, val bitrate: Long)
data class Media(val url: String, val description: String, val video: Boolean,
                 val width: Int = 0, val height: Int = 0, val variants: List<VideoVariant> = emptyList()) {
    val original: String get() = if (url.contains("/media/")) okhttp3.HttpUrl.Companion.run { url.toHttpUrl().newBuilder().setQueryParameter("name", "orig").build().toString() } else url
    fun viewerImage(viewportWidth:Float,viewportHeight:Float):String = if(video||width<=0||height<=0||viewportWidth<=0||viewportHeight<=0)url else if(kotlin.math.min(viewportWidth/width,viewportHeight/height)<.75f)original else url
    companion object {
        fun parse(raw: JSONObject): Media? {
            val url = raw.str("media_url_https")
            if (!safeMediaUrl(url)) return null
            val variants = raw.obj("video_info").optJSONArray("variants")?.objects().orEmpty().mapNotNull {
                if (it.str("content_type") == "video/mp4" && safeMediaUrl(it.str("url"))) VideoVariant(it.str("url"), it.optLong("bitrate")) else null
            }.sortedByDescending { it.bitrate }
            return Media(url, raw.str("ext_alt_text"), raw.str("type") != "photo", raw.obj("original_info").optInt("width"), raw.obj("original_info").optInt("height"), variants)
        }
    }
}
data class Post(val id: String, val author: User, val text: String, val created: String,
                val media: List<Media>, val quote: Post?, val repostedBy: String?,
                val replyTo: String, val likes: Long, val replies: Long, val reposts: Long,
                val translated: String, val sensitive: Boolean, val liked: Boolean = false, val reposted: Boolean = false,
                val bookmarked: Boolean = false, val views: Long = 0, val source: String = "", val replyToId: String = "",
                val conversationId: String = "", val article: Article? = null, val linkCard: LinkCard? = null, val poll: Poll? = null) {
    companion object {
        fun parse(value: JSONObject, depth: Int = 0, repostedBy: String? = null): Post? {
            if (depth > 3) return null
            val raw = if (value.str("__typename") == "TweetWithVisibilityResults") value.obj("tweet") else value
            val legacy = raw.obj("legacy")
            val id = raw.str("rest_id", legacy.str("id_str"))
            val user = User.parse(raw.obj("core").obj("user_results").obj("result")) ?: return null
            if (!id.matches(Regex("\\d+"))) return null
            legacy.obj("retweeted_status_result").optJSONObject("result")?.let { return parse(it, depth + 1, user.name) }
            val note = raw.obj("note_tweet").obj("note_tweet_results").obj("result")
            var text = note.str("text", legacy.str("full_text"))
            val entities = note.optJSONObject("entity_set") ?: legacy.obj("entities")
            entities.optJSONArray("urls")?.objects()?.forEach {
                if (it.str("url").isNotEmpty()) text = text.replace(it.str("url"), it.str("expanded_url", it.str("url")))
            }
            val media = (legacy.obj("extended_entities").optJSONArray("media") ?: legacy.obj("entities").optJSONArray("media"))
                ?.objects().orEmpty().take(16).mapNotNull {
                    val url = it.str("media_url_https")
                    val short = it.str("url")
                    if (short.isNotEmpty()) text = text.replace(short, "")
                    Media.parse(it)
                }
            val translation = raw.obj("grok_translated_post_with_availability")
            return Post(id, user, decode(text).trim(), legacy.str("created_at"), media,
                raw.obj("quoted_status_result").optJSONObject("result")?.let { parse(it, depth + 1) }, repostedBy,
                legacy.str("in_reply_to_screen_name"), legacy.optLong("favorite_count"), legacy.optLong("reply_count"),
                legacy.optLong("retweet_count"), if (translation.optBoolean("is_available")) decode(translation.obj("data").str("translation")) else "",
                legacy.optBoolean("possibly_sensitive"), legacy.optBoolean("favorited"), legacy.optBoolean("retweeted"), legacy.optBoolean("bookmarked"),
                raw.obj("views").optLong("count"), raw.str("source", legacy.str("source")).replace(Regex("<[^>]*>"), ""),
                legacy.str("in_reply_to_status_id_str"), legacy.str("conversation_id_str"),
                Article.parse(raw.obj("article").obj("article_results").obj("result")), LinkCard.parse(raw.obj("card")), Poll.parse(raw.obj("card")))
        }
        private fun decode(text: String) = text.replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">")
    }
}

data class PostPage(val posts: List<Post>, val cursor: String?) {
    companion object {
        fun parse(timeline: JSONObject): PostPage {
            val instructions = timeline.optJSONArray("instructions") ?: throw ApiFailure("时间线结构已变化，请更新应用")
            val posts = linkedMapOf<String, Post>()
            var cursor: String? = null
            fun item(content: JSONObject, depth: Int = 0) {
                if (depth > 8) return
                if (content.str("cursorType") == "Bottom") cursor = content.str("value").takeIf(String::isNotBlank)
                if (content.has("promotedMetadata")) return
                val data = content.optJSONObject("itemContent") ?: content
                if (data.has("promotedMetadata")) return
                Post.parse(data.obj("tweet_results").obj("result"))?.let { posts.putIfAbsent(it.id, it) }
                content.optJSONArray("items")?.objects()?.forEach { item(it.obj("item"), depth + 1) }
            }
            instructions.objects().forEach { instruction ->
                instruction.optJSONArray("entries")?.objects()?.forEach { item(it.obj("content")) }
                instruction.optJSONObject("entry")?.let { item(it.obj("content")) }
                instruction.optJSONArray("moduleItems")?.objects()?.forEach { item(it.obj("item")) }
            }
            return PostPage(posts.values.toList(), cursor)
        }
    }
}

class ApiFailure(message: String, val expired: Boolean = false, val uncertain: Boolean = false) : Exception(message)
