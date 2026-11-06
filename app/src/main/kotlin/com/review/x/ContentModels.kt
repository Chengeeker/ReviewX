package com.review.x

import org.json.JSONArray
import org.json.JSONObject
import java.net.URI

fun safeLink(value: String): Boolean = runCatching { val uri = URI(value); uri.scheme in listOf("https", "http") && !uri.host.isNullOrBlank() && uri.userInfo == null }.getOrDefault(false)
private fun cardValues(card: JSONObject): JSONObject {
    val legacy = card.optJSONObject("legacy") ?: card
    return legacy.optJSONObject("binding_values") ?: JSONObject().apply {
        legacy.optJSONArray("binding_values")?.objects()?.forEach { put(it.str("key"), it.obj("value")) }
    }
}
data class LinkCard(val title: String, val description: String, val url: String, val image: String) {
    companion object {
        fun parse(card: JSONObject): LinkCard? {
            val values = cardValues(card)
            fun text(key: String) = values.obj(key).str("string_value")
            val url = text("card_url").ifBlank { text("vanity_url") }
            if (!safeLink(url) || text("title").isBlank()) return null
            return LinkCard(text("title"), text("description"), url, listOf("summary_photo_image_large", "photo_image_full_size_large", "thumbnail_image_original")
                .map { values.obj(it).obj("image_value").str("url") }.firstOrNull(::safeMediaUrl).orEmpty())
        }
    }
}
data class Poll(val choices: List<String>, val votes: List<Long>, val endsAt: String, val selected: Int?) {
    val total get() = votes.sum()
    companion object {
        fun parse(card: JSONObject): Poll? {
            val values = cardValues(card)
            fun text(key: String) = values.obj(key).str("string_value")
            val indices = (1..4).filter { text("choice${it}_label").isNotBlank() }
            if (indices.size < 2) return null
            return Poll(indices.map { text("choice${it}_label") }, indices.map { text("choice${it}_count").toLongOrNull()?.coerceIn(0, 1L shl 53) ?: 0 },
                text("end_datetime_utc"), text("selected_choice").toIntOrNull())
        }
    }
}
data class TextRange(val offset: Int, val length: Int, val value: String)
data class ArticleBlock(val text: String, val type: String, val styles: List<TextRange>, val links: List<TextRange>, val media: List<Media>, val caption: String)
data class Article(val id: String, val title: String, val preview: String, val cover: Media?, val blocks: List<ArticleBlock>) {
    companion object {
        private fun media(raw: JSONObject): Media? {
            val info = raw.obj("media_info")
            val preview = info.obj("preview_image")
            val url = info.str("original_img_url", preview.str("original_img_url"))
            if (!safeMediaUrl(url)) return null
            val variants = info.optJSONArray("variants")?.objects().orEmpty().mapNotNull {
                if (it.str("content_type") == "video/mp4" && safeMediaUrl(it.str("url"))) VideoVariant(it.str("url"), it.optLong("bit_rate")) else null
            }.sortedByDescending { it.bitrate }
            return Media(url, "文章图片", variants.isNotEmpty(), info.optInt("original_img_width", preview.optInt("original_img_width")), info.optInt("original_img_height", preview.optInt("original_img_height")), variants)
        }
        fun parse(raw: JSONObject): Article? {
            if (raw.str("title").isBlank()) return null
            val state = raw.obj("content_state")
            val entities = state.optJSONObject("entityMap") ?: JSONObject().apply { state.optJSONArray("entityMap")?.objects()?.forEach { put(it.str("key"), it.obj("value")) } }
            val media = raw.optJSONArray("media_entities")?.objects().orEmpty().associate { it.str("media_id") to media(it) }
            val blocks = state.optJSONArray("blocks")?.objects().orEmpty().map { block ->
                val images = mutableListOf<Media>(); val links = mutableListOf<TextRange>(); var caption = ""
                block.optJSONArray("entityRanges")?.objects()?.forEach { range ->
                    val entity = entities.obj(range.str("key")); val data = entity.obj("data")
                    if (entity.str("type") == "LINK" && safeLink(data.str("url"))) links += TextRange(range.optInt("offset"), range.optInt("length"), data.str("url"))
                    if (entity.str("type") == "MEDIA") {
                        caption = data.str("caption")
                        data.optJSONArray("mediaItems")?.objects()?.forEach { media[it.str("mediaId")]?.let(images::add) }
                    }
                }
                block.obj("data").optJSONArray("urls")?.objects()?.forEach {
                    if (safeLink(it.str("text"))) links += TextRange(it.optInt("fromIndex"), it.optInt("toIndex") - it.optInt("fromIndex"), it.str("text"))
                }
                ArticleBlock(block.str("text"), block.str("type", "unstyled"), block.optJSONArray("inlineStyleRanges")?.objects().orEmpty().map { TextRange(it.optInt("offset"), it.optInt("length"), it.str("style")) }, links, images, caption)
            }
            return Article(raw.str("rest_id"), raw.str("title"), raw.str("preview_text"), media(raw.obj("cover_media")), blocks)
        }
    }
}
internal fun timelineItems(timeline: JSONObject): List<JSONObject> {
    val instructions = timeline.optJSONArray("instructions") ?: throw ApiFailure("列表结构已变化，请更新应用")
    val result = mutableListOf<JSONObject>()
    fun add(content: JSONObject, depth: Int = 0) {
        if (depth > 8 || content.has("promotedMetadata")) return
        if (content.has("cursorType")) { result += content; return }
        val item = content.optJSONObject("itemContent") ?: content
        if (!item.has("promotedMetadata") && item.has("itemType")) result += item
        content.optJSONArray("items")?.objects()?.forEach { add(it.obj("item"), depth + 1) }
    }
    instructions.objects().forEach { instruction ->
        instruction.optJSONArray("entries")?.objects()?.forEach { add(it.obj("content")) }
        instruction.optJSONObject("entry")?.let { add(it.obj("content")) }
        instruction.optJSONArray("moduleItems")?.objects()?.forEach { add(it.obj("item")) }
    }
    return result
}
data class UserPage(val users: List<User>, val cursor: String?) {
    companion object { fun parse(timeline: JSONObject): UserPage {
        val items = timelineItems(timeline)
        return UserPage(items.mapNotNull { User.parse(it.obj("user_results").obj("result")) }.distinctBy { it.id }, items.lastOrNull { it.str("cursorType") == "Bottom" }?.str("value")?.takeIf(String::isNotBlank))
    } }
}
data class SocialNotification(val id: String, val message: String, val url: String, val icon: String, val actors: List<User>, val posts: List<Post>, val timestamp: Long)
data class NotificationPage(val notifications: List<SocialNotification>, val cursor: String?, val topCursor: String?) {
    companion object { fun parse(timeline: JSONObject): NotificationPage {
        val items = timelineItems(timeline)
        val notifications = items.mapNotNull { item ->
            val post = Post.parse(item.obj("tweet_results").obj("result"))
            if (post != null) SocialNotification(post.id, "${post.author.name} 的帖子", "", "", emptyList(), listOf(post), 0)
            else if (item.str("itemType") == "TimelineNotification" && item.str("id").isNotBlank()) {
                val template = item.obj("template")
                SocialNotification(item.str("id"), item.obj("rich_message").str("text"), item.obj("notification_url").str("url"), item.str("notification_icon"),
                    template.optJSONArray("from_users")?.objects().orEmpty().mapNotNull { User.parse(it.obj("user_results").obj("result")) },
                    template.optJSONArray("target_objects")?.objects().orEmpty().mapNotNull { Post.parse(it.obj("tweet_results").obj("result")) }, item.optLong("timestamp_ms"))
            } else null
        }.distinctBy { it.id }
        return NotificationPage(notifications, items.lastOrNull { it.str("cursorType") == "Bottom" }?.str("value"), items.lastOrNull { it.str("cursorType") == "Top" }?.str("value"))
    } }
}
data class Trend(val name: String, val description: String, val meta: String)
