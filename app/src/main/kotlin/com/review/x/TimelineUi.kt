package com.review.x

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.*
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.foundation.shape.*
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshDefaults
import androidx.compose.material3.pulltorefresh.pullToRefresh
import androidx.compose.material3.pulltorefresh.rememberPullToRefreshState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.*
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.*
import androidx.compose.ui.text.*
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.*
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider
import coil.compose.AsyncImage
import coil.request.ImageRequest
import android.graphics.drawable.BitmapDrawable
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.*
import java.time.*
import java.time.format.DateTimeFormatter
import java.util.Locale

val Post.url:String get()="https://x.com/${author.handle}/status/$id"
@Composable fun NetworkImage(url:String,description:String?,modifier:Modifier=Modifier,scale:ContentScale=ContentScale.Crop,transparentFallback:Boolean=false,onDimensions:((Int,Int)->Unit)?=null,onImageReady:((ImageBitmap)->Unit)?=null,showProgress:Boolean=false) {
    val context = LocalContext.current
    val request = remember(context, url) {
        ImageRequest.Builder(context)
            .data(url.takeIf { safeMediaUrl(it) || it == "https://picsum.photos/id/1015/1200/500" })
            .setHeader("User-Agent", ReaderRepository.USER_AGENT)
            .setHeader("Referer", "https://x.com/")
            .crossfade(false)
            .build()
    }
    var retry by remember(url) { mutableIntStateOf(0) }
    key(url, retry) {
        var loading by remember { mutableStateOf(false) }
        var failed by remember { mutableStateOf(false) }
        Box(modifier, contentAlignment = Alignment.Center, propagateMinConstraints = true) {
            AsyncImage(
                model = request,
                contentDescription = description,
                contentScale = scale,
                onLoading = { loading = showProgress && !transparentFallback },
                onSuccess = {
                    loading = false
                    failed = false
                    val drawable = it.result.drawable
                    onDimensions?.invoke(drawable.intrinsicWidth, drawable.intrinsicHeight)
                    if (onImageReady != null && drawable is BitmapDrawable) {
                        onImageReady(drawable.bitmap.asImageBitmap())
                    }
                },
                onError = {
                    loading = false
                    failed = !transparentFallback
                },
            )
            if (loading || failed) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    if (loading) FlutterProgress(strokeWidth = 2.dp)
                    else Text("Failed to load image", Modifier.hapticClickable { retry++ })
                }
            }
        }
    }
}
@Composable fun Avatar(user:User?,size:Int=40,onImageReady:((ImageBitmap)->Unit)?=null,onClick:(()->Unit)?=null) {
    Box(Modifier.size(size.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surfaceContainerHighest).then(if(onClick!=null)Modifier.hapticClickable(onClick=onClick) else Modifier),contentAlignment=Alignment.Center) {
        if(user!=null && safeMediaUrl(user.avatar)) NetworkImage(user.avatar,user.name,Modifier.fillMaxSize(),onImageReady=onImageReady) else Glyph("person",size=if(size==80)40 else 24)
    }
}
@OptIn(ExperimentalMaterial3Api::class)
@Composable internal fun TimelinePullRefresh(
    refreshing: Boolean,
    enabled: Boolean,
    onRefresh: () -> Unit,
    content: @Composable (Modifier) -> Unit,
) {
    val pull = rememberPullToRefreshState()
    val header = LocalHeaderInset.current
    val stretch by animateFloatAsState(if (refreshing) 0f else 1f, tween(150), label = "refresh stretch")
    Box(Modifier.fillMaxSize().clipToBounds().pullToRefresh(refreshing, pull, enabled = enabled, onRefresh = onRefresh)) {
        content(Modifier.graphicsLayer {
            transformOrigin = TransformOrigin(.5f, 0f)
            scaleY = 1f + .025f * pull.distanceFraction.coerceIn(0f, 1.5f) * stretch
        })
        PullToRefreshDefaults.Indicator(
            state = pull,
            isRefreshing = refreshing,
            modifier = Modifier.align(Alignment.TopCenter).offset(y = header),
            containerColor = MaterialTheme.colorScheme.surface,
            color = MaterialTheme.colorScheme.primary,
        )
    }
}

