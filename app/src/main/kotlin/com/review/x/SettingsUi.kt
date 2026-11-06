package com.review.x

import android.Manifest
import android.app.Activity
import android.content.Context
import android.os.Build
import android.view.WindowManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.*
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.foundation.shape.*
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.*
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.input.pointer.*
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.*
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.*
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.*
import kotlinx.coroutines.*
import org.json.JSONObject
import kotlin.math.roundToInt

val LocalCompactSettingsRows=staticCompositionLocalOf {false}
@Composable fun SettingRow(title:String,subtitle:String?=null,icon:String?=null,onClick:(()->Unit)?=null,trailing:(@Composable ()->Unit)?=null,titleStyle:TextStyle=flutterTileTitle(),subtitleStyle:TextStyle=flutterTileSubtitle(),minHeight:Dp=if(subtitle!=null)78.dp else 62.dp,iconColor:Color=MaterialTheme.colorScheme.onSurfaceVariant) {
    Row(Modifier.fillMaxWidth().heightIn(min=minHeight).clip(RoundedCornerShape(16.dp)).then(if(onClick!=null)Modifier.hapticClickable(onClick=onClick)else Modifier).padding(horizontal=16.dp,vertical=3.dp),verticalAlignment=Alignment.CenterVertically) {
        if(icon!=null){Glyph(icon,color=iconColor);Spacer(Modifier.width(16.dp))};FlutterTileText(Modifier.weight(1f),minHeight-6.dp,titleStyle,subtitleStyle,{Text(title)},subtitle?.let{value->{Text(value)}})
        if(trailing!=null){Spacer(Modifier.width(12.dp));trailing()}else if(onClick!=null)Glyph("chevron_right_rounded",color=MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
@Composable fun Section(title:String,content:@Composable ColumnScope.()->Unit) {
    Column {Text(title,Modifier.padding(start=16.dp,end=16.dp,bottom=12.dp),style=MaterialTheme.typography.titleSmall,color=MaterialTheme.colorScheme.primary);Surface(shape=RoundedCornerShape(24.dp),color=MaterialTheme.colorScheme.surfaceContainerLow){Column(content=content)}}
}
@Composable fun SettingSwitch(title:String,value:Boolean,onChange:(Boolean)->Unit,subtitle:String?=null,icon:String?=null,enabled:Boolean=true) {
    val toggle = hapticClick { onChange(!value) }
    SettingRow(title, subtitle, icon, onClick = if (enabled) ({ onChange(!value) }) else null, trailing = {
        CompositionLocalProvider(LocalMinimumInteractiveComponentSize provides 0.dp) {
            Switch(value, onCheckedChange = if (enabled) ({ toggle() }) else null,
                enabled = enabled, modifier = Modifier.padding(horizontal=4.dp))
        }
    })
}
@Composable fun Choice(title:String,selected:Boolean,onClick:()->Unit,subtitle:String?=null,titleStyle:TextStyle=flutterTileTitle(),subtitleStyle:TextStyle=flutterTileSubtitle(),horizontalPadding:Dp=16.dp,rowHeight:Dp=if(subtitle==null)62.dp else 78.dp,verticalPadding:Dp=3.dp) {
    Row(Modifier.fillMaxWidth().heightIn(min=rowHeight).selectable(selected=selected,role=androidx.compose.ui.semantics.Role.RadioButton,onClick=hapticClick(onClick)).padding(horizontal=horizontalPadding,vertical=verticalPadding),verticalAlignment=Alignment.CenterVertically) {
        FlutterRadio(selected);Spacer(Modifier.width(16.dp));FlutterTileText(Modifier.weight(1f),rowHeight-verticalPadding*2,titleStyle,subtitleStyle,{Text(title)},subtitle?.let{value->{Text(value)}})
    }
}
@Composable fun SettingsHome(model:ReaderViewModel,state:ReaderState) {
    var about by remember {mutableStateOf(false)}
    fun open(kind:String,title:String){model.open(Feed(kind,title=title))}
    CompositionLocalProvider(LocalCompactSettingsRows provides true) {
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(top=LocalHeaderInset.current).padding(start=16.dp,top=20.dp,end=16.dp,bottom=if(!state.settings.optBoolean("floating_nav",true))24.dp else if(state.settings.optBoolean("use_liquid_glass_effect"))76.dp+WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding() else 76.dp+(if(WindowInsets.navigationBars.getBottom(LocalDensity.current)>0)6.dp else 14.dp)+WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()),verticalArrangement=Arrangement.spacedBy(32.dp)) {
        Section("偏好与功能") {SettingRow("个性化",icon="palette_outlined",onClick={open("Theme","个性化")});SettingRow("帖子与阅读样式",icon="article_outlined",onClick={open("Reading","帖子与阅读样式")});SettingRow("网络设置",icon="language_outlined",onClick={open("Network","网络设置")});SettingRow("订阅消息提醒",icon="notifications_active_outlined",onClick={open("NotificationSettings","订阅消息提醒")})}
        Section("存储与备份") {SettingRow("存储设置",icon="folder_open_outlined",onClick={open("Storage","存储设置")});SettingRow("缓存管理","查看与清理应用缓存","cleaning_services_outlined",{open("Cache","缓存管理")});SettingRow("WebDAV备份",icon="cloud_sync_outlined",onClick={open("WebDAV","WebDAV备份")})}
        Section("账号与应用") {SettingRow(if(state.loggedIn)state.user?.name ?: "X 账号" else "登录 X 账号",state.accountId?.let {"UID：$it"},"person_outline_rounded",{if(state.loggedIn)open("Account","账号管理")else open("Login","账号登录")});SettingRow("导出诊断日志","遇到问题时分享给开发者","bug_report_outlined",{open("Diagnostics","诊断日志")});SettingRow("关于 ReviewX",icon="info_outline_rounded",onClick={about=true})}
    }
    }
    if(about)AboutDialog {about=false}
}
@Composable fun SettingsScreen(kind:String,model:ReaderViewModel,state:ReaderState) {
    when(kind) {
        "Theme"->ThemeSettings(model,state)
        "Reading"->ReadingSettings(model)
        "Network"->NetworkSettings(model)
        "NotificationSettings"->NotificationSettings(model,state)
        "Storage"->StorageSettings(model,state)
        "Cache"->CacheSettings(model)
        "WebDAV"->WebDavSettings(model)
        "Account"->AccountSettings(model,state)
        "Display"->DisplaySettings(model,state)
        "Diagnostics"->DiagnosticsSettings(model)
        "About"->AboutDialog {model.back()}
        "Licenses"->LicensesScreen()
    }
}
@Composable fun ThemeSettings(model:ReaderViewModel,state:ReaderState) {
    val settings=state.settings;var weights by remember {mutableStateOf(false)}
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(top=LocalHeaderInset.current).padding(start=16.dp,top=12.dp,end=16.dp,bottom=24.dp).navigationBarsPadding(),verticalArrangement=Arrangement.spacedBy(32.dp)) {
        Section("明暗模式"){listOf("跟随系统","浅色模式","深色模式").forEachIndexed {i,title->Choice(title,settings.optInt("theme_mode")==i,{model.setSetting("theme_mode",i)})};SettingSwitch("纯黑深色模式 (OLED 省电)",settings.optBoolean("key_is_pure_black_dark"),{model.setSetting("key_is_pure_black_dark",it)},icon="contrast_rounded")}
        Section("色彩方案"){SettingSwitch("动态取色",settings.optBoolean("use_dynamic_color"),{model.setSetting("use_dynamic_color",it)},icon="auto_awesome_outlined");if(!settings.optBoolean("use_dynamic_color")){Text("预置主题配色搭配",Modifier.padding(start=16.dp,top=12.dp,end=16.dp,bottom=10.dp),style=MaterialTheme.typography.bodyMedium,color=MaterialTheme.colorScheme.onSurfaceVariant);FlowRow(Modifier.align(Alignment.CenterHorizontally).padding(start=16.dp,end=16.dp,bottom=12.dp),horizontalArrangement=Arrangement.spacedBy(12.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {val colors=listOf(0xFFFA2F3A,0xFFFF8200,0xFF1976D2,0xFF2E7D32,0xFF7B1FA2,0xFFE91E63,0xFF00897B,0xFF455A64);listOf("经典红","活力橙","极光蓝","翡翠绿","优雅紫","樱花粉","青碧色","经典黑灰").forEachIndexed {i,title->FlutterColorChip(title,Color(colors[i]),settings.optInt("key_theme_color_index")==i){model.setSetting("key_theme_color_index",i)}}}}}
        Section("字体粗细"){SettingRow("自定义应用字体粗细","当前：${weightName(settings.optInt("font_weight_delta"))}","format_bold_rounded",{weights=true})}
        Section("字体大小"){Row(Modifier.padding(start=16.dp),verticalAlignment=Alignment.CenterVertically){Glyph("format_size_rounded");Box(Modifier.weight(1f)){ReadingSlider("应用字体大小","appTextScale",.8f,1.4f,12,model,percent=true)}}}
        Section("导航布局风格"){SettingSwitch("悬浮胶囊底栏 (MD3 Expressive)",settings.optBoolean("floating_nav",true),{model.setSetting("floating_nav",it)},icon="dock_rounded")}
        Section("界面效果"){SettingSwitch("使用液态玻璃效果",settings.optBoolean("use_liquid_glass_effect"),{model.setSetting("use_liquid_glass_effect",it)},"应用于悬浮底栏和图片画廊按钮","blur_on_rounded")}
        Section("屏幕显示"){SettingRow("屏幕帧率设置",icon="speed_rounded",onClick={model.open(Feed("Display",title="屏幕刷新率"))})}
        Section("触感与震动"){SettingSwitch("触感与震动反馈",settings.optBoolean("haptics",true),{model.setSetting("haptics",it)},icon="vibration_rounded")}
    }
    if(weights)FlutterAlertDialog(onDismissRequest={weights=false},contentPadding=PaddingValues(vertical=12.dp),title={Text("选择字体粗细")},text={Column{listOf(-100,0,100,200,300).forEach {delta->Choice(weightName(delta),settings.optInt("font_weight_delta")==delta,{model.setSetting("custom_font_weight",true);model.setSetting("font_weight_delta",delta);weights=false},titleStyle=flutterTileTitle().copy(fontWeight=flutterWeight(if(settings.optInt("font_weight_delta")==delta)700 else 600),color=if(settings.optInt("font_weight_delta")==delta)MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface),horizontalPadding=20.dp,rowHeight=60.dp)}}},confirmButton={FlutterTextButton(onClick={weights=false}){Text("取消")}})
}
fun weightName(delta:Int)=when(delta){-100->"偏细";100->"中等";200->"偏粗";300->"加粗";else->"默认"}
@Composable fun ReadingSlider(title:String,key:String,min:Float,max:Float,divisions:Int,model:ReaderViewModel,percent:Boolean=false) {
    val value=LocalReading.current.optDouble(key).toFloat();var draft by remember(value) {mutableFloatStateOf(value)}
    Column(Modifier.padding(horizontal=16.dp,vertical=8.dp)){Text(if(percent)title else "$title ${"%.1f".format(draft)}",style=flutterTileTitle());if(percent)Text("${(draft*100).roundToInt()}%",style=flutterTileSubtitle());OriginalSlider(draft,{draft=it;model.previewReading(key,it.toDouble())},min..max,divisions,onFinished={model.setReading(key,draft.toDouble())},label=if(percent)"${(draft*100).toInt()}%"else null)}
}
@OptIn(ExperimentalMaterial3Api::class)
@Composable fun ReadingSettings(model:ReaderViewModel) {
    val settings=LocalReading.current
    BoxWithConstraints(Modifier.fillMaxSize()) {val previewHeight=minOf(maxHeight/2,360.dp);Column {
        Box(Modifier.fillMaxWidth().height(previewHeight).clipToBounds()) {ReadingPreview()}
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).navigationBarsPadding().padding(bottom=12.dp)) {
            linkedMapOf("relativeTime" to "相对时间","showYear" to "显示年份","showWeekday" to "显示星期","showSeconds" to "显示秒数","utcTime" to "使用 UTC 时间","showSource" to "显示发布来源","grokAutoTranslate" to "自动翻译外文推文","showBanner" to "显示主页背景图","cardBackground" to "帖子背景","largeImages" to "单图保留图片比例","defaultMutedVideo" to "默认静音播放视频","coloredLinks" to "链接使用主题色","showSensitive" to "直接显示标记为敏感的媒体","saveHistory" to "记录本机浏览历史").forEach { (key,title)->SettingSwitch(title,settings.optBoolean(key),{model.setReading(key,it)}) }
            var quality by remember {mutableStateOf(false)}
            SettingRow("默认视频清晰度",qualityName(settings.str("videoQuality")),onClick={quality=true},trailing={Glyph("arrow_drop_down")})
            if(quality)FlutterBottomSheet(onDismissRequest={quality=false},shape=RoundedCornerShape(topStart=16.dp,topEnd=16.dp)) {Column(Modifier.navigationBarsPadding()) {
                Text("默认视频清晰度",Modifier.padding(start=20.dp,top=16.dp,end=20.dp,bottom=8.dp),fontSize=16.sp,fontWeight=FontWeight.Bold)
                listOf("balanced" to "大幅降低缓冲与卡顿，秒开播放，画质适合移动屏幕","high" to "保持最高码率，需要极佳的网络带宽与代理环境","data_saver" to "消耗流量极低，弱网环境下播放更顺畅").forEach {(key,subtitle)->SettingRow(qualityName(key),subtitle,onClick={model.setReading("videoQuality",key);quality=false},trailing={if(settings.str("videoQuality")==key)Glyph("check_rounded",color=MaterialTheme.colorScheme.primary)})}
                Spacer(Modifier.height(8.dp))
            }}

            ReadingSlider("帖子与文章正文字号","fontSize",12f,24f,120,model);ReadingSlider("正文行距","lineHeight",1.1f,2f,9,model);ReadingSlider("图片圆角","imageRadius",0f,28f,280,model)
        }
    }}
}
fun qualityName(key:String)=when(key){"high"->"最高画质 (1080p/原画)";"data_saver"->"省流模式 (480p/360p)";else->"优先流畅 (720p/智能推荐)"}
@Composable fun ReadingPreview() {
    val post=remember {Post("reading-style-preview",User("preview-author","Review X","reviewx","","",verified=true),"A quiet moment. #日常 https://example.com",java.time.Instant.now().minusSeconds(300).toString(),listOf(Media("https://picsum.photos/id/1015/1200/500","",false,1200,500)),null,null,"",128,12,24,"记录生活中的片刻。#日常 https://example.com",false,views=2048,source="Review X")}
    Box(Modifier.fillMaxWidth().wrapContentHeight(Alignment.Top,unbounded=true).pointerInput(Unit){awaitPointerEventScope {while(true)awaitPointerEvent(PointerEventPass.Initial).changes.forEach {it.consume()}}}) {PostCard(post)}
}
@Composable fun NetworkSettings(model:ReaderViewModel) {
    val initial=remember {runCatching {NetworkConfig.parse(JSONObject(model.settings.string("network_config","{}")))}.getOrDefault(NetworkConfig())}
    var mode by rememberSaveable {mutableStateOf(initial.mode)};var host by rememberSaveable {mutableStateOf(initial.host)};var port by rememberSaveable {mutableStateOf(if(initial.port>0)initial.port.toString() else "")};var busy by remember {mutableStateOf(false)};var result by remember {mutableStateOf<String?>(null)};var menu by remember {mutableStateOf(false)};val scope=rememberCoroutineScope()
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(top=LocalHeaderInset.current).padding(start=16.dp,top=16.dp,end=16.dp,bottom=24.dp).navigationBarsPadding()) {
        Text("连接方式",color=MaterialTheme.colorScheme.primary,style=MaterialTheme.typography.titleSmall)
        Spacer(Modifier.height(12.dp))
        Box(Modifier.fillMaxWidth()) {Surface(onClick={menu=true},enabled=!busy,modifier=Modifier.fillMaxWidth().heightIn(min=56.dp),shape=RoundedCornerShape(12.dp),color=Color.Transparent,border=BorderStroke(1.dp,MaterialTheme.colorScheme.outline)){Row(Modifier.padding(horizontal=16.dp,vertical=16.dp),verticalAlignment=Alignment.CenterVertically){Text(when(mode){"manual"->"手动代理";"direct"->"直连";else->"自动"},Modifier.weight(1f),style=MaterialTheme.typography.titleMedium);Glyph("arrow_drop_down",color=MaterialTheme.colorScheme.onSurfaceVariant)}};DropdownMenu(menu,{menu=false}){listOf("automatic" to "自动","direct" to "直连","manual" to "手动代理").forEach{(key,title)->DropdownMenuItem(text={Text(title)},onClick={mode=key;menu=false;result=null})}}}
        Spacer(Modifier.height(12.dp))
        Text(when(mode){"manual"->"应用请求、视频和 X 登录网页使用此 HTTP 代理（支持 HTTPS CONNECT）；代理失败时不会回退直连。代理软件需保持运行。";"direct"->"应用请求、视频和 X 登录网页不使用 HTTP 代理。手机已开启的 VPN 仍会影响连接，不会绕过 VPN。";else->"启动时读取系统静态 HTTP 代理；应用请求、视频和 X 登录网页使用系统网络路由。VPN 由系统处理，不支持 PAC 自动代理脚本。"})
        if(mode=="manual"){Spacer(Modifier.height(20.dp));OutlinedTextField(host,{host=it;result=null},Modifier.fillMaxWidth(),label={Text("代理地址")},placeholder={Text("例如 127.0.0.1")},enabled=!busy,textStyle=MaterialTheme.typography.bodyLarge,singleLine=true,shape=RoundedCornerShape(12.dp));Spacer(Modifier.height(12.dp));OutlinedTextField(port,{port=it;result=null},Modifier.fillMaxWidth(),label={Text("端口")},placeholder={Text("填写代理软件提供的 HTTP 端口")},enabled=!busy,textStyle=MaterialTheme.typography.bodyLarge,singleLine=true,keyboardOptions=KeyboardOptions(keyboardType=KeyboardType.Number),shape=RoundedCornerShape(12.dp));Spacer(Modifier.height(12.dp));Text("目前支持主机名或 IPv4 地址、无需认证的 HTTP 代理。不支持 SOCKS、代理账号密码或机场订阅链接。")}
        Spacer(Modifier.height(24.dp));Text("设置用于应用内 API、图片、视频、下载和 WebDAV。外部浏览器遵循自身网络设置。保存后下次启动生效；仅切到后台不会应用新设置。")
        Spacer(Modifier.height(16.dp));FlowRow(horizontalArrangement=Arrangement.spacedBy(12.dp),verticalArrangement=Arrangement.spacedBy(8.dp)){FlutterOutlinedButton(enabled=!busy,onClick={busy=true;scope.launch{try{result=AppNetwork.test(NetworkConfig(mode,host.trim(),port.toIntOrNull()?:0))}catch(e:Exception){result=model.safeError(e)}finally{busy=false}}}){Glyph("network_check",size=18);Spacer(Modifier.width(8.dp));Text("测试连接")};Button(enabled=!busy,onClick={runCatching{val config=NetworkConfig(mode,host.trim(),port.toIntOrNull()?:0);config.validate();model.setSetting("network_config",config.json().toString());result="已保存，完全关闭应用后重新打开生效。"}.onFailure{result=model.safeError(it)}}){Text("保存")}}
        if(busy)LinearProgressIndicator(Modifier.fillMaxWidth().padding(16.dp));result?.let{Text(it,Modifier.padding(top=16.dp))}
    }
}
@Composable fun NotificationSettings(model:ReaderViewModel,state:ReaderState) {
    var busy by remember{mutableStateOf(false)};var error by remember{mutableStateOf<String?>(null)};val scope=rememberCoroutineScope()
    fun save(key:String,value:Boolean){busy=true;error=null;scope.launch{try{if(!model.setSetting(key,value))error="无法启用提醒，请检查通知权限和登录状态"}finally{busy=false}}}
    val launcher=rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()){granted->if(granted)save("notification_enabled",true)else{busy=false;error="无法启用提醒，请检查通知权限和登录状态"}}
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        Text("定期读取 X 官方通知；首次读取只建立基线。Android 系统安排至少 15 分钟一次的任务，省电策略可能延迟，无法保证即时通知。",Modifier.padding(16.dp))
        SettingSwitch("启用消息提醒",state.settings.optBoolean("notification_enabled"),{if(it && Build.VERSION.SDK_INT>=33){busy=true;error=null;launcher.launch(Manifest.permission.POST_NOTIFICATIONS)}else save("notification_enabled",it)},enabled=state.loggedIn&&!busy)
        listOf("mentions" to "提及与回复","likes" to "点赞","reposts" to "转发","followers" to "关注","other" to "其他通知").forEach{(key,title)->SettingSwitch(title,state.settings.optBoolean("notification_$key",true),{save("notification_$key",it)},enabled=!busy)}
        if(busy)LinearProgressIndicator(Modifier.fillMaxWidth())
        error?.let{Text(it,Modifier.padding(16.dp))}
    }
}
@OptIn(ExperimentalMaterial3Api::class)
@Composable fun StorageSettings(model:ReaderViewModel,state:ReaderState) {
    val reading=LocalReading.current;var selected by remember{mutableStateOf<String?>(null)}
    fun path(video:Boolean,mode:String):String=(if(video)"Movies" else "Pictures")+"/ReviewX/"+when(mode){"me"->(state.user?.handle ?: state.accountId ?: "MyProfile")+"/";"author"->"帖子作者账号/";else->""}
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(top=LocalHeaderInset.current).padding(horizontal=16.dp,vertical=12.dp).navigationBarsPadding()){Surface(shape=RoundedCornerShape(24.dp),color=MaterialTheme.colorScheme.surfaceContainerLow){Column{listOf(false,true).forEach{video->val key=if(video)"videoStorageFolder" else "imageStorageFolder";SettingRow(if(video)"视频存储路径" else "图片存储路径",path(video,reading.str(key)),if(video)"video_library_outlined" else "image_outlined",{selected=key},titleStyle=flutterTileTitle().copy(fontSize=16.sp,lineHeight=21.6.sp,fontWeight=FontWeight.SemiBold),subtitleStyle=flutterTileSubtitle().copy(fontSize=14.sp,lineHeight=19.6.sp),iconColor=MaterialTheme.colorScheme.primary)}}}}
    selected?.let{key->FlutterBottomSheet(onDismissRequest={selected=null}) {Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).navigationBarsPadding().padding(16.dp)) {
        Row(verticalAlignment=Alignment.CenterVertically){Text(if(key.startsWith("video"))"视频存储路径"else "图片存储路径",Modifier.weight(1f),fontSize=16.sp,fontWeight=FontWeight.Bold);IconButton(onClick={selected=null}){Glyph("close_rounded","关闭")}}
        Spacer(Modifier.height(6.dp));Text("保存"+(if(key.startsWith("video"))"视频"else "图片")+"时，文件将自动归类到系统相册对应文件夹。",fontSize=14.sp,color=MaterialTheme.colorScheme.onSurfaceVariant);Spacer(Modifier.height(12.dp))
        listOf("default" to "默认路径","me" to "按我的账号归类","author" to "按作者账号归类").forEach{(mode,title)->Choice(title,reading.str(key)==mode,{model.setReading(key,mode);selected=null},path(key.startsWith("video"),mode),titleStyle=flutterTileTitle().copy(fontSize=16.sp,lineHeight=21.6.sp,fontWeight=FontWeight.SemiBold),subtitleStyle=flutterTileSubtitle().copy(fontSize=14.sp,lineHeight=19.6.sp))}
    }}}

}
@Composable fun AppSectionCard(content:@Composable ColumnScope.()->Unit) {
    Surface(Modifier.fillMaxWidth().padding(horizontal=10.dp,vertical=5.dp),shape=RoundedCornerShape(24.dp),color=MaterialTheme.colorScheme.surfaceContainerLow){Column(content=content)}
}
fun formatBytes(bytes:Long)=when {bytes>=1073741824->"%.2f GB".format(java.util.Locale.ROOT,bytes/1073741824.0);bytes>=1048576->"%.1f MB".format(java.util.Locale.ROOT,bytes/1048576.0);bytes>=1024->"%.1f KB".format(java.util.Locale.ROOT,bytes/1024.0);else->bytes.toString()+" B"}
fun formatThreshold(mb:Int)=if(mb==0)"关闭自动清理"else if(mb>=1024)(mb/1024).toString()+" GB"else mb.toString()+" MB"
@Composable fun CacheSettings(model:ReaderViewModel) {
    val context=LocalContext.current;val scope=rememberCoroutineScope();var stats by remember{mutableStateOf<Map<String,Long>?>(null)};var busy by remember{mutableStateOf(false)};var loading by remember {mutableStateOf(true)};var error by remember {mutableStateOf<String?>(null)};var confirm by remember{mutableStateOf(false)};var threshold by remember{mutableStateOf(false)}
    suspend fun refresh(){loading=true;try{stats=withContext(Dispatchers.IO){NativeServices.cache(context)};error=null}catch(e:CancellationException){throw e}catch(_:Exception){error="缓存信息读取失败，请稍后重试"}finally{loading=false}}
    LaunchedEffect(Unit){refresh()}
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(top=LocalHeaderInset.current).padding(start=16.dp,top=12.dp,end=16.dp,bottom=32.dp).navigationBarsPadding()) {
        AppSectionCard {Column(Modifier.fillMaxWidth().padding(horizontal=20.dp,vertical=24.dp),horizontalAlignment=Alignment.CenterHorizontally) {
            Box(Modifier.size(56.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primaryContainer),contentAlignment=Alignment.Center){Glyph("cleaning_services_rounded",size=30,color=MaterialTheme.colorScheme.onPrimaryContainer)};Spacer(Modifier.height(16.dp))
            if(loading)FlutterProgress(Modifier.size(24.dp),strokeWidth=2.5.dp)else Text(error?:formatBytes(stats?.get("total")?:0),Modifier.flutterLineHeight(MaterialTheme.typography.headlineMedium.lineHeight),style=MaterialTheme.typography.headlineMedium,fontWeight=FontWeight.Bold,textAlign=TextAlign.Center,color=if(error==null)MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.error)
            Spacer(Modifier.height(4.dp));Text("可管理的应用缓存",color=MaterialTheme.colorScheme.onSurfaceVariant);Spacer(Modifier.height(8.dp));Text("图片与媒体、网络临时文件及系统运行时缓存",Modifier.flutterLineHeight(MaterialTheme.typography.bodySmall.lineHeight),style=MaterialTheme.typography.bodySmall,textAlign=TextAlign.Center)
            if(!loading&&error==null){Spacer(Modifier.height(24.dp));listOf("images" to "图片与媒体","network" to "网络与临时文件","system" to "系统运行时").forEach{(key,title)->Row(Modifier.fillMaxWidth().padding(vertical=4.dp)){Text(title,Modifier.weight(1f).flutterLineHeight(MaterialTheme.typography.bodySmall.lineHeight),style=MaterialTheme.typography.bodySmall);Text(formatBytes(stats?.get(key)?:0),Modifier.flutterLineHeight(MaterialTheme.typography.bodySmall.lineHeight),style=MaterialTheme.typography.bodySmall,fontWeight=FontWeight.SemiBold)}}}
        }}
        Spacer(Modifier.height(16.dp));AppSectionCard {Button(enabled=!busy&&!loading&&error==null,onClick={if(stats?.get("total")==0L)model.message("当前没有可清理的缓存")else confirm=true},modifier=Modifier.padding(16.dp).fillMaxWidth().height(48.dp),shape=RoundedCornerShape(12.dp),contentPadding=PaddingValues(start=16.dp,end=24.dp)){if(busy)FlutterProgress(Modifier.size(18.dp),strokeWidth=2.dp,color=MaterialTheme.colorScheme.onPrimary)else Glyph("delete_sweep_rounded",size=18);Spacer(Modifier.width(8.dp));Text(if(busy)"正在清理..."else "清理所有缓存")}}
        Spacer(Modifier.height(24.dp));Text("自动清理规则",Modifier.padding(horizontal=26.dp),style=MaterialTheme.typography.titleMedium,fontWeight=FontWeight.Bold);Spacer(Modifier.height(12.dp))
        AppSectionCard {SettingRow("自动清理缓存阈值","超过上限时逐步淘汰较少使用的图片。更改后在应用完全重启时生效","auto_delete_outlined",onClick=if(busy||loading)null else ({threshold=true}),trailing={Text(formatThreshold(model.settings.int("auto_clear_cache_threshold_mb",200)),fontSize=14.sp,color=MaterialTheme.colorScheme.primary,fontWeight=FontWeight.SemiBold)})}
        Spacer(Modifier.height(24.dp));AppSectionCard {Text("清理仅针对 Android 应用缓存目录，并清空 应用图片内存缓存；账号凭据、设置、本地时间线快照和已保存到相册的媒体不会受影响。缓存分类按文件路径估算；正在播放或保存的临时媒体可能需要重新加载。",Modifier.padding(16.dp),color=MaterialTheme.colorScheme.onSurfaceVariant,lineHeight=20.3.sp)}
        Spacer(Modifier.height(16.dp));FlutterTextButton(enabled=!busy&&!loading,onClick={scope.launch {refresh()}},modifier=Modifier.align(Alignment.CenterHorizontally),contentPadding=PaddingValues(start=12.dp,end=16.dp,top=8.dp,bottom=8.dp)){Glyph("refresh_rounded",size=18);Spacer(Modifier.width(8.dp));Text("刷新缓存占用")}
    }
    if(confirm)FlutterAlertDialog(onDismissRequest={confirm=false},title={Text("清理所有缓存？")},text={Text("将清理应用缓存目录中的临时文件，共 "+formatBytes(stats?.get("total")?:0)+"。账号、设置和本地时间线快照不会被清理。")},confirmButton={Button(onClick={confirm=false;busy=true;scope.launch{try{val released=stats?.get("total")?:0;NativeServices.clearCache(context);refresh();model.message("缓存清理完成，释放 "+formatBytes(released))}catch(e:CancellationException){throw e}catch(_:Exception){model.message("缓存清理失败，请稍后重试")}finally{busy=false}}}){Text("立即清理")}},dismissButton={FlutterTextButton(onClick={confirm=false}){Text("取消")}})
    if(threshold)FlutterAlertDialog(onDismissRequest={threshold=false},contentPadding=PaddingValues(vertical=8.dp),title={Text("选择自动清理阈值")},text={Column(Modifier.verticalScroll(rememberScrollState())){AppSettings.cacheThresholds.forEach{value->Choice(formatThreshold(value),model.settings.int("auto_clear_cache_threshold_mb",200)==value,onClick={threshold=false;model.setSetting("auto_clear_cache_threshold_mb",value)},titleStyle=flutterTileTitle().copy(fontSize=13.sp,lineHeight=17.55.sp),rowHeight=54.dp)}}},confirmButton={FlutterTextButton(onClick={threshold=false}){Text("取消")}})
}
@Composable fun WebDavSettings(model:ReaderViewModel) {
    var url by remember{mutableStateOf("")};var user by remember{mutableStateOf("")};var password by remember{mutableStateOf("")};var directory by remember{mutableStateOf("ReviewX")};var full by rememberSaveable{mutableStateOf(false)};var visible by remember{mutableStateOf(false)};var busy by remember{mutableStateOf(true)};var confirm by remember{mutableStateOf(false)};val scope=rememberCoroutineScope()
    LaunchedEffect(Unit){try{val config=withContext(Dispatchers.IO){model.backup.config()};url=config.str("url");user=config.str("user");password=config.str("password");directory=config.str("directory",if(config.has("url"))"" else "ReviewX")}catch(e:Exception){model.message("读取 WebDAV 配置失败")}finally{busy=false}}
    var operation by remember {mutableStateOf("")};var fieldErrors by remember{mutableStateOf<Map<String,String>>(emptyMap())}
    fun validate():Boolean{fieldErrors=webDavFormErrors(url,user,password);return fieldErrors.isEmpty()}
    fun run(action:String){if(busy||!validate())return;operation=action;busy=true;scope.launch{try{val config=JSONObject().put("url",url.trim()).put("user",user.trim()).put("password",password).put("directory",directory.trim());require(user.isNotBlank()&&password.isNotEmpty()){ "请输入用户名和密码或授权 Token" };withContext(Dispatchers.IO){model.backup.saveConfig(config)};when(action){"test"->model.message(model.backup.test(config));"upload"->{model.backup.upload(config,full);model.message("备份成功")};"restore"->{val raw=model.backup.download(config);withContext(Dispatchers.IO){model.backup.restore(raw,true)};model.message("恢复成功，请完全关闭应用后重新打开")}}}catch(e:CancellationException){throw e}catch(e:Exception){model.message(model.safeError(e))}finally{busy=false}}}
    val scheme=MaterialTheme.colorScheme
    @Composable fun backupCard(content:@Composable ColumnScope.()->Unit){Surface(shape=RoundedCornerShape(24.dp),color=if(scheme.surface==Color.Black)scheme.surfaceContainer else scheme.surfaceContainerLow){Column(content=content)}}
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(top=LocalHeaderInset.current).padding(start=16.dp,top=14.dp,end=16.dp,bottom=14.dp).navigationBarsPadding(),verticalArrangement=Arrangement.spacedBy(16.dp)) {
        Row(Modifier.fillMaxWidth().background(scheme.primaryContainer.copy(alpha=.4f),RoundedCornerShape(16.dp)).border(1.dp,scheme.primary.copy(alpha=.2f),RoundedCornerShape(16.dp)).padding(14.dp)) {Glyph("cloud_sync_rounded",color=scheme.primary);Spacer(Modifier.width(12.dp));Column {Text("备份内容",fontSize=16.sp,fontWeight=FontWeight.Bold,color=scheme.primary);Spacer(Modifier.height(4.dp));Text("备份应用设置和历史，不包含图片和视频缓存。",fontSize=14.sp,lineHeight=19.6.sp,color=scheme.onSurfaceVariant)}}
        backupCard {Choice("全量安全备份",!full,{if(!busy)full=false},"不含会话及 WebDAV 密码",titleStyle=flutterTileTitle().copy(fontSize=16.sp,lineHeight=21.6.sp),subtitleStyle=flutterTileSubtitle().copy(fontSize=14.sp,lineHeight=19.6.sp),verticalPadding=2.dp);Choice("全量备份",full,{if(!busy)full=true},"含会话及 WebDAV 密码\n含明文凭据，请妥善保管",titleStyle=flutterTileTitle().copy(fontSize=16.sp,lineHeight=21.6.sp),subtitleStyle=flutterTileSubtitle().copy(fontSize=14.sp,lineHeight=19.6.sp),verticalPadding=2.dp)}
        backupCard {Column(Modifier.padding(16.dp)) {
            Text("WebDAV 服务器配置",fontSize=16.sp,fontWeight=FontWeight.SemiBold);Spacer(Modifier.height(16.dp))
            FlutterDenseField(url,{url=it},"服务器 URL","link_rounded",!busy,placeholder="例如: https://dav.jianguoyun.com/dav/",error=fieldErrors["url"]);Spacer(Modifier.height(12.dp))
            FlutterDenseField(user,{user=it},"账号 / 邮箱","person_outline_rounded",!busy,error=fieldErrors["user"]);Spacer(Modifier.height(12.dp))
            FlutterDenseField(password,{password=it},"应用密码 / Token","lock_outline_rounded",!busy,password=true,error=fieldErrors["password"]);Spacer(Modifier.height(12.dp))
            FlutterDenseField(directory,{directory=it},"备份文件夹名称","folder_outlined",!busy,placeholder="默认: ReviewX");Spacer(Modifier.height(16.dp))
            FlutterOutlinedButton(enabled=!busy,onClick={run("test")},modifier=Modifier.fillMaxWidth()){if(busy&&operation=="test")FlutterProgress(Modifier.size(16.dp),strokeWidth=2.dp)else Glyph("wifi_tethering_rounded",size=18);Spacer(Modifier.width(8.dp));Text(if(busy&&operation=="test")"正在测试连接..."else "测试服务器连接")}
        }}
        backupCard {Column(Modifier.padding(16.dp)) {Text("云端备份与还原操作",fontSize=16.sp,fontWeight=FontWeight.SemiBold);Spacer(Modifier.height(16.dp));Row(horizontalArrangement=Arrangement.spacedBy(12.dp)) {
            Button(enabled=!busy,onClick={run("upload")},modifier=Modifier.weight(1f),contentPadding=PaddingValues(vertical=12.dp)){if(busy&&operation=="upload")FlutterProgress(Modifier.size(16.dp),strokeWidth=2.dp,color=scheme.onPrimary)else Glyph("cloud_upload_rounded",size=18);Spacer(Modifier.width(8.dp));Text(if(busy&&operation=="upload")"正在上传..."else "立即备份到云端")}
            FilledTonalButton(enabled=!busy,onClick={if(validate())confirm=true},modifier=Modifier.weight(1f),contentPadding=PaddingValues(vertical=12.dp)){if(busy&&operation=="restore")FlutterProgress(Modifier.size(16.dp),strokeWidth=2.dp)else Glyph("cloud_download_rounded",size=18);Spacer(Modifier.width(8.dp));Text(if(busy&&operation=="restore")"正在拉取..."else "从云端恢复备份")}
        }}}
    }
    if(confirm)FlutterAlertDialog(onDismissRequest={confirm=false},title={Text("从 WebDAV 恢复备份？")},text={Text("恢复会覆盖备份中的设置和历史。全量备份还会替换 X 会话及 WebDAV 密码。恢复后请重启应用。")},confirmButton={FlutterTextButton(onClick={confirm=false;run("restore")}){Text("确定恢复")}},dismissButton={FlutterTextButton(onClick={confirm=false}){Text("取消")}})
}
@OptIn(ExperimentalMaterial3Api::class)
@Composable fun AccountSettings(model:ReaderViewModel,state:ReaderState) {
    var logout by remember{mutableStateOf(false)};var cookie by remember{mutableStateOf<String?>(null)};val scope=rememberCoroutineScope();val context=LocalContext.current
    LaunchedEffect(state.accountId){cookie=null}
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
        Surface(shape=RoundedCornerShape(24.dp),color=MaterialTheme.colorScheme.surfaceContainerLow){Row(Modifier.fillMaxWidth().heightIn(min=if(state.accountId==null)62.dp else 78.dp).padding(horizontal=16.dp,vertical=11.dp),verticalAlignment=Alignment.CenterVertically){if(state.user?.avatar.isNullOrEmpty())Box(Modifier.size(40.dp).background(MaterialTheme.colorScheme.surfaceContainerHighest,CircleShape),contentAlignment=Alignment.Center){Glyph("person_outline",color=MaterialTheme.colorScheme.onSurfaceVariant)}else Avatar(state.user,40);Spacer(Modifier.width(16.dp));Column{Text(state.user?.name?:"X 账号",style=flutterTileTitle());state.accountId?.let{Spacer(Modifier.height(2.dp));Text("UID：$it",style=flutterTileSubtitle())}}}}
        Spacer(Modifier.height(24.dp));Surface(shape=RoundedCornerShape(24.dp),color=MaterialTheme.colorScheme.surfaceContainerLow){Column {
            SettingRow("导出 Cookie",icon="copy_all_rounded",onClick={scope.launch{try{cookie=model.cookie()}catch(e:Exception){model.message(model.safeError(e))}}})
            SettingRow("验证登录状态",if(state.authenticating)"正在验证账号…"else null,"verified_user_outlined",onClick=if(state.authenticating)null else ({model.refreshIdentity(true)}))
            CompositionLocalProvider(LocalContentColor provides MaterialTheme.colorScheme.error){SettingRow("退出登录",icon="logout_rounded",onClick=if(state.authenticating)null else ({logout=true}),trailing={},titleStyle=flutterTileTitle().copy(color=MaterialTheme.colorScheme.error),iconColor=MaterialTheme.colorScheme.error)}
        }}
    }
    if(logout)FlutterAlertDialog(onDismissRequest={logout=false},title={Text("退出 X 账号？")},text={Text("这会清除本机登录信息。")},confirmButton={Button(onClick={logout=false;cookie=null;model.logout()}){Text("退出")}},dismissButton={FlutterTextButton(onClick={logout=false}){Text("取消")}})
    cookie?.let {value->FlutterBottomSheet(onDismissRequest={cookie=null}){Column(Modifier.fillMaxWidth().heightIn(max=LocalConfiguration.current.screenHeightDp.dp*.75f-48.dp).verticalScroll(rememberScrollState()).navigationBarsPadding().padding(start=16.dp,end=16.dp,bottom=16.dp)){
        Row(verticalAlignment=Alignment.CenterVertically){Text("导出 Cookie",Modifier.weight(1f).flutterLineHeight(MaterialTheme.typography.titleLarge.lineHeight),style=MaterialTheme.typography.titleLarge);IconButton(onClick={cookie=null}){Glyph("close","关闭")}}
        Text(state.user?.let{"${it.name} · @${it.handle}"}?:"当前 X 账号");Spacer(Modifier.height(12.dp));AppSectionCard {SelectionContainer{Text(value,Modifier.padding(12.dp),fontFamily=androidx.compose.ui.text.font.FontFamily.Monospace,fontSize=13.sp)}};Spacer(Modifier.height(12.dp));Button(onClick={NativeServices.copy(context,value);cookie=null;model.message("已复制 Cookie 到剪贴板")},modifier=Modifier.fillMaxWidth()){Glyph("copy_all_rounded",size=18);Spacer(Modifier.width(8.dp));Text("复制全部")}
    }}}

}
@Composable fun DisplaySettings(model:ReaderViewModel,state:ReaderState) {
    val context=LocalContext.current;val display=remember{(context.getSystemService(Context.WINDOW_SERVICE) as WindowManager).defaultDisplay}
    Column(Modifier.verticalScroll(rememberScrollState())){
        val selected=state.settings.optInt("refresh_rate")
        @Composable fun modeRow(id:Int,title:String){FlutterListItem(headlineContent={Text(title)},leadingContent={Glyph(if(selected==id)"radio_button_checked"else "radio_button_off")},modifier=Modifier.clickable{model.setSetting("refresh_rate",id)})}
        modeRow(0,"跟随系统");display.supportedModes.forEach{mode->modeRow(mode.modeId,"${mode.physicalWidth} × ${mode.physicalHeight} · ${mode.refreshRate.roundToInt()} Hz")}
    }
}
@Composable fun DiagnosticsSettings(model:ReaderViewModel) {
    val context=LocalContext.current;val scope=rememberCoroutineScope();var sharing by remember{mutableStateOf(false)}
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(top=LocalHeaderInset.current).padding(start=16.dp,top=16.dp,end=16.dp,bottom=32.dp).navigationBarsPadding(),verticalArrangement=Arrangement.spacedBy(16.dp)) {
        AppSectionCard {Column(Modifier.padding(start=20.dp,top=24.dp,end=20.dp,bottom=20.dp),horizontalAlignment=Alignment.CenterHorizontally){Glyph("bug_report_outlined",size=42,color=MaterialTheme.colorScheme.primary);Spacer(Modifier.height(12.dp));Text("导出诊断日志",Modifier.flutterLineHeight(MaterialTheme.typography.titleLarge.lineHeight),style=MaterialTheme.typography.titleLarge);Spacer(Modifier.height(8.dp));Text("日志保存在本机，最多保留最近 300 条记录。点击下方按钮后，系统会打开分享菜单，由你选择是否发送。",textAlign=TextAlign.Center,color=MaterialTheme.colorScheme.onSurfaceVariant,lineHeight=20.3.sp);Spacer(Modifier.height(20.dp));Button(enabled=!sharing,onClick={sharing=true;scope.launch{try{val file=withContext(Dispatchers.IO){DiagnosticLog.export(context)};NativeServices.share(context,file,"分享 ReviewX 诊断日志")}catch(e:CancellationException){throw e}catch(_:Exception){model.message("日志导出失败，请稍后重试")}finally{sharing=false}}},modifier=Modifier.fillMaxWidth(),contentPadding=PaddingValues(start=16.dp,end=24.dp)){if(sharing)FlutterProgress(Modifier.size(18.dp),strokeWidth=2.dp)else Glyph("ios_share_rounded",size=18);Spacer(Modifier.width(8.dp));Text(if(sharing)"正在准备日志…"else "生成并分享日志")}}
        }
        AppSectionCard {Row(Modifier.padding(16.dp)){Glyph("shield_outlined",size=22,color=MaterialTheme.colorScheme.primary);Spacer(Modifier.width(12.dp));Text("日志包含应用版本、系统版本、崩溃类型与精简调用位置，以及接口操作、状态码和耗时。不会记录 Cookie、账号、帖子内容或接口正文；异常原文也不会导出。",Modifier.weight(1f),color=MaterialTheme.colorScheme.onSurfaceVariant,lineHeight=20.3.sp)}}
    }
}
@Composable fun HistoryScreen(model:ReaderViewModel,state:ReaderState) {
    val items=state.accountId?.let(model.settings::history).orEmpty()
    if(items.isEmpty())Box(Modifier.fillMaxSize(),contentAlignment=Alignment.Center){Text("暂无本机浏览历史")}
    else LazyColumn(contentPadding=PaddingValues(top=LocalHeaderInset.current)) {items(items,key={it.str("id")}){item->
        Column(Modifier.fillMaxWidth().heightIn(min=78.dp).clickable {if(item.str("id").matches(Regex("\\d{1,30}")))model.handleLink("https://x.com/i/status/${item.str("id")}")else model.message("这条历史记录没有有效的帖子编号")}.padding(horizontal=16.dp,vertical=11.dp),verticalArrangement=Arrangement.Center) {
            Text(item.str("title"),maxLines=2,overflow=TextOverflow.Ellipsis,style=flutterTileTitle())
            Spacer(Modifier.height(2.dp));Text((item.str("author")+" · "+item.str("time")).substringBefore('.'),style=flutterTileSubtitle())
        }
    }}
}
@Composable fun AboutDialog(close:()->Unit) {
    val actions=LocalActions.current
    FlutterAlertDialog(onDismissRequest=close,shape=RoundedCornerShape(20.dp),contentPadding=PaddingValues(start=20.dp,top=24.dp,end=20.dp,bottom=16.dp),centerActions=true,text={Column(Modifier.verticalScroll(rememberScrollState()),horizontalAlignment=Alignment.CenterHorizontally) {
        Image(painterResource(R.mipmap.ic_launcher),"ReviewX",Modifier.size(72.dp).clip(RoundedCornerShape(16.dp)));Spacer(Modifier.height(14.dp));Row(verticalAlignment=Alignment.CenterVertically){Text("ReviewX",fontSize=21.sp,fontWeight=FontWeight.Bold);Spacer(Modifier.width(8.dp));Text("v${BuildConfig.VERSION_NAME}",Modifier.clip(RoundedCornerShape(8.dp)).background(MaterialTheme.colorScheme.primaryContainer).padding(horizontal=8.dp,vertical=3.dp),fontSize=12.sp,fontWeight=FontWeight.Bold,color=MaterialTheme.colorScheme.onPrimaryContainer)}
        Spacer(Modifier.height(6.dp));Text("面向 X/Twitter 的 Material 3 客户端",fontSize=13.sp);Spacer(Modifier.height(16.dp));FlutterDivider(height=1.dp);Spacer(Modifier.height(14.dp))
        listOf("dynamic_feed_outlined" to "浏览推荐与关注时间线、探索趋势、帖子详情和用户主页","search_rounded" to "探索趋势并搜索帖子、用户、图片和视频，也可查看通知","photo_library_outlined" to "查看媒体、管理书签和喜欢，并发布文字帖子、回复和引用").forEach{(icon,text)->Row(Modifier.padding(bottom=8.dp)){Glyph(icon,size=16,color=MaterialTheme.colorScheme.primary);Spacer(Modifier.width(8.dp));Text(text,Modifier.weight(1f),fontSize=12.5.sp,lineHeight=16.875.sp)}}
        Spacer(Modifier.height(6.dp));FlutterDivider(height=1.dp);Spacer(Modifier.height(12.dp))
        val colors=MaterialTheme.colorScheme
        Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(colors.surfaceContainerHighest.copy(alpha=.5f)).border(1.dp,colors.outlineVariant.copy(alpha=.4f),RoundedCornerShape(12.dp)).clickable{actions.link("https://github.com/Chengeeker/ReviewX")}.padding(horizontal=12.dp,vertical=8.dp),verticalAlignment=Alignment.CenterVertically){
            Text("\uf5dd",Modifier.size(20.dp).clearAndSetSemantics{},style=TextStyle(fontFamily=androidx.compose.ui.text.font.FontFamily(androidx.compose.ui.text.font.Font(R.font.cupertino_icons)),fontSize=with(LocalDensity.current){20.dp.toSp()},color=colors.primary));Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f)){Text("GitHub 开源地址",fontSize=13.sp,fontWeight=FontWeight.Bold);Text("github.com/Chengeeker/ReviewX",fontSize=11.sp,color=colors.onSurfaceVariant)};Glyph("open_in_new_rounded",size=16,color=colors.primary)
        }

    }},confirmButton={Button(onClick=close,shape=RoundedCornerShape(12.dp),contentPadding=PaddingValues(horizontal=24.dp,vertical=10.dp)){Text("我知道了")}})
}
@Composable fun LicensesScreen() {val context=LocalContext.current;val names=remember{context.assets.list("licenses").orEmpty().toList()};LazyColumn{items(names){name->var expanded by remember{mutableStateOf(false)};SettingRow(name,onClick={expanded=!expanded});if(expanded)SelectionContainer{Text(remember(name){context.assets.open("licenses/$name").bufferedReader().use{it.readText()}},Modifier.padding(16.dp),fontSize=12.sp)}}}}


internal fun webDavFormErrors(url:String,user:String,password:String):Map<String,String> = buildMap {
    val raw=url.trim();val uri=runCatching{java.net.URI(raw)}.getOrNull()
    if(raw.isEmpty())put("url","请输入 WebDAV 服务器地址")
    else if(uri==null||uri.scheme!="https"||uri.host.isNullOrBlank()||uri.userInfo!=null||uri.rawQuery!=null||uri.rawFragment!=null)put("url","请输入无查询参数的 HTTPS 地址")
    if(user.isBlank())put("user","请输入账号")
    if(password.isBlank())put("password","请输入密码或授权 Token")
}
