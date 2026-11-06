package com.review.x

import android.app.Application
import android.graphics.Bitmap
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.hapticfeedback.HapticFeedback
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.AndroidComposeTestRule
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.semantics.getOrNull
import org.json.JSONObject
import org.junit.*
import org.junit.runner.RunWith
import org.junit.rules.TestRule
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk=[34],qualifiers="w411dp-h891dp-xhdpi",application=Application::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class UiParityTest {
    private val activity=Robolectric.buildActivity(ComponentActivity::class.java)
    @get:Rule val compose = AndroidComposeTestRule(TestRule { test, _ -> test }) { activity.get() }
    @After fun cleanup(){activity.pause().stop().destroy()}
    @Test fun scrollAndCancelledPressStaySilentWhileConfirmedTapHonorsSetting() {
        activity.setup()
        var enabled by mutableStateOf(true)
        var clicks = 0
        val events = mutableListOf<HapticFeedbackType>()
        val feedback = object : HapticFeedback {
            override fun performHapticFeedback(hapticFeedbackType: HapticFeedbackType) {
                events.add(hapticFeedbackType)
            }
        }
        compose.setContent {
            CompositionLocalProvider(LocalHapticFeedback provides feedback) {
                ReviewTheme(JSONObject().put("haptics", enabled)) {
                    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
                        Box(Modifier.fillMaxWidth().height(180.dp).testTag("card")
                            .hapticClickable { clicks++ })
                        Spacer(Modifier.height(1100.dp))
                    }
                }
            }
        }
        val card = compose.onNodeWithTag("card")
        card.performTouchInput { down(center) }
        compose.runOnIdle { Assert.assertTrue(events.isEmpty()) }
        card.performTouchInput { cancel() }
        card.performTouchInput { click() }
        compose.runOnIdle {
            Assert.assertEquals(1, clicks)
            Assert.assertEquals(listOf(HapticFeedbackType.VirtualKey), events)
            enabled = false
        }
        card.performTouchInput { click() }
        compose.runOnIdle {
            Assert.assertEquals(2, clicks)
            Assert.assertEquals(1, events.size)
            enabled = true
        }
        card.performTouchInput {
            down(center)
            advanceEventTime(40)
            moveBy(Offset(0f, -100f))
            up()
        }
        compose.runOnIdle {
            Assert.assertEquals(2, clicks)
            Assert.assertEquals(1, events.size)
        }
    }

    @Suppress("DEPRECATION")
    @Test fun immersiveStatusBarUsesTransparentWindowAndAppThemeIcons() {
        activity.setup()
        compose.runOnUiThread {
            val window = activity.get().window
            window.statusBarColor = android.graphics.Color.BLACK
            window.isStatusBarContrastEnforced = true
            val insets = androidx.core.view.WindowCompat.getInsetsController(window, window.decorView)
            window.setBackgroundDrawable(android.graphics.drawable.ColorDrawable(android.graphics.Color.BLACK))
            window.applyReaderWindow(androidx.compose.ui.graphics.Color.White)
            Assert.assertEquals(android.graphics.Color.TRANSPARENT, window.statusBarColor)
            Assert.assertFalse(window.isStatusBarContrastEnforced)
            Assert.assertTrue(insets.isAppearanceLightStatusBars)
            val background = org.robolectric.Shadows.shadowOf(window).backgroundDrawable as android.graphics.drawable.ColorDrawable
            Assert.assertEquals(android.graphics.Color.WHITE, background.color)
            window.applyReaderWindow(androidx.compose.ui.graphics.Color.Black)
            Assert.assertFalse(insets.isAppearanceLightStatusBars)
        }
    }
    @Test fun restoredHomeFeedsAreReadyAndOnlyManualPaginationCanStartWithoutCursor() {
        activity.setup()
        val settings = AppSettings(activity.get())
        val snapshots = LocalSnapshots(settings)
        val user = User("51", "缓存作者", "reader", "", "")
        val post = Post("101", user, "之前打开的帖子", "", emptyList(), null, null, "", 0, 0, 0, "", false)
        val following = Feed("HomeLatestTimeline", title = "正在关注")
        snapshots.timeline("51", "for_you", listOf(post))
        snapshots.timeline("51", "following", listOf(post.copy(id = "102")))
        val restarted = LocalSnapshots(AppSettings(activity.get()))
        val restored = listOf(
            requireNotNull(restarted.homeScreen("51", Feed())),
            requireNotNull(restarted.homeScreen("51", following)),
        )
        Assert.assertEquals(listOf("101", "102"), restored.map { it.posts.single().id })
        restored.forEach {
            Assert.assertTrue(it.loaded)
            Assert.assertTrue(it.canLoadMore)
            Assert.assertNull(it.cursor)
            Assert.assertFalse(it.busy)
        }
        Assert.assertNull(restarted.homeScreen("52", Feed()))
        settings.set("reviewx_xcache_v1_51_timeline_following", "{broken")
        Assert.assertNull(restarted.homeScreen("51", following))
    }

    @Test fun articleKeepsCachedPreviewWithOnlyTopConnectionProgress() {
        activity.setup()
        val model = ReaderViewModel(activity.get().application)
        val post = Post("101", User("51", "缓存作者", "reader", "", ""), "", "",
            emptyList(), null, null, "", 0, 0, 0, "", false,
            article = Article("2", "之前打开的文章", "保留原来的文章摘要", null, emptyList()))
        val state = ReaderState(screens = listOf(ReaderScreen(
            feed = Feed("Article", post.id), selectedPost = post, busy = true,
        )))
        compose.setContent {
            ReviewTheme(JSONObject()) {
                CompositionLocalProvider(LocalActions provides UiActions(model, {}, {}, {})) {
                    ArticleScreen(state, model)
                }
            }
        }
        compose.onNodeWithText("正在连接 X", substring = true).assertIsDisplayed()
        compose.onNodeWithText("保留原来的文章摘要").assertIsDisplayed()
        compose.onAllNodes(SemanticsMatcher.keyIsDefined(androidx.compose.ui.semantics.SemanticsProperties.ProgressBarRangeInfo))
            .assertCountEquals(1)
    }
    @Test fun originalGlassOpticalKernelCompilesOnHostSkia() {
        activity.setup()
        val source=activity.get().assets.open("glass/premium.agsl").bufferedReader().use {it.readText()}
        // Robolectric SDK 34 uses Android S Skia (upstream #9691); adapt only its child-sampling syntax.
        Assert.assertTrue(source.contains("uBackgroundTexture.eval("))
        val shader=android.graphics.RuntimeShader(source.replace("uBackgroundTexture.eval(","sample(uBackgroundTexture, "))
        GlassStyle(androidx.compose.ui.graphics.Color.White).uniforms(240,56,2f).forEach {(name,value)->shader.setFloatUniform(name,value)}
        val gallery=activity.get().assets.open("glass/gallery.agsl").bufferedReader().use {it.readText()}
        android.graphics.RuntimeShader(gallery.replace("uBackgroundTexture.eval(","sample(uBackgroundTexture, "))
        val navigation = activity.get().assets.open("glass/liquid_glass.agsl").bufferedReader().use { it.readText() }
        android.graphics.RuntimeShader(navigation.replace("background.eval(", "sample(background, "))
        val icons=JSONObject(activity.get().assets.open("flutter_icons.json").bufferedReader().use {it.readText()})
        listOf("chevron_right_rounded","notifications_active_outlined","more_vert","subdirectory_arrow_right").forEach {Assert.assertTrue(icons.has(it))}
    }
    @Test fun guestAndRootNavigationMatchOriginalEntryPoints() {
        activity.setup()
        val model=ReaderViewModel(activity.get().application)
        compose.runOnUiThread { activity.get().setContent {ReviewTheme(JSONObject().put("theme_mode",1)){Surface {Column {AppTopBar("ReviewX");Box(Modifier.weight(1f)){Guest(model)};BottomNavigation(0,{},{});Spacer(Modifier.height(24.dp))}}}} }
        compose.onNodeWithText("登录 X，阅读你的关注时间线").assertIsDisplayed()
        listOf("首页","探索","设置").forEach {compose.onNodeWithText(it).assertIsDisplayed()}
        capture("guest-light")
    }
    @Test fun settingsKeepOriginalSectionsAndRows() {
        activity.setup();val model=ReaderViewModel(activity.get().application);val settings=JSONObject().put("theme_mode",1)
        compose.runOnUiThread {activity.get().setContent {ReviewTheme(settings){Surface {SettingsHome(model,ReaderState(authenticating=false,settings=settings))}}}}
        compose.onNodeWithText("偏好与功能").assertIsDisplayed();compose.onNodeWithText("WebDAV备份").assertIsDisplayed();compose.onNodeWithText("账号与应用").assertExists()
        capture("settings-light")
    }
    @Test fun rootShellRendersSettingsWithStandardNavigation() {
        activity.setup();val model=ReaderViewModel(activity.get().application)
        val settings=JSONObject().put("theme_mode",1).put("floating_nav",false)
        compose.runOnUiThread {activity.get().setContent {ReviewTheme(settings){ReaderApp(model,ReaderState(authenticating=false,rootTab=2,settings=settings,screens=listOf(ReaderScreen(Feed("Settings",title="设置"),loaded=true))))}}}
        compose.onNodeWithText("偏好与功能").assertIsDisplayed();compose.onNodeWithText("首页").assertIsDisplayed()
        capture("root-settings-light")
    }
    @Test fun originalSliderRetainsAccessibleProgressAction() {
        activity.setup();var value by mutableFloatStateOf(.5f);var committed=false
        compose.runOnUiThread {activity.get().setContent {ReviewTheme(JSONObject().put("theme_mode",1)){Surface {OriginalSlider(value,{value=it},0f..1f,10,{committed=true})}}}}
        compose.onNode(SemanticsMatcher.keyIsDefined(androidx.compose.ui.semantics.SemanticsActions.SetProgress)).performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.SetProgress){it(.8f)}
        compose.runOnIdle {Assert.assertEquals(.8f,value,.001f);Assert.assertTrue(committed)}
    }
    @Test fun sharedSettingsDoNotOverwriteBackgroundWorkerUpdates() {
        activity.setup();val a=AppSettings(activity.get());val b=AppSettings(activity.get())
        a.set("theme_mode",2);b.set("notification_seen_123","[\"one\"]");a.set("haptics",false)
        Assert.assertEquals("[\"one\"]",a.string("notification_seen_123"));Assert.assertEquals(2,b.int("theme_mode"));Assert.assertFalse(b.bool("haptics"))
    }
    @Test fun darkTextTracksAppThemeOnCustomSurfacesAndButtons() {
        activity.setup();var mode by mutableIntStateOf(1);var black by mutableStateOf(false);var palette by mutableIntStateOf(0)
        var foreground=androidx.compose.ui.graphics.Color.Unspecified;var buttonForeground=foreground
        compose.runOnUiThread {activity.get().setContent {ReviewTheme(JSONObject().put("theme_mode",mode).put("key_is_pure_black_dark",black).put("key_theme_color_index",palette)){
            foreground=MaterialTheme.colorScheme.onSurface;buttonForeground=MaterialTheme.colorScheme.onPrimary
            Surface(color=LocalChrome.current.background){Column{Text("主题正文");Glyph("home_outlined","主题图标");Button(onClick={}){Text("主题按钮")}}}
        }}}
        fun color(text:String):androidx.compose.ui.graphics.Color {val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>();compose.onNodeWithText(text).performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult){it(layouts)};if(text=="主题正文")Assert.assertEquals(14f,layouts.single().layoutInput.style.fontSize.value,.001f);return layouts.single().layoutInput.style.color}
        for(index in 0..7)for(theme in listOf(1,2,3)) {
            compose.runOnIdle{palette=index;mode=if(theme==1)1 else 2;black=theme==3}
            compose.waitForIdle();Assert.assertEquals(foreground,color("主题正文"));Assert.assertEquals(buttonForeground,color("主题按钮"))
        }
        capture("theme-black-text")
    }
    @Test fun glassShaderActuallyRefractsAndKeepsTransparentCorners() {
        activity.setup()
        val source=activity.get().assets.open("glass/premium.agsl").bufferedReader().use{it.readText()}.replace("uBackgroundTexture.eval(","sample(uBackgroundTexture, ")
        val input=Bitmap.createBitmap(360,180,Bitmap.Config.ARGB_8888)
        for(y in 0 until 180)for(x in 0 until 360)input.setPixel(x,y,android.graphics.Color.rgb((x*9)%256,(y*7)%256,120))
        // Test-only: let native host Skia rasterize the kernel; this is not an Android GPU check.
        fun render(pinch:Float):Bitmap {
            val shader=android.graphics.RuntimeShader(source)
            GlassStyle(androidx.compose.ui.graphics.Color.Transparent,thickness=20f,refractiveIndex=1.18f,chromatic=.025f,light=2f,rimLight=0f,pinch=pinch,blur=0f,radius=100f).uniforms(360,180,2f,40f,androidx.compose.ui.unit.IntSize(822,1782)).forEach{(name,value)->shader.setFloatUniform(name,value)}
            shader.setInputShader("uBackgroundTexture",android.graphics.BitmapShader(input,android.graphics.Shader.TileMode.CLAMP,android.graphics.Shader.TileMode.CLAMP))
            return Bitmap.createBitmap(360,180,Bitmap.Config.ARGB_8888).also{val canvas=android.graphics.Canvas(it);canvas.javaClass.getMethod("setHwFeaturesInSwModeEnabled",Boolean::class.javaPrimitiveType).invoke(canvas,true);canvas.drawRect(0f,0f,360f,180f,android.graphics.Paint().apply{this.shader=shader})}
        }
        val normal=render(0f);val pinched=render(.7f)
        Assert.assertEquals(0,android.graphics.Color.alpha(normal.getPixel(41,41)))
        Assert.assertEquals(0,android.graphics.Color.alpha(normal.getPixel(180,10)))
        Assert.assertEquals(0,android.graphics.Color.alpha(normal.getPixel(10,90)))
        Assert.assertEquals(255,android.graphics.Color.alpha(normal.getPixel(180,90)))
        var differences=0;for(y in 55..125)for(x in 75..285)if(normal.getPixel(x,y)!=pinched.getPixel(x,y))differences++
        Assert.assertTrue("Pinch must alter real sampled pixels",differences>100)
        val file=File("build/parity/glass-kernel.png");requireNotNull(file.parentFile).mkdirs();file.outputStream().use{pinched.compress(Bitmap.CompressFormat.PNG,100,it)}
    }
    @Test fun darkSettingsWithLiquidBarRemainReadable() {
        activity.setup();val model=ReaderViewModel(activity.get().application)
        val settings=JSONObject().put("theme_mode",2).put("floating_nav",true).put("use_liquid_glass_effect",true)
        compose.runOnUiThread {activity.get().setContent {ReviewTheme(settings){Surface(color=LocalChrome.current.background){ReaderApp(model,ReaderState(authenticating=false,rootTab=2,settings=settings,screens=listOf(ReaderScreen(Feed("Settings",title="设置"),loaded=true))))}}}}
        compose.onNodeWithText("偏好与功能").assertIsDisplayed();compose.onNodeWithText("首页").assertExists()
        val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>();compose.onNodeWithText("个性化").performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult){it(layouts)}
        Assert.assertTrue(layouts.single().layoutInput.style.color.red>.5f)
        capture("settings-dark-liquid")
    }
    @Test fun loggedInFirstFrameAndRootTabTransitionKeepChromeInPlace() {
        activity.setup()
        val model = ReaderViewModel(activity.get().application)
        val settings = JSONObject().put("theme_mode", 2).put("key_is_pure_black_dark", true)
            .put("floating_nav", true).put("use_liquid_glass_effect", true)
        val post = Post("104", User("1", "首屏作者", "reviewx", "", ""), "首屏图层验证", "",
            emptyList(), null, null, "", 0, 0, 0, "", false)
        val posts = listOf(post) + List(7) { post.copy(id = (105 + it).toString(), text = "首屏测试帖子 $it") }
        val home = ReaderState(accountId = "1", authenticating = false, settings = settings,
            screens = listOf(ReaderScreen(posts = posts, loaded = true)))
        var current by mutableStateOf(home)
        compose.setContent {
            ReviewTheme(settings) { Surface { ReaderApp(model, current) } }
        }
        compose.onNodeWithText("ReviewX").assertIsDisplayed()
        compose.onNodeWithContentDescription("打开侧边栏").assertIsDisplayed()
        compose.onNodeWithContentDescription("发布帖子").assertIsDisplayed()
        compose.onNodeWithText("为你推荐").assertIsDisplayed()
        compose.onNodeWithText("正在关注").assertIsDisplayed()
        val title = compose.onNodeWithText("ReviewX").fetchSemanticsNode().boundsInRoot
        val postBounds = compose.onNodeWithText("首屏图层验证").fetchSemanticsNode().boundsInRoot
        val nav = compose.onNodeWithText("首页").fetchSemanticsNode().boundsInRoot
        Assert.assertTrue(postBounds.top > title.bottom)
        val reference = JSONObject(File("../reference/layout/metrics.json").readText())
            .getJSONObject("home-logged-in-dark").getJSONObject("texts")
        val density = activity.get().resources.displayMetrics.density
        Assert.assertEquals(reference.getJSONObject("ReviewX").getDouble("x"), (title.left / density).toDouble(), .5)
        val label = compose.onAllNodesWithText("首页", useUnmergedTree = true).onFirst().fetchSemanticsNode().boundsInRoot
        Assert.assertEquals(reference.getJSONObject("首页").getDouble("y"), (label.top / density).toDouble(), 1.5)
        val screenshot = capture("logged-in-home-black-liquid")
        fun hasColor(bounds: androidx.compose.ui.geometry.Rect, predicate: (Int) -> Boolean): Boolean =
            (bounds.top.toInt() until bounds.bottom.toInt()).any { y ->
                (bounds.left.toInt() until bounds.right.toInt()).any { x -> predicate(screenshot.getPixel(x, y)) }
            }
        Assert.assertTrue("Toolbar title must paint over its backdrop", hasColor(title) {
            android.graphics.Color.red(it) > 200
        })
        val reply = compose.onAllNodesWithContentDescription("回复", useUnmergedTree = true)
            .onFirst().fetchSemanticsNode().boundsInRoot
        Assert.assertTrue("Original dark reply icon has white ink", hasColor(reply) { it == android.graphics.Color.WHITE })

        compose.mainClock.autoAdvance = false
        compose.runOnUiThread {
            current = home.copy(rootTab = 1, screens = listOf(
                ReaderScreen(feed = Feed("Explore", title = "探索", option = "true"), loaded = true)
            ))
        }
        repeat(6) {
            compose.mainClock.advanceTimeByFrame()
            compose.waitForIdle()
        }
        capture("logged-in-explore-transition")
        val search = compose.onNodeWithText("搜索 X", useUnmergedTree = true)
        search.assertIsDisplayed()
        compose.onNodeWithText("ReviewX").assertDoesNotExist()
        val mid = search.fetchSemanticsNode().boundsInRoot
        Assert.assertEquals(nav, compose.onNodeWithText("首页").fetchSemanticsNode().boundsInRoot)
        compose.mainClock.advanceTimeBy(320)
        Assert.assertEquals(mid, search.fetchSemanticsNode().boundsInRoot)
        compose.mainClock.autoAdvance = true
        capture("logged-in-explore-black-liquid")
    }

    @Test fun redNoteWaterNeedsLongPressAndBeginsContractingOnRelease() {
        activity.setup()
        var touching by mutableStateOf(true)
        var longPressed by mutableStateOf(false)
        lateinit var pressure: State<Float>
        compose.setContent { pressure = navigationGlassMotion(0, touching, true, 1f, longPressed).second }
        compose.runOnIdle { Assert.assertEquals(0f, pressure.value, .001f) }
        compose.runOnUiThread { longPressed = true }
        compose.waitForIdle()
        compose.runOnIdle { Assert.assertEquals(1f, pressure.value, .01f) }
        compose.mainClock.autoAdvance = false
        compose.runOnUiThread { touching = false }
        repeat(6) {
            compose.mainClock.advanceTimeByFrame()
            compose.waitForIdle()
        }
        compose.runOnIdle { Assert.assertTrue(pressure.value in .001f..0.999f) }
        compose.mainClock.autoAdvance = true
        compose.waitForIdle()
        compose.runOnIdle { Assert.assertEquals(0f, pressure.value, .001f) }
    }

    @Test fun liquidBarSwitchesTabsOnReleaseWithoutWaitingForDoubleTap() {
        activity.setup()
        var selected = 0
        compose.runOnUiThread {
            activity.get().setContent {
                ReviewTheme(JSONObject()) { LiquidNavigation(0, { selected = it }, {}, 220.dp) }
            }
        }
        compose.onNodeWithText("探索").performTouchInput { click() }
        compose.runOnIdle { Assert.assertEquals(1, selected) }
    }

    @Test fun plainFloatingBarSwitchesOnReleaseAndOnlyDoubleTapsActiveTab() {
        activity.setup()
        var selected by mutableIntStateOf(0)
        val taps = mutableListOf<Int>()
        val refreshes = mutableListOf<Int>()
        compose.setContent {
            ReviewTheme(JSONObject().put("floating_nav", true).put("use_liquid_glass_effect", false)) {
                BottomNavigation(selected, { taps.add(it); selected = it }, { refreshes.add(it) })
            }
        }
        compose.onNodeWithText("探索").assertIsDisplayed()
        compose.mainClock.autoAdvance = false
        // Leave a pending home reselection before the first cross-tab click.
        compose.onNodeWithText("首页").performTouchInput { click() }
        for ((index, label) in listOf(1 to "探索", 2 to "设置", 0 to "首页")) {
            compose.onNodeWithText(label).performTouchInput { click() }
            compose.runOnIdle { Assert.assertEquals(index, selected) }
            compose.mainClock.advanceTimeByFrame()
            compose.waitForIdle()
        }
        compose.mainClock.advanceTimeBy(400L)
        compose.runOnIdle {
            Assert.assertEquals(listOf(1, 2, 0), taps)
            Assert.assertTrue(refreshes.isEmpty())
        }
        compose.onNodeWithText("首页").performTouchInput { doubleClick() }
        compose.mainClock.advanceTimeBy(400L)
        compose.runOnIdle {
            Assert.assertEquals(listOf(1, 2, 0), taps)
            Assert.assertEquals(listOf(0), refreshes)
        }
        compose.mainClock.autoAdvance = true
    }
    @Test fun liquidDropHapticsFireOnceOnLongPressAndRespectCancellationAndSetting() {
        activity.setup()
        var enabled by mutableStateOf(true)
        val events = mutableListOf<HapticFeedbackType>()
        val feedback = object : HapticFeedback {
            override fun performHapticFeedback(hapticFeedbackType: HapticFeedbackType) {
                events.add(hapticFeedbackType)
            }
        }
        compose.setContent {
            CompositionLocalProvider(LocalHapticFeedback provides feedback) {
                ReviewTheme(JSONObject().put("haptics", enabled)) {
                    LiquidNavigation(0, {}, {}, 220.dp)
                }
            }
        }
        val tab = compose.onNodeWithText("首页")
        compose.mainClock.autoAdvance = false
        tab.performTouchInput { down(center) }
        compose.mainClock.advanceTimeBy(120)
        compose.runOnIdle { Assert.assertTrue(events.isEmpty()) }
        compose.mainClock.advanceTimeBy(200)
        compose.runOnIdle { Assert.assertEquals(listOf(HapticFeedbackType.LongPress), events) }
        compose.mainClock.advanceTimeBy(250)
        tab.performTouchInput { up() }
        tab.performTouchInput { down(center); cancel() }
        compose.mainClock.advanceTimeBy(280)
        tab.performTouchInput { down(center); moveBy(Offset(0f, 70f)) }
        compose.mainClock.advanceTimeBy(280)
        tab.performTouchInput { up() }
        compose.runOnIdle {
            Assert.assertEquals(listOf(HapticFeedbackType.LongPress), events)
            enabled = false
        }
        compose.mainClock.advanceTimeByFrame()
        tab.performTouchInput { down(center) }
        compose.mainClock.advanceTimeBy(280)
        tab.performTouchInput { up() }
        compose.runOnIdle { Assert.assertEquals(listOf(HapticFeedbackType.LongPress), events) }
        compose.mainClock.autoAdvance = true
    }

    @Test fun galleryRetapCanCrossReturnEndpointAndStillHandOffToPageSwipe() {
        activity.setup()
        val model = ReaderViewModel(activity.get().application)
        var showing by mutableStateOf(true)
        var dismissals = 0
        val events = mutableListOf<HapticFeedbackType>()
        val feedback = object : HapticFeedback {
            override fun performHapticFeedback(hapticFeedbackType: HapticFeedbackType) {
                events.add(hapticFeedbackType)
            }
        }
        val source = androidx.compose.ui.geometry.Rect(0f, 60f, 300f, 620f)
        val request = GalleryRequest(
            List(2) { Media("", "", false) }, 0, "",
            sourceAnchor = { GalleryAnchor(source, source) },
            sourceScope = Any(),
            sourceImage = androidx.compose.ui.graphics.ImageBitmap(120, 120),
        )
        compose.setContent {
            CompositionLocalProvider(LocalHapticFeedback provides feedback) {
                ReviewTheme(JSONObject()) {
                    Box(Modifier.fillMaxSize()) {
                        if (showing) MediaGallery(request, model) {
                            dismissals++
                            showing = false
                        }
                    }
                }
            }
        }
        compose.onNodeWithContentDescription("返回").assertIsDisplayed()
        compose.mainClock.autoAdvance = false
        val dialog = compose.onNode(isDialog())
        val target = Offset(100f, 260f)
        for (delayBeforePress in listOf(64L, 144L, 176L)) {
            compose.onNodeWithContentDescription("返回").performClick()
            compose.runOnIdle { events.clear() }
            compose.mainClock.advanceTimeBy(delayBeforePress)
            dialog.performTouchInput { down(target) }
            compose.mainClock.advanceTimeBy(112)
            compose.runOnIdle {
                Assert.assertEquals(0, dismissals)
                Assert.assertTrue(events.isEmpty())
            }
            dialog.performTouchInput { up() }
            compose.runOnIdle { Assert.assertEquals(listOf(HapticFeedbackType.VirtualKey), events) }
            compose.mainClock.advanceTimeBy(550)
            compose.onNodeWithContentDescription("返回").assertIsDisplayed()
        }
        compose.onNodeWithContentDescription("返回").performClick()
        compose.mainClock.advanceTimeBy(144)
        dialog.performTouchInput { click(target) }
        compose.mainClock.advanceTimeBy(48)
        dialog.performTouchInput {
            swipe(Offset(width * .79f, height * .45f), Offset(width * .18f, height * .45f))
        }
        compose.mainClock.advanceTimeBy(800)
        compose.onNodeWithText("2 / 2").assertIsDisplayed()
        compose.runOnIdle {
            Assert.assertEquals(0, dismissals)
            Assert.assertFalse(request.flight.active)
            Assert.assertEquals(1, request.flight.index)
        }
        dialog.performTouchInput {
            swipe(Offset(width * .18f, height * .45f), Offset(width * .18f, height * .65f))
        }
        compose.mainClock.advanceTimeBy(800)
        compose.onNodeWithText("2 / 2").assertIsDisplayed()
        compose.onNodeWithContentDescription("返回").performClick()
        compose.runOnIdle { events.clear() }
        compose.mainClock.advanceTimeBy(144)
        dialog.performTouchInput { down(target) }
        compose.mainClock.advanceTimeBy(112)
        dialog.performTouchInput { cancel() }
        compose.mainClock.advanceTimeBy(100)
        compose.runOnIdle {
            Assert.assertEquals(1, dismissals)
            Assert.assertTrue(events.isEmpty())
        }
        compose.mainClock.autoAdvance = true
    }
    @Test fun settingsGeometryMatchesExportedFlutterLayout() {
        activity.setup();val model=ReaderViewModel(activity.get().application);val settings=JSONObject().put("theme_mode",1)
        compose.runOnUiThread {activity.get().setContent {ReviewTheme(settings){Surface {SettingsHome(model,ReaderState(authenticating=false,settings=settings))}}}}
        val reference=JSONObject(File("../reference/layout/metrics.json").readText()).getJSONObject("settings-light").getJSONObject("texts")
        val density=activity.get().resources.displayMetrics.density
        fun bounds(text:String)=compose.onNodeWithText(text,useUnmergedTree=true).fetchSemanticsNode().boundsInRoot
        val anchor=bounds("偏好与功能")
        for(text in listOf("个性化","帖子与阅读样式","网络设置","订阅消息提醒","存储与备份","缓存管理","WebDAV备份","账号与应用")) {
            val expected=reference.getJSONObject(text);val actual=bounds(text)
            Assert.assertEquals("$text horizontal",expected.getDouble("x")-32.0,((actual.left-anchor.left)/density).toDouble(),1.0)
            Assert.assertEquals("$text vertical",expected.getDouble("y")-20.0,((actual.top-anchor.top)/density).toDouble(),1.5)
        }
    }
    @Test fun themeSwitchesAndChipsKeepFlutterSectionPositions() {
        activity.setup();val model=ReaderViewModel(activity.get().application);val settings=JSONObject().put("theme_mode",1)
        compose.runOnUiThread {activity.get().setContent {ReviewTheme(settings){Surface {Column{AppTopBar("个性化",leadingWidth=16);ThemeSettings(model,ReaderState(authenticating=false,settings=settings))}}}}}
        val reference=JSONObject(File("../reference/layout/metrics.json").readText()).getJSONObject("theme-light").getJSONObject("texts")
        val density=activity.get().resources.displayMetrics.density
        fun top(text:String)=compose.onNodeWithText(text,useUnmergedTree=true).fetchSemanticsNode().boundsInRoot.top/density
        val anchor=top("明暗模式")
        for(text in listOf("色彩方案","字体粗细"))Assert.assertEquals(text,reference.getJSONObject(text).getDouble("y")-reference.getJSONObject("明暗模式").getDouble("y"),(top(text)-anchor).toDouble(),2.0)
    }
    @Test fun videoMenuTextIsWhiteEvenInLightAppTheme() {
        activity.setup()
        compose.runOnUiThread {activity.get().setContent {ReviewTheme(JSONObject().put("theme_mode",1)){Surface(color=androidx.compose.ui.graphics.Color(0xFF212121)){VideoMenuRow("1.0X",false){}}}}}
        val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>();compose.onNodeWithText("1.0X").performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult){it(layouts)}
        Assert.assertEquals(androidx.compose.ui.graphics.Color.White,layouts.single().layoutInput.style.color)
        capture("video-menu-light-theme")
    }
    @Test fun migratedPagesRenderWithOriginalFixtures() {
        activity.setup();val model=ReaderViewModel(activity.get().application)
        var page by mutableStateOf("network");var dark by mutableStateOf(false)
        val post=Post("123",User("1","显示对照","reviewx","","",verified=true),"同一条正文，用于对照布局。","",emptyList(),null,null,"",128,24,12,"",false,views=2048)
        compose.runOnUiThread {activity.get().setContent {
            val settings=JSONObject().put("theme_mode",if(dark)2 else 1)
            ReviewTheme(settings){Surface(color=LocalChrome.current.background){CompositionLocalProvider(LocalActions provides UiActions(model,{},{},{})){
                Column {if(page!="post"&&page!="login")AppTopBar(when(page){"reading"->"帖子与阅读样式";"cache"->"缓存管理";"account"->"账号管理";"display"->"屏幕刷新率";"network"->"网络设置";"diagnostics"->"诊断日志";"storage"->"存储设置";"webdav"->"WebDAV 云端备份与恢复";"notification-settings"->"订阅消息提醒";"history-empty"->"本机浏览历史";else->"个性化"},leadingWidth=16)
                    when(page){"reading"->ReadingSettings(model);"cache"->CacheSettings(model);"account"->AccountSettings(model,ReaderState(authenticating=false,settings=settings));"display"->DisplaySettings(model,ReaderState(authenticating=false,settings=settings));"webdav"->WebDavSettings(model);"notification-settings"->NotificationSettings(model,ReaderState(authenticating=false,settings=settings));"history-empty"->HistoryScreen(model,ReaderState(authenticating=false,settings=settings));"network"->NetworkSettings(model);"diagnostics"->DiagnosticsSettings(model);"storage"->StorageSettings(model,ReaderState(authenticating=false,settings=settings));"theme"->ThemeSettings(model,ReaderState(authenticating=false,settings=settings));"login"->LoginScreen(model,ReaderState(authenticating=false,settings=settings));else->Box(Modifier.fillMaxSize()){PostCard(post)}}
                }
            }}}
        }}
        for(theme in listOf(false,true))for(name in listOf("network","diagnostics","storage","theme","login","post","webdav","notification-settings","history-empty","reading","cache","account","display")){
            compose.runOnIdle{page=name;dark=theme};compose.waitForIdle()
            if (name == "webdav") {
                compose.onNodeWithText("全量安全备份").assertIsSelected()
                compose.onNodeWithText("不含会话及 WebDAV 密码").assertIsDisplayed()
                compose.onNodeWithText("含明文凭据，请妥善保管", substring = true).assertIsDisplayed()
            }
            if(name=="cache"){
                compose.waitUntil(10000){compose.onAllNodesWithText("图片与媒体").fetchSemanticsNodes().isNotEmpty()}
                val reference=JSONObject(File("../reference/layout/metrics.json").readText()).getJSONObject("cache-light").getJSONObject("texts")
                val density=activity.get().resources.displayMetrics.density
                val top=compose.onNodeWithText("自动清理规则",useUnmergedTree=true).fetchSemanticsNode().boundsInRoot.top/density
                Assert.assertEquals(reference.getJSONObject("自动清理规则").getDouble("y"),top.toDouble(),2.0)
            }
            capture("$name-${if(theme)"dark"else "light"}")
            compose.onAllNodes(isRoot()).assertCountEquals(1)
        }
    }
    @Test fun aboutDialogRetainsOriginalLinkAndDismissal() {
        activity.setup();val model=ReaderViewModel(activity.get().application);var open by mutableStateOf(true)
        compose.runOnUiThread {activity.get().setContent {ReviewTheme(JSONObject().put("theme_mode",2)){CompositionLocalProvider(LocalActions provides UiActions(model,{},{},{})){if(open)AboutDialog{open=false}}}}}
        compose.onNodeWithText("GitHub 开源地址").assertIsDisplayed();compose.onNodeWithText("github.com/Chengeeker/ReviewX").assertIsDisplayed()
        val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>();compose.onNodeWithText("GitHub 开源地址",useUnmergedTree=true).performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult){it(layouts)}
        Assert.assertEquals(13f,layouts.single().layoutInput.style.fontSize.value,.001f)
        capture("about-dark",dialog=true)
        compose.onNodeWithText("我知道了").performClick();compose.onNodeWithText("GitHub 开源地址").assertDoesNotExist()
    }
    @Test fun drawerMatchesFlutterGeometryAndRoutes() {
        activity.setup();var route="";var profile=false
        compose.runOnUiThread {activity.get().setContent {ReviewTheme(JSONObject().put("theme_mode",1)){Surface(Modifier.width(280.dp)){OriginalDrawer(ReaderState(authenticating=false),{profile=true},{kind,_->route=kind})}}}}
        val reference=JSONObject(File("../reference/layout/metrics.json").readText()).getJSONObject("drawer-light").getJSONObject("texts")
        val density=activity.get().resources.displayMetrics.density
        fun bounds(text:String)=compose.onNodeWithText(text,useUnmergedTree=true).fetchSemanticsNode().boundsInRoot
        capture("drawer-light")
        val anchor=bounds("未登录 / 访客")
        for(text in listOf("历史","通知","本机浏览历史")){
            val expected=reference.getJSONObject(text);val actual=bounds(text)
            Assert.assertEquals("$text x",expected.getDouble("x"),(actual.left/density).toDouble(),1.0)
            Assert.assertEquals("$text y",expected.getDouble("y")-reference.getJSONObject("未登录 / 访客").getDouble("y"),((actual.top-anchor.top)/density).toDouble(),1.5)
        }
        compose.onNodeWithText("本机浏览历史").performClick();Assert.assertEquals("LocalHistory",route)
        compose.onNodeWithText("未登录 / 访客").performClick();Assert.assertTrue(profile)
        capture("drawer-light")
    }
    @Test fun requestAndFooterStatesKeepOriginalMessagesAndActions() {
        activity.setup();var screen by mutableStateOf(ReaderScreen(loaded=true));var retries=0
        compose.runOnUiThread {activity.get().setContent {ReviewTheme(JSONObject().put("theme_mode",2)){Surface {Column{RequestStatus(screen.busy,screen.error){retries++};OriginalListFooter(screen,screen.feed.kind=="Followers"){retries++}}}}}}
        compose.onNodeWithText("暂无帖子，下拉刷新").assertIsDisplayed()
        compose.runOnIdle{screen=screen.copy(busy=true)}
        compose.onNodeWithText("正在连接 X… 若等待较久，请检查 VPN 或代理").assertIsDisplayed();compose.onNodeWithText("暂无帖子，下拉刷新").assertDoesNotExist()
        compose.runOnIdle{screen=screen.copy(busy=false,error="连接失败，请重试",cursor="next")}
        compose.onNodeWithText("重试").performClick();compose.onNodeWithText("重试加载").performClick();Assert.assertEquals(2,retries)
        capture("request-error-dark")
        compose.runOnIdle{screen=ReaderScreen(Feed("Followers"),loaded=true)};compose.onNodeWithText("没有用户").assertIsDisplayed()
        compose.runOnIdle{screen=ReaderScreen(Feed("NotificationsTimeline"),loaded=true)};compose.onNodeWithText("暂无通知").assertIsDisplayed()
    }
    @Test fun detailFailureUsesOriginalRetryAndChipKeepsThemeText() {
        activity.setup();var failed by mutableStateOf(true);var retried=false
        compose.runOnUiThread {activity.get().setContent {ReviewTheme(JSONObject().put("theme_mode",2)){Surface {if(failed)DetailLoading("请求失败"){retried=true}else FlutterLabelChip("2.0X 倍速快进中")}}}}
        compose.onNodeWithText("重试").performClick();Assert.assertTrue(retried)
        compose.runOnIdle{failed=false};compose.onNodeWithText("2.0X 倍速快进中").assertIsDisplayed();capture("video-chip-dark")
    }
    @Test fun quoteComposerKeepsCounterBesideHelper() {
        activity.setup();val model=ReaderViewModel(activity.get().application)
        val post=Post("123",User("1","显示对照","reviewx","",""),"原版引用内容","",emptyList(),null,null,"",0,0,0,"",false)
        compose.runOnUiThread {activity.get().setContent {ReviewTheme(JSONObject().put("theme_mode",1)){CompositionLocalProvider(LocalActions provides UiActions(model,{},{},{})){ComposerScreen(ComposeRequest(quote=post),model){}}}}}
        val helper=compose.onNodeWithText("本页发布文字，X 会校验账号对应的长度限制",useUnmergedTree=true).fetchSemanticsNode().boundsInRoot
        val count=compose.onNodeWithText("0/10000",useUnmergedTree=true).fetchSemanticsNode().boundsInRoot
        Assert.assertEquals(helper.top,count.top,2f);Assert.assertTrue(count.left>=helper.right)
        compose.onNode(hasSetTextAction()).performTextInput("输入字体核对")
        val inputLayouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
        compose.onNode(hasSetTextAction()).performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult){it(inputLayouts)}
        Assert.assertEquals(16f,inputLayouts.single().layoutInput.style.fontSize.value,.001f)
        compose.onNode(hasSetTextAction()).performTextClearance()
        capture("composer-light",dialog=true)
    }
    @Test fun startupFailureAndExpiredSessionRetainOriginalRecoveryUi() {
        activity.setup();val model=ReaderViewModel(activity.get().application);var startup by mutableStateOf(true)
        compose.runOnUiThread {activity.get().setContent {ReviewTheme(JSONObject().put("theme_mode",2)){Surface(Modifier.fillMaxSize()){if(startup)ReaderApp(model,ReaderState(authenticating=false,startupError="恢复失败"))else ExpiredSessionBanner{}}}}}
        compose.onNodeWithText("恢复失败").assertIsDisplayed();compose.onNodeWithText("清除登录信息").assertIsDisplayed();compose.onNodeWithText("首页").assertDoesNotExist()
        compose.runOnIdle{startup=false};compose.onNodeWithText("X 会话已过期，请重新登录").assertIsDisplayed();compose.onNodeWithText("重新登录").assertHasClickAction();capture("expired-dark")
    }
    @Test fun failedImageOffersOriginalReloadAction() {
        activity.setup()
        compose.runOnUiThread {activity.get().setContent {ReviewTheme(JSONObject().put("theme_mode",1)){Surface(Modifier.size(160.dp)){NetworkImage("","测试图",Modifier.fillMaxSize())}}}}
        compose.waitUntil(5000){compose.onAllNodesWithText("Failed to load image").fetchSemanticsNodes().isNotEmpty()}
        compose.onNodeWithText("Failed to load image").performClick()
        compose.waitUntil(5000){compose.onAllNodesWithText("Failed to load image").fetchSemanticsNodes().isNotEmpty()}
        capture("image-error-light")
    }
    @Test fun progressRetainsFlutterSizeAndAccessibilityWhenConstrained() {
        activity.setup()
        compose.runOnUiThread {activity.get().setContent {ReviewTheme(JSONObject()){Column{FlutterProgress();FlutterProgress(Modifier.size(18.dp),strokeWidth=2.dp)}}}}
        val nodes=compose.onAllNodes(SemanticsMatcher.keyIsDefined(androidx.compose.ui.semantics.SemanticsProperties.ProgressBarRangeInfo)).fetchSemanticsNodes()
        val density=activity.get().resources.displayMetrics.density
        Assert.assertEquals(2,nodes.size);Assert.assertEquals(36f,nodes[0].boundsInRoot.width/density,.01f);Assert.assertEquals(18f,nodes[1].boundsInRoot.width/density,.01f)
        nodes.forEach{Assert.assertEquals(androidx.compose.ui.semantics.ProgressBarRangeInfo.Indeterminate,it.config[androidx.compose.ui.semantics.SemanticsProperties.ProgressBarRangeInfo])}
    }
    @Test fun composerCountsVisibleCharactersAndWebDavShowsFieldValidation() {
        Assert.assertEquals(3,composerText("A👍🏽e\u0301").second)
        val limited=composerText("x".repeat(9999)+"😀"+"y");Assert.assertEquals(10000,limited.second);Assert.assertTrue(limited.first.endsWith("😀"))
        Assert.assertEquals(setOf("url","user","password"),webDavFormErrors("","","").keys)
        Assert.assertTrue(webDavFormErrors("https://example.com/dav/","user","secret").isEmpty())
        Assert.assertEquals(setOf("url"),webDavFormErrors("https://user@example.com/?token=1","user","secret").keys)
    }
    @Test fun postDatesUseTheSameTemporalTypeForRelativeTime() {
        val recent=java.time.Instant.now().minusSeconds(310)
        val settings=JSONObject().put("relativeTime",true)
        Assert.assertEquals("5 分钟前",postTime(recent.toString(),settings))
        val legacy=recent.atZone(java.time.ZoneOffset.UTC).format(java.time.format.DateTimeFormatter.ofPattern("EEE MMM dd HH:mm:ss Z yyyy",java.util.Locale.US))
        Assert.assertEquals("5 分钟前",postTime(legacy,settings))
        Assert.assertEquals("2020-01-02 03:04:05 UTC",postTime("2020-01-02T03:04:05Z",JSONObject().put("utcTime",true).put("showYear",true).put("showSeconds",true)))
        Assert.assertEquals("",postTime("invalid",settings))
    }
    @Test fun cacheThresholdDialogKeepsFlutterDenseRows() {
        Assert.assertEquals("1.00 GB",formatBytes(1073741824))
        Assert.assertEquals("1.5 KB",formatBytes(1536))
        activity.setup();val model=ReaderViewModel(activity.get().application)
        compose.runOnUiThread {activity.get().setContent {ReviewTheme(JSONObject().put("theme_mode",1)){Surface{CacheSettings(model)}}}}
        compose.waitUntil(10000){compose.onAllNodesWithText("自动清理缓存阈值").fetchSemanticsNodes().any{it.config.contains(androidx.compose.ui.semantics.SemanticsActions.OnClick)}}
        compose.onNodeWithText("自动清理缓存阈值").performClick()
        compose.onNodeWithText("选择自动清理阈值").assertIsDisplayed()
        val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
        compose.onNodeWithText("50 MB",useUnmergedTree=true).performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult){it(layouts)}
        Assert.assertEquals(13f,layouts.single().layoutInput.style.fontSize.value,.001f)
        val density=activity.get().resources.displayMetrics.density
        fun top(text:String)=compose.onNodeWithText(text,useUnmergedTree=true).fetchSemanticsNode().boundsInRoot.top/density
        val reference=JSONObject(File("../reference/layout/metrics.json").readText()).getJSONObject("cache-threshold-light").getJSONObject("texts")
        Assert.assertEquals(reference.getJSONObject("100 MB").getDouble("y")-reference.getJSONObject("50 MB").getDouble("y"),(top("100 MB")-top("50 MB")).toDouble(),.5)
        val dialogWidth=requireNotNull(org.robolectric.shadows.ShadowDialog.getLatestDialog().window).decorView.width/density
        val dialogOffset=(411f-dialogWidth)/2
        Assert.assertEquals(reference.getJSONObject("选择自动清理阈值").getDouble("x"),(dialogOffset+compose.onNodeWithText("选择自动清理阈值",useUnmergedTree=true).fetchSemanticsNode().boundsInRoot.left/density).toDouble(),1.0)
        Assert.assertEquals(reference.getJSONObject("取消").getDouble("x"),(dialogOffset+compose.onNodeWithText("取消",useUnmergedTree=true).fetchSemanticsNode().boundsInRoot.left/density).toDouble(),1.0)
        capture("cache-threshold-light",dialog=true)
        compose.onNodeWithText("取消").performClick();compose.onNodeWithText("选择自动清理阈值").assertDoesNotExist()
    }
    @Test fun specifiedLineBoxesAndTileBaselinesScaleWithoutOverlap() {
        activity.setup();var scale by mutableFloatStateOf(1f);var expectedLine=0f;var expectedTitle=0f;var expectedSubtitle=0f
        compose.runOnUiThread {activity.get().setContent {ReviewTheme(JSONObject().put("theme_mode",1)){
            val density=androidx.compose.ui.platform.LocalDensity.current
            CompositionLocalProvider(androidx.compose.ui.platform.LocalDensity provides androidx.compose.ui.unit.Density(density.density,scale)){
                with(androidx.compose.ui.platform.LocalDensity.current){expectedLine=27.94.sp.toDp().value;expectedTitle=20.25.sp.toDp().value;expectedSubtitle=17.5.sp.toDp().value}
                Surface {Column(Modifier.width(280.dp)){
                    Box(Modifier.testTag("line-box")){Text("导出诊断日志",Modifier.flutterLineHeight(MaterialTheme.typography.titleLarge.lineHeight),style=MaterialTheme.typography.titleLarge)}
                    SettingRow("图片存储路径","Pictures/ReviewX/",titleStyle=flutterTileTitle().copy(fontSize=16.sp,lineHeight=21.6.sp),subtitleStyle=flutterTileSubtitle().copy(fontSize=14.sp,lineHeight=19.6.sp))
                    Box(Modifier.testTag("multiline-tile")){SettingRow("多行标题需要在窄屏中完整显示，不能被固定高度裁切","较长的副标题也需要自动换行并避开前面的标题")}
                }}
            }
        }}}
        val density=activity.get().resources.displayMetrics.density
        for(fontScale in listOf(.8f,1f,1.4f,2f)) {
            compose.runOnIdle{scale=fontScale};compose.waitForIdle()
            Assert.assertEquals(expectedLine,compose.onNodeWithTag("line-box").fetchSemanticsNode().boundsInRoot.height/density,.6f)
            fun lineBox(text:String,height:Float):Float {
                val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
                compose.onNodeWithText(text,useUnmergedTree=true).performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult){it(layouts)}
                val result=layouts.single()
                return (result.lastBaseline-result.firstBaseline)/density+height
            }
            val minimum=lineBox("多行标题需要在窄屏中完整显示，不能被固定高度裁切",expectedTitle)+lineBox("较长的副标题也需要自动换行并避开前面的标题",expectedSubtitle)+22f
            Assert.assertTrue(compose.onNodeWithTag("multiline-tile").fetchSemanticsNode().boundsInRoot.height/density>=minimum-1f)
        }
    }
    private fun capture(name:String,dialog:Boolean=false):Bitmap {
        compose.waitForIdle()
        val view=if(dialog)requireNotNull(org.robolectric.shadows.ShadowDialog.getLatestDialog().window).decorView else activity.get().window.decorView
        val bitmap=Bitmap.createBitmap(view.width,view.height,Bitmap.Config.ARGB_8888)
        compose.runOnUiThread {view.draw(android.graphics.Canvas(bitmap))}
        val file=File("build/parity/$name.png");requireNotNull(file.parentFile).mkdirs();file.outputStream().use{bitmap.compress(Bitmap.CompressFormat.PNG,100,it)}
        Assert.assertTrue(bitmap.width>0 && bitmap.height>0)
        val density=activity.get().resources.displayMetrics.density;val texts=JSONObject()
        compose.onAllNodes(SemanticsMatcher.keyIsDefined(androidx.compose.ui.semantics.SemanticsProperties.Text),useUnmergedTree=true).fetchSemanticsNodes().forEach{node->
            val text=node.config[androidx.compose.ui.semantics.SemanticsProperties.Text].joinToString(""){it.text};val r=node.boundsInRoot
            val layouts=mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
            node.config.getOrNull(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult)?.action?.invoke(layouts)
            val style=layouts.firstOrNull()?.layoutInput?.style
            texts.put(text,JSONObject().put("x",r.left/density).put("y",r.top/density).put("width",r.width/density).put("height",r.height/density).put("fontSize",style?.fontSize?.value?.takeIf{it.isFinite()}).put("lineHeight",style?.lineHeight?.value?.takeIf{it.isFinite()}).put("lineHeightStyle",style?.lineHeightStyle.toString()).put("platformStyle",style?.platformStyle.toString()))
        }
        File("build/parity/$name.json").writeText(texts.toString(2))
        return bitmap
    }
}
