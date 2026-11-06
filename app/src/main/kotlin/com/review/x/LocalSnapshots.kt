package com.review.x

import org.json.JSONObject
import org.json.JSONArray
import java.time.Instant
import java.time.Duration

class LocalSnapshots(private val settings: AppSettings) {
    private fun prefix(account: String): String { require(account.matches(Regex("\\d+"))); return "reviewx_xcache_v1_${account}_" }
    private fun read(key: String, days: Long): JSONObject? = runCatching {
        val raw = settings.string(key)
        if (raw.toByteArray().size > 512*1024) return null
        val data = JSONObject(raw); val age=Duration.between(Instant.parse(data.str("savedAt")), Instant.now())
        data.takeIf { !age.isNegative && age <= Duration.ofDays(days) }
    }.getOrNull()
    fun profile(account: String): User? = read(prefix(account)+"profile",30)?.obj("user")?.let(CacheCodec::user)?.takeIf { it.id == account }
    fun profile(account: String, user: User) { if (user.id==account) settings.set(prefix(account)+"profile", JSONObject().put("savedAt",Instant.now().toString()).put("user",CacheCodec.user(user)).toString()) }
    fun timeline(account: String, kind: String): List<Post> = read(prefix(account)+"timeline_"+kind,14)?.takeIf { it.optInt("schema")==1 }?.optJSONArray("posts")?.objects().orEmpty().take(20).mapNotNull { CacheCodec.post(it) }
    internal fun homeScreen(account: String, feed: Feed): ReaderScreen? {
        val kind = cacheKind(feed.kind) ?: return null
        val posts = timeline(account, kind)
        if (posts.isEmpty()) return null
        return ReaderScreen(feed = feed, posts = posts, loaded = true, restoredSnapshot = true)
    }
    fun timeline(account: String, kind: String, posts: List<Post>) {
        if (kind !in listOf("for_you","following") || posts.isEmpty()) return
        val items=posts.take(20).map { CacheCodec.post(it) }.toMutableList()
        fun encode()=JSONObject().put("schema",1).put("savedAt",Instant.now().toString()).put("posts",JSONArray(items)).toString()
        var raw=encode()
        while(items.isNotEmpty() && raw.toByteArray().size>512*1024) { items.removeAt(items.lastIndex); raw=encode() }
        if(items.isNotEmpty()) settings.set(prefix(account)+"timeline_"+kind,raw)
    }
    fun clear(account: String) = settings.atomic { val data=settings.snapshot(); data.keys().asSequence().filter { it.startsWith(prefix(account)) }.toList().forEach(data::remove); settings.replace(data) }
    fun remove(account: String, id: String) = settings.atomic { listOf("for_you","following").forEach { kind ->
        val posts=timeline(account,kind).filterNot { it.id==id }.map { if(it.quote?.id==id) it.copy(quote=null) else it }
        if(posts.isEmpty()) { val data=settings.snapshot(); data.remove(prefix(account)+"timeline_"+kind); settings.replace(data) } else timeline(account,kind,posts)
    } }
}

internal fun cacheKind(kind: String): String? = when (kind) {
    "HomeTimeline" -> "for_you"
    "HomeLatestTimeline" -> "following"
    else -> null
}

