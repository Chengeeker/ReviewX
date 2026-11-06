package com.review.x

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import okhttp3.Call
import okhttp3.Callback
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.FormBody
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.MediaType.Companion.toMediaType
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

data class Feed(val kind: String = "HomeTimeline", val value: String = "", val title: String = "为你推荐", val option: String = "")

class ReaderRepository(context: Context) {
    private val assets = context.applicationContext.assets
    private val protocol by lazy { JSONObject(assets.open("twitter_protocol.json").bufferedReader().use { it.readText() }) }
    private val transactions by lazy { TransactionIds(assets.open("x_transaction_pairs.json").bufferedReader().use { it.readText() }) }
    private val http by lazy { AppNetwork.initialize(context.applicationContext); AppNetwork.http }

    suspend fun validate(raw: String): Pair<Session, User> {
        val candidate = Session.parse(raw)
        val settings = request(candidate, "/1.1/account/settings.json", mapOf("include_mention_filter" to "true"))
        val handle = settings.str("screen_name")
        if (!handle.matches(Regex("[A-Za-z0-9_]{1,50}"))) throw ApiFailure("未能确认当前账号，请重新登录")
        val user = if (candidate.userId != null) user(candidate, candidate.userId) else {
            val data = call(candidate, "UserByScreenName", JSONObject().put("screen_name", handle).put("withSafetyModeUserFields", true))
            User.parse(data.obj("user").obj("result")) ?: throw ApiFailure("账号资料不可用")
        }
        if (!user.handle.equals(handle, true) || (candidate.userId != null && candidate.userId != user.id)) throw ApiFailure("登录身份不一致，请重新登录")
        return Session.parse(candidate.cookie + if (candidate.userId == null) "; twid=u%3D${user.id}" else "") to user
    }

    suspend fun user(session: Session, id: String): User {
        require(id.matches(Regex("\\d+")))
        val data = call(session, "UserByRestId", JSONObject().put("userId", id).put("withSafetyModeUserFields", true))
        return User.parse(data.obj("user").obj("result")) ?: throw ApiFailure("用户不可用或资料结构已变化")
    }

    suspend fun page(session: Session, feed: Feed, cursor: String?, refresh: Boolean, seen: List<String>): PostPage {
        val variables = JSONObject().put("count", 20).put("includePromotedContent", false)
        if (cursor != null) variables.put("cursor", cursor)
        when (feed.kind) {
            "HomeTimeline", "HomeLatestTimeline" -> variables.put("latestControlAvailable", true)
                .put("requestContext", if (cursor != null) "scroll" else if (refresh) "ptr" else "launch")
                .put("seenTweetIds", JSONArray(seen.takeLast(50))).put("withCommunity", true)
                .put("withQuickPromoteEligibilityTweetFields", true).put("enableRanking", feed.kind == "HomeTimeline")
            "TweetDetail" -> variables.put("focalTweetId", feed.value).put("referrer", "tweet").put("withV2Timeline", true)
                .put("with_rux_injections", false).put("rankingMode", feed.option.ifBlank { "Relevance" }).put("withCommunity", true)
                .put("withQuickPromoteEligibilityTweetFields", true).put("withBirdwatchNotes", true).put("withVoice", true)
            "UserTweets", "UserTweetsAndReplies", "UserHighlightsTweets", "UserRepostsTimeline", "UserPhotoTimeline", "UserVideoTimeline", "UserArticlesTweets", "Likes" -> variables.put("userId", feed.value).put("withVoice", true).put("withCommunity", true)
                .put("withQuickPromoteEligibilityTweetFields", true).put("withClientEventToken", false)
                .put("withBirdwatchNotes", false).put("sortByMostLiked", false)
            "SearchTimeline" -> variables.put("rawQuery", feed.value).put("querySource", "typed_query").put("product", feed.option.ifBlank { "Top" })
            "Bookmarks" -> Unit
            else -> throw ApiFailure("不支持此阅读入口")
        }
        if (feed.kind == "Likes" && session.userId != feed.value) throw ApiFailure("仅可查看自己的喜欢列表")
        val data = call(session, feed.kind, variables)
        val timeline = when (feed.kind) {
            "HomeTimeline", "HomeLatestTimeline" -> data.obj("home").obj("home_timeline_urt")
            "TweetDetail" -> data.obj("threaded_conversation_with_injections_v2")
            "Bookmarks" -> data.obj("bookmark_timeline_v2").obj("timeline")
            "SearchTimeline" -> data.obj("search_by_raw_query").obj("search_timeline").obj("timeline")
            else -> {
                val result = data.obj("user").obj("result")
                val wrapper = result.optJSONObject("timeline") ?: result.obj("timeline_v2")
                wrapper.optJSONObject("timeline") ?: wrapper
            }
        }
        return withContext(Dispatchers.Default) { PostPage.parse(timeline) }
    }

