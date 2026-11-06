package com.review.x

import org.json.JSONObject
import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Test

class ProtocolTest {
    @Test fun cookieWhitelistAndIdentity() {
        val session = Session.parse("auth_token=fixture; ct0=csrf; twid=u%3D123; unrelated=private")
        assertEquals("123", session.userId)
        assertEquals("csrf", session.csrf)
        assertFalse(session.cookie.contains("unrelated"))
        assertEquals("Session(redacted)", session.toString())
    }
    @Test fun rejectsHeaderInjectionAndIncompleteSessions() {
        listOf("auth_token=x; ct0=y\r\nHost: example.com", "ct0=y", "auth_token=x; ct0=", "auth_token=x; ct0=y\u0000").forEach {
            assertThrows(IllegalArgumentException::class.java) { Session.parse(it) }
        }
    }
    @Test fun malformedIdentityIsNotTrusted() {
        assertNull(Session.parse("auth_token=x; ct0=y; twid=%GG").userId)
        assertNull(Session.parse("auth_token=x; ct0=y; twid=u=123suffix").userId)
    }
    @Test fun mediaUrlsCannotEscapeCdnBoundary() {
        assertTrue(safeMediaUrl("https://pbs.twimg.com/media/test.jpg"))
        listOf("http://pbs.twimg.com/a", "https://pbs.twimg.com.evil.test/a", "https://pbs.twimg.com@evil.test/a",
            "https://evil.test@pbs.twimg.com/a", "file:///tmp/a", "https://pbs.twimg.com:444/a").forEach { assertFalse(it, safeMediaUrl(it)) }
    }
    @Test fun transactionMatchesFlutterGolden() {
        assertEquals("BwYFBAMEBQa4LRsurVpWFVPhMuqT/t3ZBA", TransactionIds.encode("GET", "/graphql/id/op", "AQID", "test", 0x01020304, 7))
    }
    @Test fun transactionRejectsOutOfRangeInputs() {
        assertThrows(IllegalArgumentException::class.java) { TransactionIds.encode("GET", "/", "AQID", "test", -1, 0) }
        assertThrows(IllegalArgumentException::class.java) { TransactionIds.encode("GET", "/", "AQID", "test", 1, 256) }
    }
    @Test fun missingTimelineIsAnErrorNotAnEmptyFeed() {
        assertThrows(ApiFailure::class.java) { PostPage.parse(JSONObject()) }
        assertTrue(PostPage.parse(JSONObject("""{"instructions":[]}""")).posts.isEmpty())
    }
    @Test fun quotesStayInsidePostsAndRowsAreDeduplicated() {
        val quoted = tweet("2")
        val main = tweet("1").put("quoted_status_result", JSONObject().put("result", quoted))
        val page = PostPage.parse(JSONObject().put("instructions", JSONArray(listOf(JSONObject().put("entries", JSONArray(listOf(
            entry(main), entry(main), JSONObject().put("content", JSONObject().put("cursorType", "Bottom").put("value", "next")))))))))
        assertEquals(listOf("1"), page.posts.map { it.id })
        assertEquals("2", page.posts.single().quote?.id)
        assertEquals("next", page.cursor)
    }
    @Test fun modulesAndPromotionsAreHandledExplicitly() {
        val promoted = entry(tweet("4"))
        promoted.getJSONObject("content").put("promotedMetadata", JSONObject())
        val module = JSONObject().put("content", JSONObject().put("items", JSONArray(listOf(JSONObject().put("item", entry(tweet("3")).getJSONObject("content"))))))
        val page = PostPage.parse(JSONObject().put("instructions", JSONArray(listOf(JSONObject().put("entries", JSONArray(listOf(module, promoted)))))))
        assertEquals(listOf("3"), page.posts.map { it.id })
    }
    @Test fun modernUserFieldsAndLongTextOverrideLegacy() {
        val raw = tweet("1").put("note_tweet", JSONObject("""{"note_tweet_results":{"result":{"text":"long &amp; complete"}}}"""))
        val post = Post.parse(raw)!!
        assertEquals("Modern", post.author.name)
        assertEquals("long & complete", post.text)
    }
    @Test fun pagesStayBoundedAndDoNotDuplicateIds() {
        val posts = (1..310).map { Post.parse(tweet(it.toString()))!! }
        val merged = mergePosts(posts.take(300), posts.drop(290))
        assertEquals(300, merged.size)
        assertEquals("11", merged.first().id)
        assertEquals("310", merged.last().id)
    }
    private fun entry(post: JSONObject) = JSONObject().put("content", JSONObject().put("itemContent", JSONObject().put("tweet_results", JSONObject().put("result", post))))
    private fun tweet(id: String) = JSONObject("""{
        "rest_id":"$id", "core":{"user_results":{"result":{
          "rest_id":"123", "core":{"screen_name":"reader","name":"Modern"},
          "legacy":{"screen_name":"old","name":"Legacy"}}}},
        "legacy":{"full_text":"body","favorite_count":2}}
    """)
}
