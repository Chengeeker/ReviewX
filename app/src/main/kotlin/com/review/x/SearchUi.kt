package com.review.x

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.*
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.*
import kotlinx.coroutines.*

class SearchUi {
    var query by mutableStateOf("")
    var focused by mutableStateOf(false)
    var users by mutableStateOf<List<User>>(emptyList())
    var busy by mutableStateOf(false)
}

@Composable fun SearchSuggestions(model:ReaderViewModel,state:ReaderState,search:SearchUi,header:Dp) {
    val focus=LocalFocusManager.current;val recent=state.accountId?.let(model.settings::searches).orEmpty()
    val query=search.query.trim()
    LaunchedEffect(query,search.focused,state.accountId) {
        search.users=emptyList();search.busy=false
        if(!search.focused || query.length<2)return@LaunchedEffect
        search.busy=true
        try {delay(350);search.users=model.suggestedUsers(query)}catch(e:CancellationException){throw e}catch(_:Exception){}finally {search.busy=false}
    }
    if(!search.focused || query.isBlank()&&recent.isEmpty())return
    fun submit(text:String){focus.clearFocus();model.search(text)}
    BoxWithConstraints(Modifier.fillMaxSize()) {
        Box(Modifier.fillMaxSize().padding(top=header).clickable(interactionSource=remember {androidx.compose.foundation.interaction.MutableInteractionSource()},indication=null){focus.clearFocus()})
        Surface(Modifier.padding(start=12.dp,end=12.dp,top=header+4.dp).fillMaxWidth().heightIn(max=(maxHeight-header-88.dp).coerceAtLeast(0.dp)),shape=RoundedCornerShape(16.dp),shadowElevation=8.dp,color=MaterialTheme.colorScheme.surface) {
            LazyColumn {
                if(query.isBlank()) {
                    item {Row(Modifier.padding(start=16.dp,top=8.dp,end=8.dp),verticalAlignment=Alignment.CenterVertically){Text("最近",Modifier.weight(1f),style=MaterialTheme.typography.titleMedium,fontWeight=FontWeight.Bold);FlutterTextButton(onClick={state.accountId?.let {model.setSetting("search_history_$it","[]")}}){Text("清除全部")}}}
                    items(recent,key={it}) {text->FlutterListItem(headlineContent={Text(text,maxLines=1,overflow=TextOverflow.Ellipsis)},leadingContent={Glyph("history_rounded")},trailingContent={IconButton(onClick={state.accountId?.let {model.settings.removeSearch(it,text)}}){Glyph("close_rounded","移除搜索记录")}},modifier=Modifier.clickable {submit(text)})}
                } else {
                    item {FlutterListItem(headlineContent={Text(query,maxLines=1,overflow=TextOverflow.Ellipsis)},leadingContent={Glyph("search_rounded")},trailingContent={if(search.busy)FlutterProgress(Modifier.size(18.dp),strokeWidth=2.dp)},modifier=Modifier.clickable {submit(query)})}
                    items(recent.filter {it.startsWith(query,true)&&!it.equals(query,true)}.take(4),key={it}) {text->FlutterListItem(headlineContent={Text(text,maxLines=1,overflow=TextOverflow.Ellipsis)},leadingContent={Glyph("history_rounded")},modifier=Modifier.clickable {submit(text)})}
                    if(search.users.isNotEmpty())item {FlutterDivider(height=1.dp)}
                    items(search.users,key={it.id}) {user->FlutterListItem(headlineContent={Text(user.name,maxLines=1,overflow=TextOverflow.Ellipsis)},supportingContent={Text("@${user.handle}",maxLines=1)},leadingContent={Avatar(user,42)},modifier=Modifier.clickable {focus.clearFocus();model.openUser(user)})}
                }
            }
        }
    }
}

@Composable fun SearchResults(model:ReaderViewModel,state:ReaderState,list:LazyListState) {
    Column {
        Box(Modifier.padding(12.dp)){SearchField(model,state)}
        Row(Modifier.horizontalScroll(rememberScrollState())) {listOf("Top" to "热门","Latest" to "最新","People" to "用户","Photos" to "图片","Videos" to "视频").forEach {(key,title)->
            val selected=state.screen.feed.option==key
            Box(Modifier.padding(horizontal=4.dp).height(48.dp),contentAlignment=Alignment.Center){CompositionLocalProvider(LocalMinimumInteractiveComponentSize provides 0.dp){FilterChip(selected,{model.search(state.screen.feed.value,key)},label={Text(title,Modifier.padding(horizontal=1.dp))},leadingIcon=if(selected)({Glyph("check",size=18)})else null,modifier=Modifier.height(38.dp),colors=FilterChipDefaults.filterChipColors(containerColor=MaterialTheme.colorScheme.surface))}}
        }}
        Box(Modifier.weight(1f)){TimelineScreen(model,state,list,24)}
    }
}
