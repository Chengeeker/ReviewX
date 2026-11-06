@file:OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)

package com.review.x

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.os.Build
import androidx.activity.ComponentActivity
import androidx.activity.compose.*
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.*
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.foundation.pager.*
import androidx.compose.foundation.interaction.collectIsDraggedAsState
import androidx.compose.foundation.*
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.foundation.shape.*
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.*
import androidx.compose.ui.*
import androidx.compose.ui.draw.*
import androidx.compose.ui.layout.*
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.platform.*
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.*
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.*
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.*

class MainActivity:ComponentActivity() {
    private var pendingIntent by mutableStateOf<Intent?>(null)
    override fun onCreate(savedInstanceState:Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        pendingIntent=intent
        DiagnosticLog.initialize(this)
        AppNetwork.initialize(this)
        setContent {
            val model:ReaderViewModel=viewModel();val state by model.state.collectAsStateWithLifecycle()
            ReviewTheme(state.settings) {
                val scaffold = LocalChrome.current.background
                LaunchedEffect(scaffold) { window.applyReaderWindow(scaffold) }
                LaunchedEffect(pendingIntent,state.authenticating) {
                    if(!state.authenticating) { pendingIntent?.let { incoming ->
                        if(incoming.action==Intent.ACTION_VIEW) incoming.dataString?.let(model::handleLink)
                        else if(incoming.getBooleanExtra("open_notifications",false)) model.handleLink("https://x.com/notifications")
                    };pendingIntent=null }
                }
                LaunchedEffect(state.settings.optInt("refresh_rate")) { val mode=state.settings.optInt("refresh_rate");window.attributes=window.attributes.apply { preferredDisplayModeId=mode } }
                Box(Modifier.fillMaxSize().background(scaffold)) { ReaderApp(model,state) }
            }
        }
    }
    override fun onNewIntent(intent:Intent) { super.onNewIntent(intent);setIntent(intent);pendingIntent=intent }
}

data class GalleryRequest(val media:List<Media>,val index:Int,val author:String,val post:Post?=null,
    val sourceAnchor:((Int)->GalleryAnchor?)?=null,val sourceRadius:Float=16f,val sourceCovers:Boolean=true,
    val sourceScope:Any?=null,val sourceImage:ImageBitmap?=null,
    val flight:GalleryFlightState=GalleryFlightState(sourceScope,sourceImage,index)) {
    val openingAnchor = sourceAnchor?.invoke(index)
}
data class ComposeRequest(val reply:Post?=null,val quote:Post?=null)
class UiActions(val model:ReaderViewModel,val gallery:(GalleryRequest)->Unit,val compose:(ComposeRequest)->Unit,val link:(String)->Unit)
val LocalActions=staticCompositionLocalOf<UiActions> { error("Reader UI is required") }