object CacheCodec {
    fun user(u: User)=JSONObject().put("id",u.id).put("name",u.name).put("handle",u.handle).put("avatar",u.avatar).put("banner",u.banner).put("description",u.bio)
        .put("followers",u.followers).put("following",u.following).put("postsCount",u.postsCount).put("verified",u.verified).put("isFollowing",u.isFollowing)
        .put("followedBy",u.followedBy).put("protected",u.protected).put("followRequested",u.followRequested).put("location",u.location).put("website",u.website)
        .put("createdAt",u.created).put("knownCounts",JSONArray(u.knownCounts.toList()))
    fun user(r: JSONObject): User? {
        if(!r.str("id").matches(Regex("\\d{1,32}")) || r.str("handle").isBlank()) return null
        return User(r.str("id"),r.str("name").take(200),r.str("handle").take(100),r.str("avatar").takeIf(::safeMediaUrl).orEmpty(),r.str("description").take(1200),
            r.str("banner").takeIf(::safeMediaUrl).orEmpty(),n(r,"followers"),n(r,"following"),n(r,"postsCount"),r.optBoolean("isFollowing"),r.optBoolean("followedBy"),r.optBoolean("protected"),
            r.optBoolean("followRequested"),r.optBoolean("verified"),r.str("location").take(200),r.str("website").takeIf(::safeLink).orEmpty(),r.str("createdAt").take(80),
            r.optJSONArray("knownCounts")?.let { a -> (0 until a.length()).map { a.optString(it) }.toSet() } ?: setOf("followers","following","postsCount"))
    }
    private fun n(r: JSONObject,key: String)=r.optLong(key).coerceIn(0,1L shl 53)
    fun media(m: Media)=JSONObject().put("preview",m.url).put("video",m.variants.firstOrNull()?.url).put("width",m.width).put("height",m.height).put("alt",m.description)
        .put("videoQualities",JSONObject().apply { m.variants.take(12).forEach { put(quality(it),it.url) } })
    fun media(r: JSONObject): Media? {
        val url=r.str("preview"); if(!safeMediaUrl(url)) return null
        val qualities=r.obj("videoQualities")
        val variants=qualities.keys().asSequence().take(12).mapNotNull { key -> qualities.str(key).takeIf(::safeMediaUrl)?.let { VideoVariant(it,key.substringBefore(' ').substringBefore('p').toLongOrNull() ?: 0) } }.toList()
            .ifEmpty { r.str("video").takeIf(::safeMediaUrl)?.let { listOf(VideoVariant(it,0)) } ?: emptyList() }
        return Media(url,r.str("alt").take(1200),variants.isNotEmpty(),r.optInt("width").coerceIn(0,100000),r.optInt("height").coerceIn(0,100000),variants)
    }
    fun quality(v: VideoVariant): String {
        val resolution=Regex("/(\\d+)x(\\d+)/").find(v.url)
        return if(resolution!=null) "${minOf(resolution.groupValues[1].toInt(),resolution.groupValues[2].toInt())}p" else "${v.bitrate/1000} kbps"
    }
    fun post(p: Post,depth: Int=0): JSONObject = JSONObject().put("id",p.id).put("author",user(p.author)).put("text",p.text.take(50000)).put("translatedText",p.translated.take(50000))
        .put("createdAt",p.created).put("media",JSONArray(p.media.take(4).map(::media))).put("likes",p.likes).put("reposts",p.reposts).put("replies",p.replies)
        .put("liked",p.liked).put("reposted",p.reposted).put("quote",if(depth<1) p.quote?.let { post(it,depth+1) } else null).put("repostedBy",p.repostedBy)
        .put("views",p.views).put("source",p.source.take(300)).put("sensitive",p.sensitive).put("replyToHandle",p.replyTo).put("replyToId",p.replyToId).put("conversationId",p.conversationId).put("bookmarked",p.bookmarked)
        .put("article",p.article?.let { JSONObject().put("id",it.id).put("title",it.title).put("preview",it.preview.take(1200)).put("cover",it.cover?.let(::media)) })
        .put("linkCard",p.linkCard?.let { JSONObject().put("title",it.title).put("description",it.description).put("url",it.url).put("image",it.image) })
        .put("poll",p.poll?.let { JSONObject().put("choices",JSONArray(it.choices)).put("votes",JSONArray(it.votes)).put("endsAt",it.endsAt).put("selected",it.selected) })
    fun post(r: JSONObject,depth: Int=0): Post? {
        if(depth>1 || !r.str("id").matches(Regex("\\d{1,32}"))) return null
        val user=user(r.obj("author")) ?: return null
        val card=r.obj("linkCard"); val article=r.obj("article"); val poll=r.obj("poll")
        val choices=poll.optJSONArray("choices")?.let { a -> (0 until minOf(a.length(),4)).map { a.optString(it).take(300) } }.orEmpty()
        return Post(r.str("id"),user,r.str("text").take(50000),r.str("createdAt").take(80),r.optJSONArray("media")?.objects().orEmpty().take(4).mapNotNull(::media),
            r.optJSONObject("quote")?.let { post(it,depth+1) },r.str("repostedBy").takeIf(String::isNotBlank)?.take(200),r.str("replyToHandle").take(100),n(r,"likes"),n(r,"replies"),n(r,"reposts"),
            r.str("translatedText").take(50000),r.optBoolean("sensitive"),r.optBoolean("liked"),r.optBoolean("reposted"),r.optBoolean("bookmarked"),n(r,"views"),r.str("source").take(300),r.str("replyToId").take(32),r.str("conversationId").take(32),
            if(article.str("title").isNotBlank()) Article(article.str("id"),article.str("title").take(300),article.str("preview").take(1200),article.optJSONObject("cover")?.let(::media),emptyList()) else null,
            if(safeLink(card.str("url"))) LinkCard(card.str("title").take(300),card.str("description").take(1000),card.str("url"),card.str("image").takeIf(::safeMediaUrl).orEmpty()) else null,
            if(choices.size>=2) Poll(choices,choices.indices.map { poll.optJSONArray("votes")?.optLong(it)?.coerceIn(0,1L shl 53) ?: 0 },poll.str("endsAt"),poll.optInt("selected").takeIf { it in 1..4 }) else null)
    }
}
