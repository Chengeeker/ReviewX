package com.review.x

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.*
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.*
import kotlin.math.roundToInt

@Composable internal fun RequestStatus(loading:Boolean,error:String?,onRetry:()->Unit) {
    if(!loading&&error==null)return
    Surface(color=MaterialTheme.colorScheme.surfaceContainer){
        Row(Modifier.fillMaxWidth().padding(horizontal=16.dp,vertical=8.dp),verticalAlignment=Alignment.CenterVertically){
            if(loading)FlutterProgress(Modifier.size(18.dp),strokeWidth=2.dp)else Glyph("info_outline",size=20)
            Spacer(Modifier.width(12.dp));Text(if(loading)"正在连接 X… 若等待较久，请检查 VPN 或代理"else error.orEmpty(),Modifier.weight(1f))
            if(!loading)FlutterTextButton(onClick=onRetry){Text("重试")}
        }
    }
}

@Composable internal fun OriginalListFooter(screen:ReaderScreen,userList:Boolean,onMore:()->Unit) {
    val notifications=screen.feed.kind=="NotificationsTimeline"
    val empty=if(notifications)screen.notifications.isEmpty()else if(userList)screen.users.isEmpty()else screen.posts.isEmpty()
    Column(Modifier.fillMaxWidth().padding(if(notifications||userList)20.dp else 24.dp),horizontalAlignment=Alignment.CenterHorizontally){
        if (screen.busy) return@Column
        if(notifications||userList){
                if(screen.cursor!=null||screen.error!=null)FlutterTextButton(onClick=onMore){Text(if(screen.error==null)"加载更多"else if(notifications)"重新加载"else "重试")}
                if(empty&&screen.error==null)Text(if(notifications)"暂无通知"else "没有用户")
        }else {
            if(screen.canLoadMore)FilledTonalButton(onClick=onMore){Text(if(screen.error!=null)"重试加载"else "加载更多")}
            if(screen.loaded&&screen.error==null&&!screen.canLoadMore)Text(if(empty)"暂无帖子，下拉刷新"else "没有更多帖子")
        }
    }
}

private val drawerDestinations = listOf(
    Triple("bookmarks_outlined", "历史", "Bookmarks"),
    Triple("notifications_outlined", "通知", "NotificationsTimeline"),
    Triple("history_rounded", "本机浏览历史", "LocalHistory"),
)
private val drawerRowPadding = 20.dp
private val drawerIconWidth = 24.dp
private val drawerIconGap = 12.dp

@Composable internal fun OriginalDrawer(state:ReaderState,onProfile:()->Unit,onRoute:(String,String)->Unit) {
    val appDensity = LocalDensity.current
    val drawerDensity = remember(appDensity) {
        object : Density by appDensity {
            // Use the app's scaled SP conversion for text layout as well as DP sizing.
            override fun TextUnit.toPx(): Float = with(appDensity) { this@toPx.toDp().toPx() }
            override fun TextUnit.roundToPx(): Int = toPx().roundToInt()
        }
    }
    CompositionLocalProvider(LocalDensity provides drawerDensity) {
        val rowStyle = LocalTextStyle.current.copy(fontSize = 15.sp, fontWeight = FontWeight.Medium)
        val measurer = rememberTextMeasurer()
        val labelWidth = remember(measurer, rowStyle) {
            drawerDestinations.maxOf { (_, title, _) ->
                measurer.measure(title, style = rowStyle, maxLines = 1).size.width
            }
        }
        val density = LocalDensity.current
        val direction = LocalLayoutDirection.current
        val insets = DrawerDefaults.windowInsets
        val contentWidth = with(density) {
            (labelWidth + 2 * drawerRowPadding.roundToPx() + drawerIconWidth.roundToPx() + drawerIconGap.roundToPx() +
                insets.getLeft(this, direction) + insets.getRight(this, direction)).toDp()
        }
        val colors=MaterialTheme.colorScheme
        BoxWithConstraints {
            val width = minOf(contentWidth, 240.dp, maxWidth * 0.8f)
            ModalDrawerSheet(Modifier.width(width), drawerContainerColor = LocalChrome.current.background, windowInsets = insets) {
                Column(Modifier.padding(start=20.dp,top=20.dp,end=16.dp,bottom=12.dp).clip(RoundedCornerShape(12.dp)).hapticClickable(onClick=onProfile).padding(4.dp)) {
                    Box(Modifier.size(64.dp).clip(CircleShape).background(colors.secondaryContainer),contentAlignment=Alignment.Center){
                        if(!state.user?.avatar.isNullOrEmpty())NetworkImage(state.user!!.avatar,state.user.name,Modifier.fillMaxSize())else Glyph("person_rounded",size=36,color=colors.onSecondaryContainer)
                    }
                    Spacer(Modifier.height(14.dp));Text(state.user?.name?:if(state.loggedIn)"X 已登录"else "未登录 / 访客",maxLines=1,overflow=TextOverflow.Ellipsis,fontSize=16.5.sp,lineHeight=25.sp,fontWeight=FontWeight.Bold)
                    state.user?.let{Text("@${it.handle}",Modifier.padding(top=2.dp),maxLines=1,overflow=TextOverflow.Ellipsis,style=MaterialTheme.typography.bodySmall,color=colors.onSurfaceVariant)}
                }
                FlutterDivider(height=1.dp)
                Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(vertical=6.dp)) {
                    drawerDestinations.forEach { (icon, title, kind) ->
                        Row(Modifier.fillMaxWidth().heightIn(min=48.dp).clip(RoundedCornerShape(16.dp)).hapticClickable{onRoute(kind,title)}.padding(horizontal=drawerRowPadding),verticalAlignment=Alignment.CenterVertically){
                            Box(Modifier.width(drawerIconWidth)){Glyph(icon,size=22,color=colors.onSurfaceVariant)}
                            Spacer(Modifier.width(drawerIconGap))
                            Text(title, style = rowStyle)
                        }
                    }
                }
            }
        }
    }
}

@Composable internal fun DetailLoading(error:String?,onRetry:()->Unit) {
    Box(Modifier.fillMaxSize(),contentAlignment=Alignment.Center){
        if(error==null)FlutterProgress()else Column(horizontalAlignment=Alignment.CenterHorizontally){Text(error,textAlign=TextAlign.Center);Spacer(Modifier.height(12.dp));FilledTonalButton(onClick=onRetry){Text("重试")}}
    }
}

@Composable internal fun ExpiredSessionBanner(onLogin:()->Unit) {
    Surface(color=MaterialTheme.colorScheme.surfaceContainerLow){Column{
        Row(Modifier.fillMaxWidth().padding(start=16.dp,top=2.dp),verticalAlignment=Alignment.CenterVertically){
            Text("X 会话已过期，请重新登录",Modifier.weight(1f));Box(Modifier.heightIn(min=52.dp).padding(horizontal=8.dp),contentAlignment=Alignment.Center){FlutterTextButton(onClick=onLogin){Text("重新登录")}}
        }
        HorizontalDivider(thickness=.5.dp,color=MaterialTheme.colorScheme.outlineVariant)
    }}
}