    suspend fun userByHandle(session: Session, handle: String): User {
        require(handle.matches(Regex("[A-Za-z0-9_]{1,50}")))
        return User.parse(call(session, "UserByScreenName", JSONObject().put("screen_name", handle).put("withSafetyModeUserFields", true)).obj("user").obj("result")) ?: throw ApiFailure("用户不可用")
    }
    suspend fun users(session: Session, feed: Feed, cursor: String?): UserPage {
        val variables = JSONObject().put("count", 20).put("includePromotedContent", false)
        cursor?.let { variables.put("cursor", it) }
        val timeline = if (feed.kind == "SearchTimeline") {
            val data = call(session, feed.kind, variables.put("rawQuery", feed.value).put("querySource", "typed_query").put("product", "People"))
            data.obj("search_by_raw_query").obj("search_timeline").obj("timeline")
        } else {
            require(feed.kind in listOf("Followers", "Following"))
            val result = call(session, feed.kind, variables.put("userId", feed.value)).obj("user").obj("result")
            val wrapper = result.optJSONObject("timeline") ?: result.obj("timeline_v2")
            wrapper.optJSONObject("timeline") ?: wrapper
        }
        return UserPage.parse(timeline)
    }
    suspend fun notifications(session: Session, cursor: String?): NotificationPage {
        val variables = JSONObject().put("timeline_type", "All").put("count", 20)
        cursor?.let { variables.put("cursor", it) }
        return NotificationPage.parse(call(session, "NotificationsTimeline", variables).obj("viewer_v2").obj("user_results").obj("result").obj("notification_timeline").obj("timeline"))
    }
    suspend fun markRead(session: Session, cursor: String) { rest(session, "/2/notifications/all/last_seen_cursor.json", mapOf("cursor" to cursor)) }
    suspend fun trends(session: Session, personalized: Boolean): List<Trend> {
        val fields = mutableMapOf("count" to "20", "include_entities" to "true", "include_user_entities" to "true", "tweet_mode" to "extended", "cards_platform" to "Web-12", "include_cards" to "1", "include_ext_is_blue_verified" to "1", "include_ext_views" to "true", "send_error_codes" to "true")
        if (!personalized) fields["tab_category"] = "objective_trends"
        val data = request(session, "/2/guide.json", fields)
        val trends = linkedMapOf<String, Trend>()
        fun read(item: JSONObject) {
            val trend = item.obj("trend")
            val name = trend.str("name", trend.str("trend_name"))
            val metadata = trend.optJSONObject("trend_metadata") ?: trend.obj("trendMetadata")
            if (name.isNotBlank()) trends.putIfAbsent(name.lowercase(), Trend(name, trend.str("description"), trend.str("metaDescription", trend.str("meta_description", metadata.str("metaDescription")))))
        }
        val timeline = data.obj("timeline")
        if (!timeline.has("instructions")) throw ApiFailure("趋势结构已变化")
        timeline.optJSONArray("instructions")?.objects()?.forEach { instruction ->
            val entries = instruction.obj("addEntries").optJSONArray("entries") ?: instruction.optJSONArray("entries") ?: JSONArray()
            entries.objects().forEach { entry ->
                val content = entry.obj("content")
                read(content.obj("item").obj("content")); read(content.obj("itemContent")); read(content)
                val items = content.obj("timelineModule").optJSONArray("items") ?: content.optJSONArray("items") ?: JSONArray()
                items.objects().forEach { read(it.obj("item").obj("content")); read(it.obj("item").obj("itemContent")) }
            }
        }
        return trends.values.toList()
    }
    suspend fun recommended(session: Session): List<User> {
        val data = request(session, "/1.1/users/recommendations.json", mapOf("user_id" to session.userId.orEmpty(), "display_location" to "profile_accounts_sidebar", "limit" to "10", "pc" to "true", "skip_status" to "1"))
        return data.optJSONArray("items")?.objects().orEmpty().mapNotNull { item ->
            val raw = item.optJSONObject("user") ?: item
            User.parse(raw) ?: User.parse(JSONObject().put("rest_id", item.str("user_id",raw.str("id_str"))).put("legacy", raw))
        }.filter { it.id!=session.userId && !it.isFollowing }.distinctBy { it.id }
    }
    suspend fun article(session: Session, postId: String): Post {
        val data = call(session, "TweetResultByRestId", JSONObject().put("tweetId", postId).put("withCommunity", false).put("includePromotedContent", false).put("withVoice", false))
        val post = Post.parse(data.obj("tweetResult").obj("result"))
        return post?.takeIf { it.article != null } ?: throw ApiFailure("这篇文章暂不可用，请在网页查看")
    }
    suspend fun follow(session: Session, id: String, following: Boolean): User {
        rest(session, if (following) "/1.1/friendships/create.json" else "/1.1/friendships/destroy.json", mapOf("user_id" to id, "include_following" to "1", "include_followed_by" to "1", "skip_status" to "1"))
        try {
            return user(session, id).also { if (it.isFollowing != following && !(following && it.protected && it.followRequested)) throw ApiFailure("关注状态未确认", uncertain = true) }
        } catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
        catch (_: Exception) { throw ApiFailure("关注结果待确认，请刷新主页核对后再操作", uncertain = true) }
    }
    suspend fun like(session: Session, id: String, liked: Boolean) {
        val data = call(session, if (liked) "FavoriteTweet" else "UnfavoriteTweet", JSONObject().put("tweet_id", id))
        if (data.str(if (liked) "favorite_tweet" else "unfavorite_tweet") != "Done") throw ApiFailure("操作结果未确认，请刷新核对", uncertain = true)
    }
    suspend fun bookmark(session: Session, id: String, bookmarked: Boolean) {
        val data = call(session, if (bookmarked) "CreateBookmark" else "DeleteBookmark", JSONObject().put("tweet_id", id))
        if (data.str(if (bookmarked) "tweet_bookmark_put" else "tweet_bookmark_delete") != "Done") throw ApiFailure("书签结果未确认，请刷新核对", uncertain = true)
    }
    suspend fun repost(session: Session, id: String, reposted: Boolean) {
        val data = call(session, if (reposted) "CreateRetweet" else "DeleteRetweet", JSONObject().put(if (reposted) "tweet_id" else "source_tweet_id", id).put("dark_request", false))
        val result = (data.optJSONObject("create_retweet") ?: data.obj("unretweet")).obj("retweet_results").obj("result")
        if (!result.has("rest_id")) throw ApiFailure("转发结果未确认，请刷新核对", uncertain = true)
    }
    suspend fun delete(session: Session, id: String) {
        if (call(session, "DeleteTweet", JSONObject().put("tweet_id", id).put("dark_request", false)).optJSONObject("delete_tweet") == null) throw ApiFailure("删除结果未确认，请刷新核对", uncertain = true)
    }
    suspend fun publish(session: Session, text: String, replyId: String? = null, quoteUrl: String? = null): String {
        require(text.isNotBlank() || quoteUrl != null) { "请输入帖子正文" }
        val variables = JSONObject().put("tweet_text", text).put("dark_request", false)
            .put("media", JSONObject().put("media_entities", JSONArray()).put("possibly_sensitive", false)).put("semantic_annotation_ids", JSONArray())
        replyId?.let { variables.put("reply", JSONObject().put("in_reply_to_tweet_id", it).put("exclude_reply_user_ids", JSONArray())) }
        quoteUrl?.let { require(safeLink(it) && URIHost(it) in listOf("x.com", "twitter.com")); variables.put("attachment_url", it) }
        val id = call(session, "CreateTweet", variables).obj("create_tweet").obj("tweet_results").obj("result").str("rest_id")
        if (!id.matches(Regex("\\d+"))) throw ApiFailure("发布结果待确认，请先核对，避免重复发布", uncertain = true)
        return id
    }
    private fun URIHost(url: String) = java.net.URI(url).host
    private suspend fun rest(session: Session, path: String, fields: Map<String, String>): JSONObject {
        require(path in listOf("/1.1/friendships/create.json", "/1.1/friendships/destroy.json", "/2/notifications/all/last_seen_cursor.json"))
        val body = FormBody.Builder().apply { fields.forEach { (key, value) -> add(key, value) } }.build()
        return request(session, path, emptyMap(), "POST", body)
    }
    private suspend fun call(session: Session, operation: String, variables: JSONObject): JSONObject = withContext(Dispatchers.IO) {
        val config = protocol.optJSONObject(operation) ?: throw ApiFailure("接口配置缺失")
        val method = config.str("method")
        require(method in listOf("GET", "POST"))
        val id = config.getString("id")
        require(id.matches(Regex("[A-Za-z0-9_-]+")) && operation.matches(Regex("[A-Za-z]+")))
        val query = if (method == "GET") mapOf("variables" to variables.toString(), "features" to config.obj("features").toString(), "fieldToggles" to config.obj("fieldToggles").toString()) else emptyMap()
        val payload = if (method == "POST") JSONObject().put("variables", variables).put("features", config.obj("features")).put("fieldToggles", config.obj("fieldToggles")).put("queryId", id).toString().toRequestBody("application/json".toMediaType()) else null
        val body = request(session, "/graphql/$id/$operation", query, method, payload)
        body.optJSONObject("data") ?: throw ApiFailure("接口返回了无法识别的数据", uncertain = method == "POST")
    }