@Composable fun TimelineScreen(model:ReaderViewModel,state:ReaderState,list:LazyListState,bottom:Int,active:Boolean=true) {
    val screen=state.screen;val actions=LocalActions.current
    val userList=screen.feed.kind in listOf("Followers","Following") || screen.feed.kind=="SearchTimeline"&&screen.feed.option=="People"
    val detail = screen.feed.kind == "TweetDetail"
    if(detail&&screen.selectedPost==null){DetailLoading(screen.error){model.load()};return}
    val known=remember(detail,screen.posts,screen.selectedPost){
        if (detail) screen.posts.associateBy {it.id}+listOfNotNull(screen.selectedPost).associateBy {it.id}
        else emptyMap()
    }
    LaunchedEffect(list,screen.key,screen.cursor,screen.restoredSnapshot,screen.busy,screen.error,active) {
        if(!active)return@LaunchedEffect
        snapshotFlow {
            (list.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: -1) to
                (list.firstVisibleItemIndex > 0 || list.firstVisibleItemScrollOffset > 0)
        }.collect { (index, hasScrolled) ->
            if(screen.shouldPrefetch(index,list.layoutInfo.totalItemsCount,hasScrolled))model.load(true)
        }
    }
    val refreshing = screen.busy && screen.pullRefreshing
    key(screen.key) {
    TimelinePullRefresh(refreshing, enabled = active && (!screen.busy || refreshing), onRefresh = { model.load(fromPull = true) }) { stretch ->
        LazyColumn(state=list,contentPadding=PaddingValues(top=LocalHeaderInset.current,bottom=bottom.dp),modifier=Modifier.fillMaxSize().then(stretch)) {
            if (!refreshing && (screen.busy || screen.error != null || screen.auxiliaryError != null))
                item(key="request-status"){RequestStatus(screen.busy,screen.error?:screen.auxiliaryError){model.load()}}
            if(screen.feed.kind=="NotificationsTimeline")item{if(screen.readUncertain)FlutterListItem(headlineContent={},supportingContent={Text("已读结果待核对，请在 X 查看")})else Spacer(Modifier.height(4.dp))}
            screen.profile?.let { user -> item(key="profile") { ProfileHeader(user,state,model) };item(key="tabs") { ProfileTabs(screen,model) } }
            if(screen.feed.kind=="Likes" && screen.profile!=null && screen.profile.id!=state.accountId) {item {Text("X 不公开其他用户的喜欢列表，仅可查看自己的喜欢",Modifier.fillMaxWidth().padding(24.dp),textAlign=androidx.compose.ui.text.style.TextAlign.Center)};return@LazyColumn}
            if(screen.feed.kind=="Explore") {
                item {Text(if(screen.feed.option=="false")"当前趋势"else "为你推荐的趋势",Modifier.padding(start=16.dp,top=16.dp,end=16.dp,bottom=4.dp),style=MaterialTheme.typography.titleLarge,fontWeight=FontWeight.Bold)}
                items(screen.trends,key={"trend:${it.name}"},contentType={"trend"}) { trend -> Column(Modifier.fillMaxWidth().hapticClickable {model.search(trend.name)}.padding(horizontal=16.dp,vertical=14.dp)) {
                    Text(trend.description.ifBlank{"趋势"},fontSize=13.sp,color=MaterialTheme.colorScheme.onSurfaceVariant);Spacer(Modifier.height(4.dp))
                    Text(trend.name,style=MaterialTheme.typography.titleMedium,fontWeight=FontWeight.Bold)
                    if(trend.meta.isNotBlank()){Spacer(Modifier.height(4.dp));Text(trend.meta,color=MaterialTheme.colorScheme.onSurfaceVariant)}
                } }
                if(!screen.busy&&screen.trends.isEmpty()&&screen.auxiliaryError==null)item {Box(Modifier.fillMaxWidth().padding(24.dp),contentAlignment=Alignment.Center){Text("当前没有可显示的趋势")}}
                if(screen.feed.option!="false") {item {FlutterDivider();Text("推荐关注",Modifier.padding(16.dp),style=MaterialTheme.typography.titleLarge,fontWeight=FontWeight.Bold)};if(!screen.busy&&screen.users.isEmpty()&&screen.auxiliaryError==null)item {Text("X 暂未返回推荐用户",Modifier.padding(16.dp))}}
            }
            items(screen.users,key={"user:${it.id}"},contentType={"user"}) {UserRow(it,state,model)}
            items(screen.notifications,key={"notification:"+it.id},contentType={"notification"}) { n ->
                FlutterCard(Modifier.fillMaxWidth().padding(horizontal=12.dp,vertical=6.dp)) {Column {
                    FlutterListItem(headlineContent={Text(n.message.ifBlank {"X 通知"})},supportingContent=if(n.timestamp>0)({Text(java.time.Instant.ofEpochMilli(n.timestamp).atZone(java.time.ZoneId.systemDefault()).format(java.time.format.DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")))})else null,
                        leadingContent={Glyph(if(n.icon.contains("heart"))"favorite"else if(n.icon.contains("retweet"))"repeat"else "notifications_outlined")},
                        modifier=Modifier.hapticClickable(enabled=n.posts.isNotEmpty()||n.actors.isNotEmpty()){if(n.posts.isNotEmpty())model.openPost(n.posts.first())else model.openUser(n.actors.first())})
                    FlowRow {n.actors.take(8).forEach {user->FlutterTextButton(onClick={model.openUser(user)}) {Text("@"+user.handle)}}}
                    n.posts.take(3).forEach {PostCard(model.effective(it))}
                }}
            }
            if(detail) {
                screen.selectedPost?.let {post->item(key="selected") {PostCard(model.effective(post),detail=true,replyParent=screen.replyParent)}}
                item(key="reply-sort") {var menu by remember {mutableStateOf(false)}
                    Row(Modifier.fillMaxWidth().padding(horizontal=12.dp,vertical=4.dp),verticalAlignment=Alignment.CenterVertically) {
                        Text("回复",Modifier.weight(1f));Box {
                            Row(Modifier.hapticClickable{menu=true}.padding(12.dp),verticalAlignment=Alignment.CenterVertically){Text(when(screen.feed.option){"Recency"->"最近";"Likes"->"喜欢";else->"相关"});Spacer(Modifier.width(4.dp));Glyph("expand_more",size=20)}
                            DropdownMenu(menu,{menu=false}) {listOf("Relevance" to "相关","Recency" to "最近","Likes" to "喜欢").forEach { (key,title)->DropdownMenuItem(text={Text(title)},leadingIcon={if(key==screen.feed.option||key=="Relevance"&&screen.feed.option.isBlank())Glyph("check")else Spacer(Modifier.size(24.dp))},onClick={menu=false;if(screen.feed.option!=key)model.replaceFeed(screen.feed.copy(option=key))})}}
                        }
                    }
                }
            }
            itemsIndexed(screen.posts,key={_,post->"post:"+post.id},contentType={_,_->"post"}) {index,post->
                val parent=known[post.replyToId]
                var depth=0
                if (parent != null) {
                    var ancestor: Post? = parent
                    val visited = mutableSetOf(post.id)
                    while(ancestor!=null && ancestor.id!=screen.selectedPost?.id && depth<2 && visited.add(ancestor.id)){depth++;ancestor=known[ancestor.replyToId]}
                }
                Box(Modifier.padding(start=(depth*12).dp)) {PostCard(model.effective(post),replyParent=parent,showParentPreview=parent?.id!=screen.selectedPost?.id,connectedAbove=!detail&&index>0&&continues(screen.posts[index-1],post),connectedBelow=!detail&&index<screen.posts.lastIndex&&continues(post,screen.posts[index+1]))}
            }
            if(screen.feed.kind!="Explore")item(key="list-footer"){OriginalListFooter(screen,userList){model.load(screen.loaded&&screen.canLoadMore)}}
        }
    }
    }
}
@Composable fun UserRow(user:User,state:ReaderState,model:ReaderViewModel) {
    val recommended=state.screen.feed.kind=="Explore"
    Row(Modifier.fillMaxWidth().heightIn(min=78.dp).hapticClickable {model.openUser(user)}.padding(horizontal=16.dp,vertical=11.dp),verticalAlignment=Alignment.CenterVertically) {
        if(user.avatar.isNotBlank())Avatar(user,if(recommended)40 else 42)else Box(Modifier.width(40.dp),contentAlignment=Alignment.Center){Glyph("person")}
        Spacer(Modifier.width(16.dp));Column(Modifier.weight(1f)){Text(user.name,style=flutterTileTitle(),maxLines=if(recommended)1 else Int.MAX_VALUE,overflow=TextOverflow.Ellipsis);Spacer(Modifier.height(2.dp));Text("@${user.handle}\n${user.bio}",style=flutterTileSubtitle(),maxLines=3,overflow=TextOverflow.Ellipsis)}
        if(recommended){Spacer(Modifier.width(16.dp));Button(onClick={model.follow(user)},enabled=!model.blocked("user:${user.id}")&&!user.isFollowing&&!user.followRequested){Text(if("user:${user.id}" in state.pending)"提交中"else if("user:${user.id}" in state.uncertain)"待核对"else if(user.isFollowing)"已关注"else if(user.followRequested)"已请求"else "关注")}}
    }
}
@Composable fun ProfileHeader(user:User,state:ReaderState,model:ReaderViewModel) {
    var bannerBounds by remember(user.id){mutableStateOf<androidx.compose.ui.layout.LayoutCoordinates?>(null)};var avatarImageBounds by remember(user.id){mutableStateOf<androidx.compose.ui.layout.LayoutCoordinates?>(null)}
    var bannerImage by remember(user.id){mutableStateOf<ImageBitmap?>(null)};var avatarImage by remember(user.id){mutableStateOf<ImageBitmap?>(null)}
    val bannerScope=remember(user.id){Any()};val avatarScope=remember(user.id){Any()}
    val actions=LocalActions.current;val showBanner=LocalReading.current.optBoolean("showBanner",true);val context=LocalContext.current
    Column {
        Box(Modifier.fillMaxWidth().height((if(showBanner)178 else 96).dp)) {
            if(showBanner) Box(Modifier.fillMaxWidth().height(120.dp).onGloballyPositioned {bannerBounds=it}.background(MaterialTheme.colorScheme.surfaceContainerHighest).hideGallerySource(bannerScope,0).hapticClickable(enabled=safeMediaUrl(user.banner)) {actions.gallery(GalleryRequest(listOf(Media(user.banner,"背景图",false)),0,user.handle,sourceAnchor={bannerBounds?.galleryAnchor()},sourceRadius=0f,sourceScope=bannerScope,sourceImage=bannerImage))}) {if(safeMediaUrl(user.banner))NetworkImage(user.banner,"背景图",Modifier.fillMaxSize(),onImageReady={bannerImage=it})}
            Box(Modifier.padding(start=16.dp,top=if(showBanner)82.dp else 8.dp).size(88.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surface).padding(4.dp)) {Box(Modifier.fillMaxSize().onGloballyPositioned {avatarImageBounds=it}.hideGallerySource(avatarScope,0)){Avatar(user,80,onImageReady={avatarImage=it},onClick={if(safeMediaUrl(user.avatar))actions.gallery(GalleryRequest(listOf(Media(user.avatar.replace("_bigger.","."),user.name,false)),0,user.handle,sourceAnchor={avatarImageBounds?.galleryAnchor()},sourceRadius=40f,sourceScope=avatarScope,sourceImage=avatarImage))})}}
            Box(Modifier.align(Alignment.BottomEnd).padding(end=16.dp,bottom=8.dp)) {
                if(user.id==state.accountId) FlutterOutlinedButton(onClick={NativeServices.share(context,"https://x.com/${user.handle}","分享个人主页")}) {Glyph("share_outlined",size=18);Spacer(Modifier.width(8.dp));Text("分享")}
                else FilledTonalButton(onClick={model.follow(user)},enabled=!model.blocked("user:${user.id}")) {Text(if("user:${user.id}" in state.pending)"提交中…" else if(user.isFollowing)"取消关注" else if(user.followRequested)"已请求关注" else if(user.protected)"请求关注" else "关注")}
            }
        }
        Column(Modifier.padding(start=16.dp,top=8.dp,end=16.dp)) {
            Row(verticalAlignment=Alignment.CenterVertically){Text(user.name,Modifier.weight(1f,fill=false).flutterLineHeight(MaterialTheme.typography.titleLarge.lineHeight),style=MaterialTheme.typography.titleLarge,fontWeight=FontWeight.Bold);if(user.verified){Spacer(Modifier.width(4.dp));Glyph("verified",size=20,color=MaterialTheme.colorScheme.primary)}}
            Text("@${user.handle}",style=MaterialTheme.typography.bodyMedium,color=MaterialTheme.colorScheme.onSurfaceVariant)
            if(user.followedBy || user.protected)Text(listOfNotNull(if(user.followedBy)"关注了你" else null,if(user.protected)"受保护的账号" else null).joinToString(" · "),Modifier.padding(top=6.dp),style=MaterialTheme.typography.bodySmall)
            if(user.bio.isNotBlank()){Spacer(Modifier.height(12.dp));Text(user.bio)}
            if(user.location.isNotBlank()||safeLink(user.website)||parseDate(user.created)!=null)Spacer(Modifier.height(10.dp));FlowRow(horizontalArrangement=Arrangement.spacedBy(14.dp),verticalArrangement=Arrangement.spacedBy(6.dp)){if(user.location.isNotBlank())Text("⌖ ${user.location}",color=MaterialTheme.colorScheme.onSurfaceVariant);if(safeLink(user.website))Text(user.website,Modifier.hapticClickable {actions.link(user.website)},color=MaterialTheme.colorScheme.primary);parseDate(user.created)?.let {Text("◷ ${it.year}年${it.monthValue}月加入",color=MaterialTheme.colorScheme.onSurfaceVariant)}}
            FlowRow(horizontalArrangement=Arrangement.spacedBy(12.dp)) {listOf(Triple("following",user.following,"正在关注"),Triple("followers",user.followers,"关注者")).forEach { (key,count,label)->FlutterTextButton(onClick={model.open(Feed(if(key=="followers")"Followers" else "Following",user.id,label))},contentPadding=PaddingValues(horizontal=4.dp),colors=ButtonDefaults.textButtonColors(contentColor=MaterialTheme.colorScheme.onSurface)){Text(buildAnnotatedString{withStyle(SpanStyle(fontWeight=FontWeight.Bold)){append(if(key in user.knownCounts)"$count "else "— ")};withStyle(SpanStyle(color=MaterialTheme.colorScheme.onSurfaceVariant)){append(label)}})} } }
            if(state.screen.profileError)FlutterTextButton(onClick={model.load()}){Text("资料加载失败，点击重试")}
            if("user:${user.id}" in state.uncertain)Text("操作结果待核对，请刷新后再操作",color=MaterialTheme.colorScheme.error)
        }
    }
}
@Composable fun ProfileTabs(screen:ReaderScreen,model:ReaderViewModel) {
    val scheme=MaterialTheme.colorScheme
    val tabs=listOf("UserTweets" to "推文","UserTweetsAndReplies" to "回复","UserRepostsTimeline" to "转推","UserPhotoTimeline" to "照片","UserArticlesTweets" to "文章","Likes" to "喜欢")
    val icons=listOf("article_outlined","chat_bubble_outline","repeat","photo_library_outlined","description_outlined","favorite_border")
    var tweetMode by rememberSaveable(screen.profile?.id){mutableStateOf("UserTweets")};var mediaMode by rememberSaveable(screen.profile?.id){mutableStateOf("UserPhotoTimeline")}
    if(screen.feed.kind in listOf("UserTweets","UserHighlightsTweets"))tweetMode=screen.feed.kind
    if(screen.feed.kind in listOf("UserPhotoTimeline","UserVideoTimeline"))mediaMode=screen.feed.kind
    Column {
        Row(Modifier.horizontalScroll(rememberScrollState())) {tabs.forEachIndexed {i,(kind,title)->
            var menu by remember {mutableStateOf(false)}
            val selected=screen.feed.kind==kind || i==0&&screen.feed.kind=="UserHighlightsTweets" || i==3&&screen.feed.kind=="UserVideoTimeline"
            Box {
                Column(Modifier.width(IntrinsicSize.Max).selectable(selected,onClick=hapticClick {if(i==0||i==3)menu=true else model.replaceFeed(screen.feed.copy(kind=kind))})) {
                    Row(Modifier.padding(horizontal=14.dp,vertical=16.dp),verticalAlignment=Alignment.CenterVertically) {
                        val color=if(selected)scheme.onSurface else scheme.onSurfaceVariant
                        Glyph(icons[i],size=18,color=color);Spacer(Modifier.width(6.dp))
                        Text(if(i==0&&tweetMode=="UserHighlightsTweets")"亮点"else if(i==3&&mediaMode=="UserVideoTimeline")"视频"else title,color=color)
                        if(i==0||i==3)Glyph("keyboard_arrow_down",size=16,color=color)
                    }
                    Box(Modifier.fillMaxWidth().height(3.dp).background(if(selected)scheme.primary else Color.Transparent))
                }
                DropdownMenu(menu,{menu=false}) {(if(i==0)listOf("UserTweets" to "推文","UserHighlightsTweets" to "亮点")else listOf("UserPhotoTimeline" to "照片","UserVideoTimeline" to "视频")).forEach {(op,label)->
                    DropdownMenuItem(text={Text(label)},leadingIcon={if(op==if(i==0)tweetMode else mediaMode)Glyph("check",size=24)else Spacer(Modifier.size(24.dp))},onClick={menu=false;model.replaceFeed(screen.feed.copy(kind=op))})
                }}
            }
        }}
        HorizontalDivider(color=scheme.outlineVariant)
    }
}

fun continues(parent:Post,reply:Post)=parent.repostedBy==null && reply.repostedBy==null && reply.replyToId==parent.id && (parent.conversationId.isBlank() || reply.conversationId.isBlank() || parent.conversationId==reply.conversationId)
@Composable fun PostCard(post:Post,quoted:Boolean=false,detail:Boolean=false,replyParent:Post?=null,showParentPreview:Boolean=true,connectedAbove:Boolean=false,connectedBelow:Boolean=false) {
    val actions=LocalActions.current;val model=actions.model;val context=LocalContext.current;val settings=LocalReading.current;val scheme=MaterialTheme.colorScheme
    val accountState by model.state.collectAsStateWithLifecycle()
    if(model.isDeleted(post.id)){
        if(quoted)Box(Modifier.border(1.dp,scheme.outlineVariant,RoundedCornerShape(16.dp)).padding(12.dp)){Text("该帖子已删除",style=MaterialTheme.typography.bodySmall)}
        return
    }
    var menu by remember {mutableStateOf(false)};var delete by remember {mutableStateOf(false)}
    val connected=!quoted&&(connectedAbove||connectedBelow)
    Column(Modifier.fillMaxWidth().drawBehind {if(connected){val color=scheme.primary.copy(alpha=.5f);drawLine(color,Offset(8.dp.toPx(),if(connectedAbove)0f else 30.dp.toPx()),Offset(8.dp.toPx(),if(connectedBelow)size.height else 30.dp.toPx()),2.dp.toPx(),StrokeCap.Round);drawLine(color,Offset(8.dp.toPx(),30.dp.toPx()),Offset(28.dp.toPx(),30.dp.toPx()),2.dp.toPx(),StrokeCap.Round)}}.padding(start=if(connected)16.dp else 0.dp)) {
    Column(Modifier.fillMaxWidth().then(if(quoted)Modifier.clip(RoundedCornerShape(16.dp)).border(1.dp,scheme.outlineVariant,RoundedCornerShape(16.dp)) else Modifier).background(if(settings.optBoolean("cardBackground",true))scheme.surfaceContainerLowest else Color.Transparent).hapticClickable(enabled=!detail) {model.openPost(post)}.drawBehind {if(!quoted && !connected && (post.replyToId.isNotBlank()||post.replyTo.isNotBlank()))drawLine(scheme.primary.copy(alpha=.35f),Offset(1.dp.toPx(),0f),Offset(1.dp.toPx(),size.height),2.dp.toPx())}.padding(horizontal=12.dp,vertical=10.dp)) {
        post.repostedBy?.let {Text("↻ $it 转发了",style=MaterialTheme.typography.labelMedium,modifier=Modifier.padding(bottom=8.dp))}
        Row(verticalAlignment=Alignment.Top) {
            if(post.author.avatar.isBlank())Box(Modifier.size(40.dp).hapticClickable{model.openUser(post.author)},contentAlignment=Alignment.Center){Glyph("person",color=postIconColor())}else Avatar(post.author,40){model.openUser(post.author)};Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f).heightIn(min=40.dp).hapticClickable {model.openUser(post.author)},verticalArrangement=Arrangement.Center){Text(post.author.name+if(post.author.verified)" ✓"else "",maxLines=1,overflow=TextOverflow.Ellipsis,style=MaterialTheme.typography.titleSmall);Row{Text("@${post.author.handle}",Modifier.weight(1f,fill=false),maxLines=1,overflow=TextOverflow.Ellipsis,style=MaterialTheme.typography.bodySmall);if(parseDate(post.created)!=null)Text("· ${postTime(post.created,settings)}",Modifier.weight(1f,fill=false).padding(start=6.dp),maxLines=1,overflow=TextOverflow.Ellipsis,style=MaterialTheme.typography.labelSmall)}}
            Box {IconButton(onClick=hapticClick {menu=true},modifier=Modifier.size(40.dp)){Glyph("more_vert",size=24,color=postIconColor())};DropdownMenu(menu,{menu=false}) {
                fun close(action:()->Unit) {menu=false;action()}
                DropdownMenuItem(text={Text("复制正文")},onClick={close {NativeServices.copy(context,post.text)}})
                DropdownMenuItem(text={Text("复制链接")},onClick={close {NativeServices.copy(context,post.url)}})
                DropdownMenuItem(text={Text("在应用内浏览")},onClick={close {runCatching {NativeServices.open(context,post.url)}.onFailure {model.message("无法打开浏览器")}}})
                DropdownMenuItem(text={Text("回复")},onClick={close {actions.compose(ComposeRequest(reply=post))}})
                DropdownMenuItem(text={Text("引用")},onClick={close {actions.compose(ComposeRequest(quote=post))}})
                DropdownMenuItem(text={Text(if(post.bookmarked)"移除书签" else "保存到书签")},enabled=!model.blocked(post.id),onClick={close {model.mutate(post,"bookmark")}})
                if(post.reposted)DropdownMenuItem(text={Text("撤销转推")},enabled=!model.blocked(post.id),onClick={close {model.mutate(post,"repost")}})
                if(accountState.accountId==post.author.id)DropdownMenuItem(text={Text("删除帖子",color=scheme.error)},enabled=!model.blocked(post.id),onClick={close {delete=true}})
            }}
        }
        Spacer(Modifier.height(12.dp))
        if(post.replyTo.isNotBlank()||post.replyToId.isNotBlank())Column(Modifier.padding(bottom=8.dp)) {Row(verticalAlignment=Alignment.CenterVertically) {Glyph("subdirectory_arrow_right",size=16,color=scheme.primary);Spacer(Modifier.width(6.dp));Text((replyParent?.author?.handle?:post.replyTo).let {if(it.isBlank())"回复帖子"else "回复 @"+it},style=MaterialTheme.typography.labelMedium,color=scheme.primary)};if(replyParent!=null&&showParentPreview)Surface(Modifier.padding(top=6.dp).fillMaxWidth().hapticClickable {model.openPost(replyParent)},shape=RoundedCornerShape(8.dp),color=scheme.surfaceContainerHighest.copy(alpha=.5f)) {Column(Modifier.padding(10.dp)){Text(replyParent.author.name,maxLines=1,overflow=TextOverflow.Ellipsis,style=MaterialTheme.typography.labelMedium);Text(replyParent.text.ifBlank {"查看原帖"},maxLines=2,overflow=TextOverflow.Ellipsis,style=MaterialTheme.typography.bodySmall)}}}
        if(post.text.isNotBlank())Box(Modifier.padding(vertical=8.dp)){TranslatableText(post,selectable=detail,maxLines=if(detail)Int.MAX_VALUE else 12)}
        if(settings.optBoolean("showSource") && post.source.isNotBlank())Text(post.source,style=MaterialTheme.typography.labelSmall)
        post.article?.let {article->FlutterCard(onClick={model.open(Feed("Article",post.id,"X 文章"),post=post)},modifier=Modifier.padding(horizontal=10.dp,vertical=5.dp)) {Column {article.cover?.let {NetworkImage(it.url,it.description,Modifier.fillMaxWidth().height(180.dp))};Column(Modifier.padding(12.dp)){Text(article.title,style=MaterialTheme.typography.titleMedium);if(article.preview.isNotBlank())Text(article.preview,maxLines=3,overflow=TextOverflow.Ellipsis);Text("阅读 X 文章 →")}}} }
        if(post.article==null)post.linkCard?.let {card->FlutterCard(onClick={actions.link(card.url)},modifier=Modifier.padding(horizontal=10.dp,vertical=5.dp)) {Column {if(safeMediaUrl(card.image))NetworkImage(card.image,null,Modifier.fillMaxWidth().height(150.dp));Column(Modifier.padding(12.dp)){Text(card.title,style=MaterialTheme.typography.titleSmall);Text(card.description,maxLines=2,overflow=TextOverflow.Ellipsis);Text(runCatching {java.net.URI(card.url).host}.getOrDefault(""))}}} }
        post.poll?.let {poll->
            val total=poll.votes.sum();val end=runCatching {Instant.parse(poll.endsAt)}.getOrNull();val ended=end?.isBefore(Instant.now())==true
            Column(Modifier.padding(vertical=12.dp)) {
                poll.choices.forEachIndexed {i,choice->val votes=poll.votes.getOrElse(i){0};Column(Modifier.padding(vertical=4.dp)) {
                    Text(choice+(if(poll.selected==i+1)" ✓"else "")+" · $votes 票"+(if(total==0L)""else " · "+String.format(Locale.ROOT,"%.1f",votes*100.0/total)+"%"))
                    LinearProgressIndicator(progress={if(total==0L)0f else votes.toFloat()/total},modifier=Modifier.fillMaxWidth(),strokeCap=StrokeCap.Butt,gapSize=0.dp,drawStopIndicator={})
                }}
                Text("$total 票"+(if(end==null)""else if(ended)" · 已结束"else " · 截止 "+end.atZone(ZoneId.systemDefault()).format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss.SSS"))))
                if(!ended)FlutterTextButton(onClick={runCatching {NativeServices.open(context,post.url)}.onFailure {model.message("无法打开浏览器")}}){Text("在 X 投票")}
            }
        }
        if(post.media.isNotEmpty())MediaGrid(post)
        if(post.quote!=null && !quoted) {Row(Modifier.padding(top=8.dp,bottom=6.dp),verticalAlignment=Alignment.CenterVertically){Glyph("format_quote",size=16);Spacer(Modifier.width(6.dp));Text("引用 @${post.quote.author.handle} 的帖子",style=MaterialTheme.typography.labelMedium)};PostCard(model.effective(post.quote),quoted=true)}
        if(!quoted)Row(Modifier.padding(top=2.dp)) {
            ActionCell("回复","chat_bubble_outline",compact(post.replies),enabled=!detail,onClick={model.openPost(post)})
            ActionCell("转发","repeat",compact(post.reposts),if(post.reposted)scheme.primary else null,!model.blocked(post.id)){model.mutate(post,"repost")}
            ActionCell("喜欢",if(post.liked)"favorite" else "favorite_border",compact(post.likes),if(post.liked)scheme.error else null,!model.blocked(post.id)){model.mutate(post,"like")}
            ActionCell("查看次数","bar_chart_rounded",compact(post.views),enabled=false,onClick={})
            ActionCell("书签",if(post.bookmarked)"bookmark" else "bookmark_border_rounded",null,if(post.bookmarked)scheme.primary else null,!model.blocked(post.id)){model.mutate(post,"bookmark")}
            ActionCell("分享","share_outlined",null,onClick={NativeServices.share(context,post.url,"分享帖子")})
        }
        if(post.id in accountState.uncertain)Text("操作结果待核对，请刷新后再操作",Modifier.padding(top=8.dp))
    }
    if(!quoted && !connectedBelow)HorizontalDivider(thickness=1.dp,color=scheme.outlineVariant)
    }
    if(delete)FlutterAlertDialog(onDismissRequest={delete=false},title={Text("删除帖子？")},text={Text("删除后无法恢复。")},confirmButton={FlutterTextButton(onClick={delete=false;model.mutate(post,"delete")}){Text("删除")}},dismissButton={FlutterTextButton(onClick={delete=false}){Text("取消")}})
}
@Composable private fun postIconColor() = if (LocalDarkTheme.current) Color.White else Color(0xDD000000)

@Composable private fun RowScope.ActionCell(label:String,icon:String,count:String?,color:Color?=null,enabled:Boolean=true,onClick:()->Unit) {
    Row(Modifier.weight(1f).height(40.dp).clip(RoundedCornerShape(18.dp)).hapticClickable(enabled=enabled,onClickLabel=label,onClick=onClick),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.Center) {Glyph(icon,label,size=17,color=color ?: postIconColor());if(count!=null){Spacer(Modifier.width(3.dp));Text(count,fontSize=11.sp,color=color ?: MaterialTheme.colorScheme.onSurfaceVariant,maxLines=1)}}
}
fun compact(n:Long)=when {n>=1000000->"%.1f".format(Locale.ROOT,n/1000000.0).removeSuffix(".0")+"M";n>=1000->"%.1f".format(Locale.ROOT,n/1000.0).removeSuffix(".0")+"K";else->n.toString()}
fun parseDate(raw:String):ZonedDateTime?=runCatching {ZonedDateTime.parse(raw,DateTimeFormatter.ofPattern("EEE MMM dd HH:mm:ss Z yyyy",Locale.US))}.getOrNull() ?: runCatching {Instant.parse(raw).atZone(ZoneOffset.UTC)}.getOrNull()
fun postTime(raw:String,settings:org.json.JSONObject):String {
    val parsed=parseDate(raw) ?: return "";val date=parsed.withZoneSameInstant(if(settings.optBoolean("utcTime"))ZoneOffset.UTC else ZoneId.systemDefault());val minutes=Duration.between(parsed.toInstant(),Instant.now()).toMinutes()
    if(settings.optBoolean("relativeTime",true) && minutes in 0..1439)return if(minutes==0L)"刚刚" else if(minutes<60)"$minutes 分钟前" else "${minutes/60} 小时前"
    val pattern=(if(settings.optBoolean("showYear"))"yyyy-" else "")+"MM-dd"+(if(settings.optBoolean("showWeekday"))" E" else "")+" HH:mm"+(if(settings.optBoolean("showSeconds"))":ss" else "")
    return date.format(DateTimeFormatter.ofPattern(pattern,Locale.CHINA))+(if(settings.optBoolean("utcTime"))" UTC" else "")
}
@Composable fun RichText(text:String,style:TextStyle=MaterialTheme.typography.bodyMedium,maxLines:Int=Int.MAX_VALUE,selectable:Boolean=false) {
    val actions=LocalActions.current;val color=if(LocalReading.current.optBoolean("coloredLinks",true))MaterialTheme.colorScheme.primary else style.color
    val annotated=buildAnnotatedString {
        append(text)
        textLinks(text).forEach {range->
            val target=textLinkUrl(range.value)
            addLink(LinkAnnotation.Clickable(target,TextLinkStyles(style=SpanStyle(color=color))){actions.link(target)},range.offset,range.offset+range.length)
        }
    }
    val content:@Composable ()->Unit={Text(annotated,style=style,maxLines=maxLines,overflow=TextOverflow.Ellipsis)}
    if(selectable)SelectionContainer {content()} else content()
}
@Composable fun TranslatableText(post:Post,selectable:Boolean=false,maxLines:Int=Int.MAX_VALUE) {
    val settings=LocalReading.current;val model=LocalActions.current.model;val scope=rememberCoroutineScope()
    var translated by remember(post.text) {mutableStateOf(NativeServices.cachedTranslation(post.text))};var busy by remember(post.text) {mutableStateOf(false)}
    val auto=settings.optBoolean("grokAutoTranslate");var override by remember(post.id,post.text,post.translated,auto) {mutableStateOf<Boolean?>(null)}
    val needed=NativeServices.needsTranslation(post.text)
    suspend fun translate(){if(busy)return;busy=true;try{translated=NativeServices.translate(post.text)}catch(e:CancellationException){throw e}catch(_:Exception){}finally{busy=false}}
    LaunchedEffect(post.text,post.translated,auto){if(auto && post.translated.isBlank() && needed && translated==null)translate()}
    val available=post.translated.ifBlank {translated.orEmpty()};val shown=override ?: auto
    val style=MaterialTheme.typography.bodyMedium.copy(fontSize=settings.optDouble("fontSize",16.0).toFloat().sp,lineHeight=(settings.optDouble("fontSize",16.0)*settings.optDouble("lineHeight",1.5)).toFloat().sp)
    Column {RichText(if(shown&&available.isNotBlank())available else post.text,style,maxLines,selectable)
        if(available.isNotBlank()||needed)FlutterTextButton(onClick={if(available.isNotBlank())override=!shown else scope.launch {translate();if(translated!=null)override=true}},enabled=!busy,contentPadding=PaddingValues(horizontal=4.dp),modifier=Modifier.heightIn(min=32.dp)) {
            if(busy)FlutterProgress(Modifier.size(14.dp),strokeWidth=2.dp)else Glyph("translate",size=18);Spacer(Modifier.width(8.dp));Text(if(busy)"正在翻译…"else if(available.isNotBlank()&&shown)"显示原文"else if(post.translated.isNotBlank())"Grok 翻译"else "由 Google 翻译")
        }
    }
}
@Composable fun MediaGrid(post:Post) {
    var revealed by rememberSaveable(post.id) {mutableStateOf(false)};val settings=LocalReading.current;val actions=LocalActions.current
    val galleryScope=remember(post.id){Any()}
    if(post.sensitive && !revealed && !settings.optBoolean("showSensitive")) {FlutterOutlinedButton(onClick={revealed=true}){Glyph("visibility_outlined",size=18);Spacer(Modifier.width(8.dp));Text("显示 X 标记为敏感的媒体")};return}
    val media=post.media;val radius=settings.optDouble("imageRadius",16.0).dp;val screenHeight=LocalConfiguration.current.screenHeightDp.dp
    val bounds=remember(post.id){mutableMapOf<Int,androidx.compose.ui.layout.LayoutCoordinates>()}
    val previews = remember(post.id, media) { mutableMapOf<Int, ImageBitmap>() }
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        @Composable fun tile(index:Int,modifier:Modifier) {val item=media[index];var sourceImage by remember(item.url){mutableStateOf<ImageBitmap?>(null)};Box(modifier.onGloballyPositioned {bounds[index]=it}.clip(RoundedCornerShape(radius)).hideGallerySource(galleryScope,index).hapticClickable {actions.gallery(GalleryRequest(media,index,post.author.handle,post,sourceAnchor={bounds[it]?.galleryAnchor()},sourceRadius=radius.value,sourceScope=galleryScope,sourceImage=sourceImage,previewImage={previews[it]}))}){NetworkImage(item.url,item.description,Modifier.fillMaxSize(),onImageReady={sourceImage=it;previews[index]=it});if(item.video)Glyph("play_circle_fill",size=48,color=Color.White,modifier=Modifier.align(Alignment.Center));if(item.description.isNotBlank())Text("ALT",color=Color.White,modifier=Modifier.align(Alignment.BottomStart).padding(8.dp).background(Color.Black.copy(alpha=.54f)).padding(4.dp))}}
        if(media.size==1) {val first=media.first();val ratio=if(settings.optBoolean("largeImages",true)&&first.width>0&&first.height>0)(first.width.toFloat()/first.height).coerceIn(.2f,3f) else 1.4f;val width=minOf(maxWidth,minOf(screenHeight*.42f,480.dp)*ratio);tile(0,Modifier.width(width).aspectRatio(ratio))}
        else Column(verticalArrangement=Arrangement.spacedBy(6.dp)) {for(i in media.indices step 2)Row(horizontalArrangement=Arrangement.spacedBy(6.dp)){tile(i,Modifier.weight(1f).aspectRatio(1f));if(i+1<media.size)tile(i+1,Modifier.weight(1f).aspectRatio(1f)) else Spacer(Modifier.weight(1f))}}
    }
}
@Composable fun ComposerScreen(request:ComposeRequest,model:ReaderViewModel,onClose:()->Unit) {
    var text by rememberSaveable {mutableStateOf("")};var busy by remember {mutableStateOf(false)};var uncertain by rememberSaveable {mutableStateOf(false)};var error by remember {mutableStateOf<String?>(null)};var published by rememberSaveable {mutableStateOf<String?>(null)}
    val scope=rememberCoroutineScope();val context=LocalContext.current;val actions=LocalActions.current
    val measuredText=remember(text){composerText(text)}
    val focusRequester=remember {androidx.compose.ui.focus.FocusRequester()}
    val back = hapticClick(onClose)
    Dialog(onDismissRequest={if(!busy)onClose()},properties=DialogProperties(usePlatformDefaultWidth=false,decorFitsSystemWindows=false)) {
        val window = (LocalView.current.parent as? DialogWindowProvider)?.window
        val dark = LocalDarkTheme.current
        SideEffect { window?.applyReviewStatusBar(dark) }
        BackHandler {if(!busy)onClose()}
        Surface(Modifier.fillMaxSize(),color=LocalChrome.current.background) {Column {
            AppTopBar(if(request.reply!=null)"回复" else if(request.quote!=null)"引用帖子" else "发布帖子",leading={IconButton(onClick={if(!busy)back()}){Glyph("arrow_back","返回")}},actions={FlutterTextButton(enabled=!busy&&!uncertain&&published==null,onClick={busy=true;error=null;scope.launch {try{published=model.publish(text,request.reply,request.quote)}catch(e:CancellationException){throw e}catch(e:Exception){error=model.safeError(e);uncertain=e is ApiFailure && e.uncertain}finally{busy=false}}}){Text(if(busy)"提交中…" else "发布")}})
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).imePadding().padding(20.dp)) {
                request.reply?.let {Text("回复 @${it.author.handle}")};request.quote?.let {FlutterCard(Modifier.fillMaxWidth().padding(horizontal=10.dp,vertical=5.dp)){Text("@${it.author.handle}\n${it.text}",Modifier.padding(12.dp),maxLines=5,overflow=TextOverflow.Ellipsis)}}
                LaunchedEffect(Unit){focusRequester.requestFocus()}
                OutlinedTextField(text,{text=composerText(it).first},Modifier.fillMaxWidth().focusRequester(focusRequester),textStyle=MaterialTheme.typography.bodyLarge,readOnly=busy||uncertain||published!=null,minLines=6,placeholder={Text("有什么新鲜事？")},supportingText={Row(Modifier.fillMaxWidth()){Text("本页发布文字，X 会校验账号对应的长度限制",Modifier.weight(1f),maxLines=1,overflow=TextOverflow.Ellipsis);Spacer(Modifier.width(8.dp));Text("${measuredText.second}/10000")}})
                error?.let {Text(it,color=MaterialTheme.colorScheme.error)}
                if(uncertain){Text("这次发布结果尚未确认。请先在 X 主页核对，避免重复发布。");FlutterTextButton(onClick={NativeServices.open(context,"https://x.com/home")}){Text("在 X 核对")};FlutterTextButton(onClick={NativeServices.copy(context,text)}){Text("复制正文")}}
                published?.let {id->Text("X 已返回发布成功的帖子编号");SelectionContainer{Text(id)};FlutterTextButton(onClick={onClose();actions.link("https://x.com/i/status/$id")}){Text("查看已发布帖子")};Button(onClick=onClose,modifier=Modifier.fillMaxWidth()){Text("完成")}}
            }
        } }
    }
}



internal fun composerText(raw:String):Pair<String,Int> {
    val boundaries=android.icu.text.BreakIterator.getCharacterInstance(java.util.Locale.ROOT);boundaries.setText(raw)
    var count=0;var end=boundaries.first();var next=boundaries.next()
    while(next!=android.icu.text.BreakIterator.DONE&&count<10000){end=next;count++;next=boundaries.next()}
    return raw.substring(0,end) to count
}
