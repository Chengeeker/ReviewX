package com.review.x

import org.json.JSONObject
import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Test

class MigrationTest {
    @Test fun cachedTimelinePrefetchWaitsForScrollAndStopsAfterFailure() {
        val cached = ReaderScreen(loaded = true, restoredSnapshot = true)
        assertFalse(cached.shouldPrefetch(4, 6, hasScrolled = false))
        assertFalse(cached.shouldPrefetch(-1, 21, hasScrolled = true))
        assertFalse(cached.shouldPrefetch(2, 21, hasScrolled = true))
        assertTrue(cached.shouldPrefetch(12, 21, hasScrolled = true))
        assertFalse(cached.copy(error = "网络错误").shouldPrefetch(20, 21, hasScrolled = true))
        assertFalse(cached.copy(busy = true).shouldPrefetch(20, 21, hasScrolled = true))
        assertFalse(cached.copy(restoredSnapshot = false).shouldPrefetch(20, 21, hasScrolled = true))
        assertTrue(cached.copy(restoredSnapshot = false, cursor = "next").shouldPrefetch(20, 21, hasScrolled = true))
    }
    @Test fun richTextPreservesOriginalUnicodeAndUrlBoundaries() {
        val text="😀 #中文，＃测试! #123 &amp#tag https://example.com/#section @reader $"+"ABC"
        val links=textLinks(text)
        assertEquals(listOf("#中文","＃测试","https://example.com/#section","@reader","$"+"ABC"),links.map {it.value})
        links.forEach {assertEquals(it.value,text.substring(it.offset,it.offset+it.length))}
        assertEquals("https://x.com/reader",textLinkUrl("@reader"))
        assertEquals("search",DeepLinks.parse(textLinkUrl("＃测试"))?.kind)
    }
    @Test fun galleryButtonStretchKeepsAnchorContinuousAndBoundsDeformation() {
        assertArrayEquals(floatArrayOf(1f,1f,.5f,.5f),galleryButtonStretch(0f,0f),.0001f)
        val right=galleryButtonStretch(1000f,0f);assertEquals(1.3f,right[0],.0001f);assertEquals(.85f,right[1],.0001f);assertEquals(0f,right[2],.0001f)
        val left=galleryButtonStretch(-1000f,0f);assertEquals(1f,left[2],.0001f);assertEquals(right[0],left[0],.0001f)
        assertEquals(.5f,galleryButtonStretch(.001f,0f)[2],.0001f)
    }
    @Test fun galleryImageSelectionMatchesOriginalPhysicalPixelThreshold() {
        val image=Media("https://pbs.twimg.com/media/test.jpg","",false,4000,3000)
        assertEquals(image.original,image.viewerImage(1080f,1920f))
        assertEquals(image.url,image.viewerImage(4000f,3000f))
        assertEquals(image.url,image.copy(width=0).viewerImage(1080f,1920f))
    }
    @Test fun legacyCipherReadsBothPayloadFormatsAndRejectsDamage() {
        val key=javax.crypto.spec.SecretKeySpec(ByteArray(16){it.toByte()},"AES")
        val plain="{\"cookie\":\"auth_token=a; ct0=b\"}".toByteArray()
        listOf(false,true).forEach {gcm->
            val iv=ByteArray(if(gcm)12 else 16){(it+3).toByte()}
            val cipher=javax.crypto.Cipher.getInstance(if(gcm)"AES/GCM/NoPadding"else "AES/CBC/PKCS5Padding")
            cipher.init(javax.crypto.Cipher.ENCRYPT_MODE,key,if(gcm)javax.crypto.spec.GCMParameterSpec(128,iv)else javax.crypto.spec.IvParameterSpec(iv))
            val payload=iv+cipher.doFinal(plain)
            assertArrayEquals(plain,LegacyImport.decryptLegacy(payload,key,gcm))
            assertThrows(IllegalArgumentException::class.java){LegacyImport.decryptLegacy(byteArrayOf(1,2),key,gcm)}
            if(gcm){payload[payload.lastIndex]=(payload.last().toInt() xor 1).toByte();assertThrows(javax.crypto.AEADBadTagException::class.java){LegacyImport.decryptLegacy(payload,key,true)}}
        }
    }
    @Test fun galleryFlightPreservesSourceCropAndFitsDestination() {
        val frame=androidx.compose.ui.geometry.Rect(12f,90f,132f,210f)
        val source=GalleryAnchor(frame,frame)
        val viewport=androidx.compose.ui.geometry.Rect(0f,0f,400f,800f)
        val image=androidx.compose.ui.geometry.Size(2f,1f)
        val opening=galleryGeometry(source,viewport,image,0f,true)
        assertEquals(frame,opening.clip);assertEquals(240f,opening.image.width,.001f)
        val full=galleryGeometry(source,viewport,image,1f,true)
        assertEquals(androidx.compose.ui.geometry.Rect(0f,300f,400f,500f),full.image)
        assertEquals(androidx.compose.ui.geometry.Rect(0f,0f,400f,800f),full.clip)
        assertEquals(opening,galleryGeometry(source,viewport,image,-1f,true))
    }
    @Test fun returnEndpointUsesPhysicalScreenPositionAndOriginalCropUnderClipping() {
        val screenFrame = androidx.compose.ui.geometry.Rect(16f, 152f, 136f, 272f)
        val screenClip = androidx.compose.ui.geometry.Rect(16f, 180f, 136f, 272f)
        val overlayOrigin = androidx.compose.ui.geometry.Offset(0f, 48f)
        val source = GalleryAnchor(screenFrame, screenClip).inOverlay(overlayOrigin)
        val viewport = androidx.compose.ui.geometry.Rect(0f, 0f, 400f, 800f)
        val image = androidx.compose.ui.geometry.Size(2f, 1f)
        val finalFraction = 1f - galleryHeroProgress(1f, returning = true)
        val final = galleryGeometry(source, viewport, image, finalFraction, covers = true)
        assertEquals(screenFrame, final.frame.translate(overlayOrigin))
        assertEquals(screenClip, final.clip.translate(overlayOrigin))
        assertEquals(galleryImagePlane(screenFrame, image, crop = true), final.image.translate(overlayOrigin))
    }
    @Test fun galleryReturnToHalfWidthTileMovesAndShrinksFromVisibleImageTogether() {
        val viewport = androidx.compose.ui.geometry.Rect(0f, 0f, 400f, 800f)
        val tile = androidx.compose.ui.geometry.Rect(200f, 100f, 380f, 280f)
        val imageSize = androidx.compose.ui.geometry.Size(2f, 1f)
        val fitted = galleryImagePlane(viewport, imageSize, crop = false)
        val halfway = galleryGeometry(GalleryAnchor(tile, tile), viewport, imageSize,
            .5f, covers = true, fullImage = fitted, fullClip = fitted)
        assertEquals(androidx.compose.ui.geometry.Rect(100f, 200f, 390f, 390f), halfway.clip)
        assertEquals(halfway.clip, halfway.clip.intersect(halfway.image))
        assertTrue(halfway.clip.width < fitted.width)
    }
    @Test fun galleryPageFeedbackSkipsUnchangedPagesAndEnforcesFlutterCooldown() {
        val feedback = GalleryPageFeedback()
        assertFalse(feedback.shouldTick(0, 0, 0))
        assertTrue(feedback.shouldTick(0, 1, 0))
        assertFalse(feedback.shouldTick(1, 2, 39))
        assertTrue(feedback.shouldTick(2, 1, 40))
    }
    @Test fun galleryFlightUsesCachedImagePlaneAndReversibleRedNoteCurve() {
        val source=androidx.compose.ui.geometry.Rect(10f,10f,110f,110f)
        val wideImage=androidx.compose.ui.geometry.Size(400f,200f)
        assertEquals(androidx.compose.ui.geometry.Rect(-40f,10f,160f,110f),galleryImagePlane(source,wideImage,true))
        assertEquals(androidx.compose.ui.geometry.Rect(0f,300f,400f,500f),galleryImagePlane(androidx.compose.ui.geometry.Rect(0f,0f,400f,800f),wideImage,false))
        assertEquals(0f,galleryHeroProgress(0f,false),.0001f)
        assertEquals(1f,galleryHeroProgress(1f,false),.0001f)
        assertEquals(0f,galleryHeroProgress(0f,true),.0001f)
        assertEquals(1f,galleryHeroProgress(1f,true),.0001f)
        val opening=galleryHeroProgress(.3f,false)
        assertEquals(1f-opening,galleryHeroProgress(.7f,true),.0001f)
    }
    @Test fun deepLinksPreserveTrustedRoutesAndRejectAuthorityConfusion() {
        assertEquals(LinkTarget("post","123"),DeepLinks.parse("https://x.com/name/status/123?ref=test"))
        assertEquals(LinkTarget("search","中国 + test"),DeepLinks.parse("https://twitter.com/search?q=%E4%B8%AD%E5%9B%BD%20%2B%20test"))
        assertEquals(LinkTarget("bookmarks"),DeepLinks.parse("https://x.com/i/bookmarks"))
        listOf("https://x.com.evil.test/home","https://evil@x.com/home","https://x.com:444/home","file://x.com/home","javascript:alert(1)").forEach{assertNull(DeepLinks.parse(it))}
        assertEquals("other",DeepLinks.parse("https://x.com/i/unsupported")?.kind)
    }
    @Test fun unknownProfileCountsDoNotEraseKnownValuesButExplicitZeroDoes() {
        val old=User("1","Reader","reader","","",followers=800,following=90,postsCount=70,knownCounts=setOf("followers","following","postsCount"))
        val update=User("1","Reader","reader","","",following=0,knownCounts=setOf("following"))
        val merged=update.preservingCounts(old)
        assertEquals(800L,merged.followers);assertEquals(0L,merged.following);assertEquals(70L,merged.postsCount)
        assertEquals(0L,update.copy(id="2").preservingCounts(old).followers)
    }
    @Test fun readingSettingsClampAndCarryForwardLegacyFolders() {
        val reading=AppSettings.validatedReading(JSONObject("""{"fontSize":999,"appTextScale":0.2,"imageRadius":-1,"storageFolder":"author","defaultMutedVideo":"false","videoQuality":"invalid"}"""))
        assertEquals(24.0,reading.getDouble("fontSize"),0.0);assertEquals(.8,reading.getDouble("appTextScale"),0.0)
        assertEquals(0.0,reading.getDouble("imageRadius"),0.0);assertEquals("author",reading.getString("imageStorageFolder"));assertFalse(reading.getBoolean("defaultMutedVideo"));assertEquals("balanced",reading.getString("videoQuality"))
    }
    @Test fun backupWhitelistExcludesCredentialsAndArbitraryKeys() {
        listOf("history_123","notification_seen_12","reviewx_xcache_v1_12_timeline_for_you","reading_settings").forEach{assertTrue(AppSettings.localBackupKey(it))}
        listOf("twitter_session_v1","webdav_config","history_other","reviewx_xcache_v1_12_session","flutter_credentials_imported").forEach{assertFalse(AppSettings.localBackupKey(it))}
    }
    @Test fun fullBackupSessionIdentityIsValidatedBeforeSaving() {
        assertEquals("12",LegacyImport.validatedSession(JSONObject("""{"cookie":"auth_token=fixture; ct0=fixture","userId":"12"}""")).userId)
        assertThrows(IllegalArgumentException::class.java){LegacyImport.validatedSession(JSONObject("""{"cookie":"auth_token=fixture; ct0=fixture; twid=u%3D99","userId":"12"}"""))}
    }
    @Test fun webDavUsesOneEncodedDirectoryAndCannotEscapeEndpoint() {
        assertEquals("https://backup.example/dav/Review%20X/",BackupService.endpoint(JSONObject("""{"url":"https://backup.example/dav","directory":"Review X"}""")))
        listOf("http://backup.example/dav","https://user:pass@backup.example/dav","https://backup.example/dav?token=x").forEach{url->assertThrows(IllegalArgumentException::class.java){BackupService.endpoint(JSONObject().put("url",url))}}
        listOf("..","../other","dir\\other").forEach{dir->assertThrows(IllegalArgumentException::class.java){BackupService.endpoint(JSONObject().put("url","https://backup.example/dav/").put("directory",dir))}}
    }
    @Test fun manualProxyInputDoesNotAcceptCredentialsOrPaths() {
        NetworkConfig("manual","127.0.0.1",7890).validate()
        listOf(NetworkConfig("manual","host/path",7890),NetworkConfig("manual","user@host",7890),NetworkConfig("manual","host",65536),NetworkConfig("unknown")).forEach{assertThrows(IllegalArgumentException::class.java){it.validate()}}
    }
    @Test fun mediaOriginalPreservesFormatAndQualityFallbackIsBounded() {
        val media=Media("https://pbs.twimg.com/media/example?format=png&name=small","",false)
        assertEquals("https://pbs.twimg.com/media/example?format=png&name=orig",media.original)
        val video=media.copy(video=true,variants=listOf(VideoVariant("https://video.twimg.com/a/1920x1080/v.mp4",6000000),VideoVariant("https://video.twimg.com/a/1280x720/v.mp4",2000000),VideoVariant("https://video.twimg.com/a/640x360/v.mp4",500000)))
        assertEquals(720,videoHeight(preferredVideo(video,"balanced")!!.url));assertEquals(360,videoHeight(preferredVideo(video,"data_saver")!!.url));assertEquals(1080,videoHeight(preferredVideo(video,"high")!!.url))
    }
    @Test fun cacheCodecCannotRestoreForeignHostsOrInventCounts() {
        val raw=JSONObject("""{"id":"1","handle":"reader","name":"Reader","avatar":"https://evil.test/image","followers":-8,"knownCounts":[],"website":"javascript:alert(1)"}""")
        val user=CacheCodec.user(raw)!!;assertEquals("",user.avatar);assertEquals("",user.website);assertEquals(0L,user.followers);assertTrue(user.knownCounts.isEmpty())
        assertNull(CacheCodec.user(raw.put("id","not-a-numeric-id")))
    }
    @Test fun notificationModulesKeepCursorsAndIgnorePromotedEntries() {
        val item=JSONObject("""{"itemType":"TimelineNotification","id":"notice-1","rich_message":{"text":"liked"},"notification_icon":"heart_icon","template":{}}""")
        val timeline=JSONObject().put("instructions",JSONArray().put(JSONObject().put("entries",JSONArray().put(JSONObject().put("content",JSONObject().put("items",JSONArray().put(JSONObject().put("item",JSONObject().put("itemContent",item)))))).put(JSONObject().put("content",JSONObject().put("cursorType","Top").put("value","top"))).put(JSONObject().put("content",JSONObject().put("itemContent",JSONObject(item.toString()).put("id","ad").put("promotedMetadata",JSONObject())))))))
        val page=NotificationPage.parse(timeline);assertEquals(1,page.notifications.size);assertEquals("top",page.topCursor);assertEquals("likes",NotificationWorker.category(page.notifications.single()))
    }
    @Test fun imageInertiaKeepsOriginalLogicalThresholdAndDistance() {
        val zero=androidx.compose.ui.geometry.Offset.Zero
        assertEquals(zero,galleryInertia(androidx.compose.ui.geometry.Offset(799f,0f),2f))
        assertEquals(androidx.compose.ui.geometry.Offset(240f,0f),galleryInertia(androidx.compose.ui.geometry.Offset(800f,0f),2f))
        assertEquals(androidx.compose.ui.geometry.Offset(-72f,96f),galleryInertia(androidx.compose.ui.geometry.Offset(-300f,400f),1f))
        assertEquals(zero,galleryInertia(androidx.compose.ui.geometry.Offset(Float.NaN,0f),1f))
        assertEquals(zero,galleryInertia(zero,0f))
    }
    @Test fun glassBlurFallbackPreservesSolidColorsAndBounds() {
        val solid=IntArray(15){0xffaabbcc.toInt()}
        assertArrayEquals(solid,gaussianBlur(solid,5,3,2f))
        val impulse=IntArray(9){if(it==4)0xffffffff.toInt()else 0xff000000.toInt()}
        val blurred=gaussianBlur(impulse,3,3,1f)
        assertEquals(blurred[0],blurred[8]);assertEquals(blurred[1],blurred[7])
        assertTrue((blurred[4]and 255)>(blurred[0]and 255))
        assertTrue(blurred.all{it ushr 24==255})
        assertThrows(IllegalArgumentException::class.java){gaussianBlur(solid,5,4,1f)}
    }
}