    private suspend fun request(session: Session, path: String, query: Map<String, String>, method: String = "GET", payload: RequestBody? = null): JSONObject = withContext(Dispatchers.IO) {
        val url = "https://api.x.com$path".toHttpUrl().newBuilder().apply { query.forEach { (key, value) -> addQueryParameter(key, value) } }.build()
        val request = Request.Builder().url(url).method(method, payload).header("Authorization", "Bearer $BEARER")
            .header("Cookie", session.cookie).header("x-csrf-token", session.csrf)
            .header("x-twitter-active-user", "yes").header("x-twitter-auth-type", "OAuth2Session")
            .header("x-twitter-client-language", "zh-cn").header("Accept-Language", "zh-CN,zh;q=0.9")
            .header("x-client-transaction-id", transactions.create(method, path)).header("User-Agent", USER_AGENT)
            .header("Origin", "https://x.com").header("Referer", "https://x.com/").build()
        suspendCancellableCoroutine { continuation ->
            val started=System.nanoTime()
            val event=if(path.startsWith("/graphql/"))path.substringAfterLast('/') else path.substringAfterLast('/').substringBefore('.')
            val call = http.newCall(request)
            continuation.invokeOnCancellation { call.cancel() }
            call.enqueue(object : Callback {
                override fun onFailure(call: Call, e: IOException) {
                    if(!call.isCanceled()) DiagnosticLog.record(event,duration=(System.nanoTime()-started)/1000000,error=e)
                    if (continuation.isActive) continuation.resumeWithException(ApiFailure(if (method == "POST") "结果尚未确认，请刷新核对后再操作" else "网络连接失败，请检查网络或 VPN 后重试", uncertain = method == "POST"))
                }
                override fun onResponse(call: Call, response: Response) {
                    DiagnosticLog.record(event,response.code,(System.nanoTime()-started)/1000000)
                    try {
                        response.use {
                            if (it.code == 401) throw ApiFailure("会话已过期，请重新登录", true)
                            if (it.code == 429) throw ApiFailure("请求频率受限，请稍后手动重试")
                            if (it.code != 200) throw ApiFailure("请求失败（${it.code}），请稍后重试", uncertain = method == "POST" && it.code >= 500)
                            val body = it.body ?: throw ApiFailure("服务器返回空响应", uncertain = method == "POST")
                            if (body.contentLength() > MAX_RESPONSE) throw ApiFailure("响应超过安全大小限制", uncertain = method == "POST")
                            val source = body.source()
                            source.request(MAX_RESPONSE + 1)
                            if (source.buffer.size > MAX_RESPONSE) throw ApiFailure("响应超过安全大小限制", uncertain = method == "POST")
                            val value = JSONTokener(source.readUtf8()).nextValue()
                            val json = when (value) { is JSONObject -> value; is JSONArray -> JSONObject().put("items", value); else -> throw ApiFailure("响应结构已变化", uncertain = method == "POST") }
                            val errors = json.optJSONArray("errors")?.objects().orEmpty()
                            if (errors.any { it.optInt("code") in listOf(32, 89, 215) }) throw ApiFailure("会话已过期，请重新登录", true)
                            if (errors.any { it.optInt("code") == 88 }) throw ApiFailure("请求频率受限，请稍后手动重试")
                            if (errors.isNotEmpty()) throw ApiFailure("接口拒绝了请求，请稍后手动重试")
                            if (continuation.isActive) continuation.resume(json)
                        }
                    } catch (error: Exception) {
                        if (continuation.isActive) continuation.resumeWithException(if (error is ApiFailure) error else ApiFailure(if (method == "POST") "结果尚未确认，请刷新核对后再操作" else "响应读取失败，请重试", uncertain = method == "POST"))
                    }
                }
            })
        }
    }
    companion object {
        const val USER_AGENT = "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36"
        private const val MAX_RESPONSE = 8L * 1024 * 1024
        // Public web client identifier, not an account credential.
        private const val BEARER = "AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA"
    }
}