@OptIn(ExperimentalMaterial3Api::class,ExperimentalFoundationApi::class)
@Composable fun ReaderApp(model:ReaderViewModel,state:ReaderState) {
    if (state.restoring) return
    if (state.startupError != null) {
        Column(Modifier.fillMaxWidth().statusBarsPadding(), horizontalAlignment = Alignment.CenterHorizontally) {
            RequestStatus(false, state.startupError, model::restore)
            FlutterTextButton(onClick = model::logout) { Text("清除登录信息") }
        }
        return
    }
    val context=LocalContext.current;val scope=rememberCoroutineScope();val drawer=rememberDrawerState(DrawerValue.Closed)
    val snackbar=remember { SnackbarHostState() };var gallery by remember { mutableStateOf<GalleryRequest?>(null) };var composer by remember { mutableStateOf<ComposeRequest?>(null) }
    val actions=remember(model) { UiActions(model,{ gallery=it },{ composer=it },{ url ->
        if(DeepLinks.parse(url)?.kind !in listOf(null,"other")) model.handleLink(url)
        else runCatching { NativeServices.open(context,url) }.onFailure { model.message("无法打开链接，请检查是否安装浏览器") }
    }) }
    LaunchedEffect(state.message) { state.message?.let { snackbar.showSnackbar(it);model.message(null) } }
    var clearHistory by remember {mutableStateOf(false)}
    val root=state.screens.size==1;val lists=remember { linkedMapOf<String,LazyListState>() };val list=lists.getOrPut(listKey(state.screen)) { LazyListState() };if(lists.size>32)lists.remove(lists.keys.first())
    val previousPositions=remember {mutableMapOf<String,Pair<Int,Int>>()}
    val saved=key(state.accountId){rememberSaveableStateHolder()};val searchUi=remember {SearchUi()}
    LaunchedEffect(state.accountId){gallery=null;composer=null;lists.clear();previousPositions.clear();searchUi.query="";searchUi.focused=false;searchUi.users=emptyList();drawer.close()}
    val activeScreenKeys by rememberUpdatedState(state.screens.map{it.key}.toSet())
    val density=LocalDensity.current
    BackHandler(drawer.isOpen || !root) { if(drawer.isOpen)scope.launch { drawer.close() } else model.back() }
    CompositionLocalProvider(LocalActions provides actions,LocalGalleryFlight provides gallery?.flight) {
        ModalNavigationDrawer(drawerState=drawer,gesturesEnabled=root && state.rootTab==0,drawerContent={
            ModalDrawerSheet(Modifier.width(280.dp),drawerContainerColor=LocalChrome.current.background) {
                OriginalDrawer(state,onProfile={scope.launch {drawer.close()};model.openOwnProfile()},onRoute={kind,title->
                    val feed=if(!state.loggedIn&&kind!="LocalHistory")Feed("Login",title="账号登录")else Feed(kind,title=title,option=if(kind=="Bookmarks")"account_history"else "")
                    model.open(feed);scope.launch {drawer.close()}
                })
            }
        }) {
            Box(Modifier.fillMaxSize().clipToBounds()) {
                val liveState = state
                val direction = if (LocalLayoutDirection.current == LayoutDirection.Rtl) -1 else 1
                val easing = CubicBezierEasing(.215f, .61f, .355f, 1f)
                AnimatedContent(
                    targetState = state,
                    contentKey = { if (it.screens.size == 1) "root" else it.screen.key },
                    modifier = Modifier.fillMaxSize(),
                    transitionSpec = {
                        if (targetState.screens.size < initialState.screens.size) {
                            (EnterTransition.None togetherWith slideOutHorizontally(
                                tween(220, easing = CubicBezierEasing(.55f, .055f, .675f, .19f))
                            ) { it * direction }).apply { targetContentZIndex = -1f }.using(null)
                        } else {
                            (slideInHorizontally(tween(320, easing = easing)) { it * direction }
                                togetherWith ExitTransition.None).using(null)
                        }
                    },
                    label = "routes",
                ) { entry ->
                    val currentRoute = if (liveState.screens.size == 1) "root" else liveState.screen.key
                    val entryRoute = if (entry.screens.size == 1) "root" else entry.screen.key
                    val state = if (currentRoute == entryRoute) liveState else entry
                    val root = state.screens.size == 1
                    val profile = state.screen.profile
                    val list = lists.getOrPut(listKey(state.screen)) { LazyListState() }
                    val frosted = (root && state.rootTab != 2) ||
                        state.screen.feed.kind in setOf("Reading", "Storage", "Cache", "WebDAV", "Diagnostics", "NotificationsTimeline", "LocalHistory") ||
                        state.screen.feed.option == "account_history"
                    val floating = state.settings.optBoolean("floating_nav", true)
                    val sample = frosted || root && floating && state.settings.optBoolean("use_liquid_glass_effect")
                    val backdrop = rememberBackdrop()
                    val statusInset = WindowInsets.statusBarsIgnoringVisibility.asPaddingValues().calculateTopPadding()
                    val navigationInsets = WindowInsets.navigationBarsIgnoringVisibility
                    val navInset = if (root && !floating)
                        68.dp + navigationInsets.asPaddingValues().calculateBottomPadding() else 0.dp

                    CompositionLocalProvider(LocalBackdrop provides backdrop) {
                        Box(Modifier.fillMaxSize().background(LocalChrome.current.background)) {
                            ReaderPageLayout(
                                overlap = root || frosted && state.screen.feed.kind != "Reading",
                                bottomInset = navInset,
                                header = {
                                    HeaderSurface(frosted) {
                                    if(root && state.rootTab==2) SettingsStatusBar()
                                    else if(state.screen.feed.kind!="Login") AppTopBar(if(root && state.rootTab==0) "ReviewX" else if(state.screen.feed.kind=="WebDAV")"WebDAV 云端备份与恢复"else state.screen.feed.title,
                                        height=if(profile!=null)with(density){56.sp.toDp().value}.coerceIn(56f,112f).toInt()else if(root && state.rootTab==0 && state.loggedIn)48 else 56,transparent=frosted,leadingWidth=if(root&&state.rootTab==1)16 else 56,titleSpacing=if(root&&state.rootTab==1)0.dp else 16.dp,
                                        leading={ if(root && state.rootTab==0) IconButton(onClick={ scope.launch { drawer.open() } }) { if(!state.user?.avatar.isNullOrEmpty()) Avatar(state.user,32) else Glyph("menu_rounded","打开侧边栏") } else if(!root) IconButton(onClick=model::back) { Glyph("arrow_back", "返回") } },
                                        titleContent=if(root && state.rootTab==1) ({ Box(Modifier.padding(end=16.dp)){SearchField(model,state,searchUi)} }) else if(profile!=null)({Column {Text(profile.name,maxLines=1,overflow=TextOverflow.Ellipsis);if("postsCount" in profile.knownCounts)Text("${profile.postsCount} 推文",style=MaterialTheme.typography.bodySmall)}})else null,
                                        titleClick=if(root)({ scope.launch { list.animateScrollToItem(0) };Unit })else null,
                                        titleDoubleClick=if(root)({ scope.launch { list.animateScrollToItem(0);model.load() };Unit })else null,
                                        actions={ if(state.screen.feed.kind=="LocalHistory")IconButton(onClick={clearHistory=true},enabled=state.accountId?.let {model.settings.history(it).isNotEmpty()}==true){Glyph("delete_outline","清空本机历史")};if(profile!=null)IconButton(onClick={runCatching {NativeServices.open(context,"https://x.com/${profile.handle}")}.onFailure {model.message("无法打开浏览器")}}){Glyph("open_in_new","在 X 打开主页")};if(state.screen.feed.kind=="Article")IconButton(onClick={runCatching {NativeServices.open(context,(state.screen.posts.firstOrNull()?:state.screen.selectedPost)?.url?:"https://x.com/i/status/${state.screen.feed.value}")}.onFailure {model.message("无法打开浏览器")}}){Glyph("open_in_new","在 X 打开原文")};if(state.screen.feed.kind=="NotificationsTimeline") FlutterTextButton(onClick=model::markNotificationsRead,enabled=state.screen.topCursor!=null && !state.screen.markedRead && !state.screen.markingRead && !state.screen.readUncertain) {Text(if(state.screen.markedRead)"已读"else if(state.screen.markingRead)"提交中…"else "标记已读")};if(root && state.rootTab==0 && state.loggedIn) IconButton(onClick={ composer=ComposeRequest() }) { Glyph("edit_outlined","发布帖子",color=MaterialTheme.colorScheme.onSurfaceVariant) } })
                                    if(root && state.rootTab==0 && state.loggedIn) ReviewTabs(listOf("为你推荐","正在关注"),state.homeTab,model::selectHome)
                                    if(root && state.rootTab==1) ExploreTabs(state.screen.feed.option!="false",model::explore)
                                    if(state.screen.feed.option=="account_history")ReviewTabs(listOf("书签","喜欢"),if(state.screen.feed.kind=="Likes")1 else 0,{model.replaceFeed(Feed(if(it==0)"Bookmarks"else "Likes",state.accountId.orEmpty(),"历史","account_history"))},icons=listOf("bookmark_border","favorite_border"))
                                    if(state.expired)ExpiredSessionBanner{model.open(Feed("Login",title="账号登录"))}
                                    }
                                },
                                body = { topInset ->
                                    Box(Modifier.fillMaxSize().then(
                                        if (sample) Modifier.recordBackdrop(backdrop, notify = Build.VERSION.SDK_INT < 33) else Modifier
                                    ).background(LocalChrome.current.background)) {
                                        val screenBody: @Composable (ReaderState) -> Unit = { page ->
                                            val active = page.screen.key == liveState.screen.key && page.rootTab == liveState.rootTab
                                            val pageList = lists.getOrPut(listKey(page.screen)) { LazyListState() }
                                            val pageInset = if (root && page.rootTab == 2 && !page.expired) statusInset else topInset
                                            var retainedInset by remember { mutableStateOf(pageInset) }
                                            if (page.rootTab == state.rootTab) SideEffect { retainedInset = pageInset }
                                            val inset = if (page.rootTab == state.rootTab) pageInset else retainedInset
                                            CompositionLocalProvider(LocalHeaderInset provides inset) {
                                                DisposableEffect(page.screen.key, root) {
                                                    onDispose {
                                                        if (!root && page.screen.key !in activeScreenKeys) saved.removeState(page.screen.key)
                                                    }
                                                }
                                                saved.SaveableStateProvider(if (root) "root:${page.rootTab}" else page.screen.key) {
                                                when(val kind=page.screen.feed.kind) {
                                                    "Settings" -> SettingsHome(model,page)
                                                    "Login" -> LoginScreen(model,page)
                                                    "Theme","Reading","Network","NotificationSettings","Storage","Cache","WebDAV","Account","About","Display","Licenses","Diagnostics" -> SettingsScreen(kind,model,page)
                                                    "SearchTimeline" -> SearchResults(model,page,pageList)
                                                    "LocalHistory" -> HistoryScreen(model,page)
                                                    "Article" -> ArticleScreen(page,model)
                                                    "ProfileLink" -> DetailLoading(page.screen.error){model.load()}
                                                    "Browser" -> LaunchedEffect(page.screen.key) { actions.link(page.screen.feed.value);model.back() }
                                                    else -> if(!page.loggedIn) Box(Modifier.padding(top=inset)){Guest(model)} else if(root&&page.rootTab==0)HomeTimelines(model,page,lists,if(floating)100 else 0,active) else if(page.screen.feed.option=="account_history")HistoryTimelines(model,page,lists,active) else TimelineScreen(model,page,pageList,if(root&&floating)100 else 24,active=active)
                                                }
                                                }
                                            }
                                        }
                                        if (root) {
                                            AnimatedContent(
                                                targetState = state, contentKey = { it.rootTab },
                                                modifier = Modifier.fillMaxSize().clipToBounds(),
                                                transitionSpec = {
                                                    val sign = if (targetState.rootTab > initialState.rootTab) direction else -direction
                                                    (slideInHorizontally(tween(260, easing = easing)) { it * sign }
                                                        togetherWith slideOutHorizontally(tween(260, easing = easing)) { -it * sign }).using(null)
                                                },
                                                label = "tab bodies",
                                            ) { page -> screenBody(page) }
                                        } else screenBody(state)
                                    }
                                },
                                overlay = { height ->
                                    if (root && state.rootTab == 1) SearchSuggestions(model, state, searchUi, height)
                                },
                            )
                            if(root) Box(Modifier.align(Alignment.BottomCenter).windowInsetsPadding(navigationInsets).padding(bottom=if(!state.settings.optBoolean("floating_nav",true))0.dp else if(navigationInsets.getBottom(LocalDensity.current)>0)6.dp else 14.dp)) {
                                BottomNavigation(state.rootTab,{ index -> if(index==state.rootTab) scope.launch {if(list.firstVisibleItemIndex>0||list.firstVisibleItemScrollOffset>with(density){50.dp.toPx()}){previousPositions[state.screen.key]=list.firstVisibleItemIndex to list.firstVisibleItemScrollOffset;list.animateScrollToItem(0)}else{val previous=previousPositions.remove(state.screen.key);if(previous!=null)list.animateScrollToItem(previous.first,previous.second)else list.animateScrollToItem(0)}} else model.selectRoot(index) },{ index -> if(index!=state.rootTab)model.selectRoot(index);scope.launch { list.animateScrollToItem(0);model.load() } })
                            }
                        }
                    }
                }
                SnackbarHost(snackbar,Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(bottom=if(root)68.dp else 12.dp))
            }
        }
        if(clearHistory)FlutterAlertDialog(onDismissRequest={clearHistory=false},title={Text("清空本机历史？")},confirmButton={FlutterTextButton(onClick={state.accountId?.let {model.setSetting("history_$it","[]")};clearHistory=false}){Text("清空")}},dismissButton={FlutterTextButton(onClick={clearHistory=false}){Text("取消")}})
        if(composer!=null) ComposerScreen(composer!!,model) { composer=null }
        if(gallery!=null) MediaGallery(gallery!!,model) { gallery=null }
    }
}

val LocalHeaderInset=staticCompositionLocalOf {0.dp}
@OptIn(ExperimentalFoundationApi::class)
@Composable fun AppTopBar(title:String,height:Int=56,leading:@Composable ()->Unit={},actions:@Composable RowScope.()->Unit={},titleContent:(@Composable ()->Unit)?=null,titleClick:(()->Unit)?=null,titleDoubleClick:(()->Unit)?=null,transparent:Boolean=false,leadingWidth:Int=56,titleSpacing:Dp=0.dp) {
    val background=LocalChrome.current.appBar
    Column(Modifier.background(if(transparent)Color.Transparent else background).windowInsetsPadding(WindowInsets.statusBarsIgnoringVisibility)) {
        val tap = titleClick?.let { hapticClick(it) }
        val doubleTap = titleDoubleClick?.let { hapticClick(it) }
        Row(Modifier.fillMaxWidth().height(height.dp),verticalAlignment=Alignment.CenterVertically) {
            Box(Modifier.width(leadingWidth.dp),contentAlignment=Alignment.Center) { leading() }
            Spacer(Modifier.width(titleSpacing))
            Box(Modifier.weight(1f).then(if(tap!=null)Modifier.combinedClickable(onClick=tap,onDoubleClick=doubleTap) else Modifier)) { if(titleContent!=null)titleContent() else Text(title,maxLines=1,overflow=TextOverflow.Ellipsis,style=TextStyle(platformStyle=androidx.compose.ui.text.PlatformTextStyle(includeFontPadding=true),fontSize=18.sp,fontWeight=flutterWeight(700),color=MaterialTheme.colorScheme.onSurface)) }
            Row(content=actions)
        }
    }
}
@Composable
private fun ExploreTabs(personalized: Boolean, select: (Boolean) -> Unit) {
    val colors = MaterialTheme.colorScheme
    Row(Modifier.fillMaxWidth().height(48.dp)) {
        listOf("探索", "当前趋势").forEachIndexed { index, title ->
            val selected = (index == 0) == personalized
            val selectTab = hapticClick { select(index == 0) }
            Box(
                Modifier.weight(1f).fillMaxHeight().selectable(selected, onClick = {
                    if (!selected) selectTab()
                }),
                contentAlignment = Alignment.Center,
            ) {
                Text(title, fontWeight = flutterWeight(if (selected) 700 else 400))
                HorizontalDivider(
                    Modifier.align(Alignment.BottomCenter), thickness = if (selected) 3.dp else 1.dp,
                    color = if (selected) colors.primary else colors.outlineVariant,
                )
            }
        }
    }
}
@Composable fun ReviewTabs(titles:List<String>,selected:Int,onSelect:(Int)->Unit,icons:List<String> = emptyList()) {
    val scheme=MaterialTheme.colorScheme
    Box(Modifier.fillMaxWidth()) {
        HorizontalDivider(Modifier.align(Alignment.BottomCenter),color=scheme.outlineVariant)
        Row(Modifier.fillMaxWidth().height(if(icons.isEmpty())48.dp else 72.dp)) {titles.forEachIndexed {index,title->
            Box(Modifier.weight(1f).fillMaxHeight().selectable(selected==index,onClick=hapticClick {onSelect(index)}),contentAlignment=Alignment.Center) {
                Column(Modifier.width(IntrinsicSize.Max).fillMaxHeight(),horizontalAlignment=Alignment.CenterHorizontally) {
                    Column(Modifier.weight(1f),verticalArrangement=Arrangement.Center,horizontalAlignment=Alignment.CenterHorizontally) {
                        if(icons.isNotEmpty()){Glyph(icons[index],color=if(index==selected)scheme.primary else scheme.onSurfaceVariant);Spacer(Modifier.height(2.dp))}
                        Text(title,fontSize=15.sp,fontWeight=flutterWeight(if(index==selected)600 else 400),color=if(index==selected)scheme.primary else scheme.onSurfaceVariant)
                    }
                    Box(Modifier.fillMaxWidth().height(3.dp).clip(RoundedCornerShape(topStart=3.dp,topEnd=3.dp)).background(if(index==selected)scheme.primary else Color.Transparent))
                }
            }
        }}
    }
}
@Composable fun BottomNavigation(selected:Int,onSelect:(Int)->Unit,onDouble:(Int)->Unit) {
    val feedback = androidx.compose.ui.platform.LocalHapticFeedback.current
    fun confirm(index: Int, action: (Int) -> Unit) {
        if (index != selected || index < 2) {
            feedback.performHapticFeedback(androidx.compose.ui.hapticfeedback.HapticFeedbackType.VirtualKey)
        }
        action(index)
    }
    val select: (Int) -> Unit = { confirm(it, onSelect) }
    val double: (Int) -> Unit = { confirm(it, onDouble) }
    val latestSelect by rememberUpdatedState(select)
    val current by rememberUpdatedState(selected)
    val settings=LocalSettings.current;val floating=settings.optBoolean("floating_nav",true)
    val liquid = floating && settings.optBoolean("use_liquid_glass_effect")
    val labels=listOf("首页","探索","设置");val icons=listOf("home_outlined","explore_outlined","settings_outlined");val chosen=listOf("home_rounded","explore","settings_rounded")
    val scope = rememberCoroutineScope()
    var pending by remember { mutableStateOf<Job?>(null) }
    var lastTap by remember { mutableLongStateOf(0L) }
    LaunchedEffect(selected, floating, liquid) {
        pending?.cancel()
        lastTap = 0L
    }
    fun plainTap(index: Int) {
        pending?.cancel()
        if (index != selected) {
            lastTap = 0L
            select(index)
        } else if (index < 2) {
            val now = android.os.SystemClock.uptimeMillis()
            if (lastTap != 0L && now - lastTap < 300L) {
                lastTap = 0L
                double(index)
            } else {
                lastTap = now
                pending = scope.launch {
                    delay(300L)
                    lastTap = 0L
                    if (index == current) latestSelect(index)
                }
            }
        }
    }
    if(!floating) {
    NavigationBar(modifier=Modifier.height(68.dp),containerColor=LocalChrome.current.navigation,tonalElevation=0.dp,windowInsets=WindowInsets(0)) { labels.forEachIndexed { i,label -> NavigationBarItem(selected==i,{plainTap(i)},icon={Glyph(if(selected==i)chosen[i] else icons[i])},label={Text(label,fontSize=12.sp,fontWeight=flutterWeight(if(selected==i)700 else 500))},colors=NavigationBarItemDefaults.colors(selectedIconColor=MaterialTheme.colorScheme.onPrimaryContainer,selectedTextColor=MaterialTheme.colorScheme.primary,indicatorColor=MaterialTheme.colorScheme.primaryContainer,unselectedIconColor=MaterialTheme.colorScheme.onSurfaceVariant,unselectedTextColor=MaterialTheme.colorScheme.onSurfaceVariant)) } }}
    else BoxWithConstraints(Modifier.fillMaxWidth(),contentAlignment=Alignment.Center) {
        val width=minOf(440.dp,maxWidth-40.dp)*2/3
        if(liquid) LiquidNavigation(selected,select,double,width)
        else Box(Modifier.width(width).height(56.dp).dropShadow(RoundedCornerShape(32.dp),androidx.compose.ui.graphics.shadow.Shadow(radius=16.dp,color=Color.Black.copy(alpha=if(LocalDarkTheme.current).35f else .12f),offset=DpOffset(0.dp,4.dp))).clip(RoundedCornerShape(32.dp)).background(MaterialTheme.colorScheme.surfaceContainerHigh).padding(4.dp)) {
            val position by androidx.compose.animation.core.animateDpAsState((width-8.dp)/3*selected,tween(200,easing=CubicBezierEasing(.645f,.045f,.355f,1f)))
            Box(Modifier.offset { IntOffset(position.roundToPx(), 0) }.width((width-8.dp)/3).fillMaxHeight().clip(RoundedCornerShape(28.dp)).background(MaterialTheme.colorScheme.secondaryContainer))
            Row {
            labels.forEachIndexed { i,label ->
                Column(Modifier.weight(1f).fillMaxHeight().clip(RoundedCornerShape(28.dp))
                    .selectable(selected == i, role = androidx.compose.ui.semantics.Role.Tab, onClick = { plainTap(i) }),horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.Center) {
                    Glyph(if(selected==i)chosen[i] else icons[i],size=22,color=if(selected==i)MaterialTheme.colorScheme.onSecondaryContainer else MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.height(2.dp));Text(label,fontSize=11.5.sp,fontWeight=flutterWeight(if(selected==i)600 else 400),color=if(selected==i)MaterialTheme.colorScheme.onSecondaryContainer else MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        }
    }
}
@Composable fun Guest(model:ReaderViewModel) { Column(Modifier.fillMaxSize().padding(32.dp),verticalArrangement=Arrangement.Center,horizontalAlignment=Alignment.CenterHorizontally) {
    Glyph("forum_outlined",size=72,color=MaterialTheme.colorScheme.primary);Spacer(Modifier.height(24.dp));Text("ReviewX",Modifier.flutterLineHeight(MaterialTheme.typography.headlineMedium.lineHeight),style=MaterialTheme.typography.headlineMedium);Spacer(Modifier.height(12.dp));Text("登录 X，阅读你的关注时间线");Spacer(Modifier.height(24.dp))
    Button(onClick={model.open(Feed("Login",title="账号登录"))}) { Glyph("login",size=18);Spacer(Modifier.width(8.dp));Text("登录 X") }
} }
@Composable fun SearchField(model:ReaderViewModel,state:ReaderState,suggestions:SearchUi?=null) {
    val focus=LocalFocusManager.current
    var text by rememberSaveable(state.screen.feed.value) { mutableStateOf(if(state.screen.feed.kind=="SearchTimeline")state.screen.feed.value else "") }
    TextField(suggestions?.query?:text,{text=it;suggestions?.query=it},Modifier.fillMaxWidth().onFocusChanged {suggestions?.focused=it.isFocused},placeholder={Text("搜索 X")},leadingIcon={Glyph(if(suggestions!=null)"search_rounded"else "search")},trailingIcon={IconButton(onClick={focus.clearFocus();model.search(suggestions?.query?:text)}) {Glyph(if(suggestions!=null)"arrow_forward_rounded"else "arrow_forward")}},textStyle=MaterialTheme.typography.bodyLarge,singleLine=true,shape=RoundedCornerShape(32.dp),keyboardOptions=KeyboardOptions(imeAction=ImeAction.Search),keyboardActions=KeyboardActions(onSearch={focus.clearFocus();model.search(suggestions?.query?:text)}),colors=TextFieldDefaults.colors(unfocusedIndicatorColor=Color.Transparent,focusedIndicatorColor=Color.Transparent))
}
@Composable fun LoginScreen(model:ReaderViewModel,state:ReaderState) {
    val context=LocalContext.current;var importing by rememberSaveable { mutableStateOf(false) };var cookie by remember { mutableStateOf("") };var visible by remember { mutableStateOf(false) }
    val launcher=rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { if(it.resultCode==Activity.RESULT_OK)model.restore() }
    BackHandler(state.authenticating) {}
    Column {
    AppTopBar(if(importing)"Cookie 导入"else "账号登录",leading={IconButton(onClick={if(!state.authenticating)model.back()}){Glyph("arrow_back","返回")}},actions={FlutterTextButton(enabled=!state.authenticating,onClick={importing=!importing}){Text(if(importing)"账号登录"else "Cookie 导入")}})
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(start=32.dp,top=48.dp,end=32.dp,bottom=24.dp),horizontalAlignment=Alignment.CenterHorizontally) {
        state.loginError?.let {Text(it,color=MaterialTheme.colorScheme.error,textAlign=androidx.compose.ui.text.style.TextAlign.Center);Spacer(Modifier.height(16.dp))}
        if(!importing) Surface(shape=RoundedCornerShape(24.dp),color=MaterialTheme.colorScheme.surfaceContainerLow) { Column(Modifier.padding(24.dp),horizontalAlignment=Alignment.CenterHorizontally) {
            Box(Modifier.size(56.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primaryContainer),contentAlignment=Alignment.Center) {Glyph("open_in_browser",size=28,color=MaterialTheme.colorScheme.onPrimaryContainer)}
            Spacer(Modifier.height(20.dp));Text("使用 X 官方页面登录",Modifier.flutterLineHeight(MaterialTheme.typography.titleLarge.lineHeight),style=MaterialTheme.typography.titleLarge,textAlign=androidx.compose.ui.text.style.TextAlign.Center);Spacer(Modifier.height(12.dp));Text("账号、密码和安全验证都在 X 页面完成。ReviewX 不会收集或保存你的密码；登录成功后会验证会话并返回应用。",textAlign=androidx.compose.ui.text.style.TextAlign.Center)
            Spacer(Modifier.height(24.dp));Button(onClick={launcher.launch(Intent(context,XLoginActivity::class.java))},enabled=!state.authenticating,modifier=Modifier.fillMaxWidth().height(48.dp)) {if(state.authenticating)FlutterProgress(Modifier.size(20.dp),strokeWidth=2.dp)else Text("前往 X 登录")}
        } } else {
            Text("粘贴 X 会话 Cookie。至少包含 auth_token 和 ct0；验证通过后仅保存在本机加密存储中。");Spacer(Modifier.height(24.dp))
            OutlinedTextField(cookie,{cookie=it},Modifier.fillMaxWidth(),textStyle=MaterialTheme.typography.bodyLarge,label={Text("X Cookie")},placeholder={Text("auth_token=…; ct0=…; twid=…")},visualTransformation=if(visible)VisualTransformation.None else PasswordVisualTransformation(),enabled=!state.authenticating,keyboardOptions=KeyboardOptions(keyboardType=KeyboardType.Password,autoCorrectEnabled=false),trailingIcon={IconButton(onClick={visible=!visible}){Glyph(if(visible)"visibility_off" else "visibility")}},shape=RoundedCornerShape(12.dp))
            Spacer(Modifier.height(16.dp));Button(onClick={model.login(cookie);cookie=""},enabled=!state.authenticating && cookie.isNotBlank(),modifier=Modifier.fillMaxWidth().height(48.dp)) {if(state.authenticating)FlutterProgress(Modifier.size(20.dp),strokeWidth=2.dp)else Text("验证并登录")}
        }
        Spacer(Modifier.height(12.dp));FlutterTextButton(enabled=!state.authenticating,onClick={val diagnostics=XLoginDiagnostics.read(context);if(diagnostics.isEmpty())model.message("当前没有登录诊断记录")else{NativeServices.copy(context,diagnostics);model.message("登录诊断已复制（不含 Cookie 或密码）")}}) {Glyph("content_copy_outlined",size=18);Spacer(Modifier.width(8.dp));Text("复制登录诊断（不含账号凭据）")}
    }
    }
}


@Composable fun HomeTimelines(model:ReaderViewModel,state:ReaderState,lists:MutableMap<String,LazyListState>,bottom:Int,active:Boolean) {
    val currentlyActive by rememberUpdatedState(active)
    val pager=rememberPagerState(initialPage=state.homeTab,pageCount={2})
    var dragging by remember {mutableStateOf(false)}
    val dragged by pager.interactionSource.collectIsDraggedAsState()
    LaunchedEffect(state.homeTab){if(pager.currentPage!=state.homeTab)pager.animateScrollToPage(state.homeTab)}
    LaunchedEffect(dragged){if(dragged)dragging=true}
    LaunchedEffect(pager){snapshotFlow {pager.settledPage to pager.isScrollInProgress}.collect {(page,moving)->if(!moving&&dragging){dragging=false;if(currentlyActive)model.selectHome(page)}}}
    HorizontalPager(pager,Modifier.fillMaxSize(),beyondViewportPageCount=1) {index->
        val screen=if(index==state.homeTab)state.screen else model.cachedHome(index)
        TimelineScreen(model,state.copy(screens=listOf(screen)),lists.getOrPut(listKey(screen)){LazyListState()},bottom,active=active&&index==state.homeTab)
    }
}

private fun listKey(screen:ReaderScreen)=screen.key+":"+screen.feed.kind+":"+screen.feed.option
@Composable fun HistoryTimelines(model:ReaderViewModel,state:ReaderState,lists:MutableMap<String,LazyListState>,active:Boolean) {
    val index=if(state.screen.feed.kind=="Likes")1 else 0
    val pager=rememberPagerState(initialPage=index,pageCount={2});val cache=remember(state.screen.key){mutableMapOf<Int,ReaderScreen>()};cache[index]=state.screen
    val currentActive by rememberUpdatedState(active);var dragging by remember {mutableStateOf(false)};val dragged by pager.interactionSource.collectIsDraggedAsState()
    LaunchedEffect(index){if(pager.currentPage!=index)pager.animateScrollToPage(index)}
    LaunchedEffect(dragged){if(dragged)dragging=true}
    LaunchedEffect(pager){snapshotFlow {pager.settledPage to pager.isScrollInProgress}.collect {(page,moving)->if(!moving&&dragging){dragging=false;if(currentActive)model.replaceFeed(state.screen.feed.copy(kind=if(page==0)"Bookmarks"else "Likes",value=state.accountId.orEmpty()))}}}
    HorizontalPager(pager,Modifier.fillMaxSize(),beyondViewportPageCount=1) {page->
        val screen=if(page==index)state.screen else cache[page] ?: ReaderScreen(feed=state.screen.feed.copy(kind=if(page==0)"Bookmarks"else "Likes"),key=state.screen.key)
        TimelineScreen(model,state.copy(screens=listOf(screen)),lists.getOrPut(listKey(screen)){LazyListState()},24,active=active&&page==index)
    }
}
