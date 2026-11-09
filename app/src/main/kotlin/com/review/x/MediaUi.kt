package com.review.x

import android.Manifest
import android.app.Activity
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.os.Build
import android.os.SystemClock
import android.view.HapticFeedbackConstants
import android.view.WindowManager
import androidx.activity.compose.*
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.*
import androidx.compose.foundation.gestures.*
import androidx.compose.foundation.interaction.DragInteraction
import androidx.compose.foundation.interaction.collectIsDraggedAsState
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.*
import androidx.compose.foundation.shape.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.*
import androidx.compose.ui.draw.*
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.geometry.isSpecified
import androidx.compose.ui.graphics.*
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.*
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.positionOnScreen
import androidx.compose.ui.platform.*
import androidx.compose.ui.unit.*
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.*
import androidx.core.view.*
import androidx.lifecycle.*
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.media3.common.*
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.PlayerView
import kotlinx.coroutines.*
import kotlin.math.abs
import kotlin.math.min
import kotlin.math.roundToInt

internal class GalleryPageFeedback {
    private var lastTick = -40L

    fun shouldTick(previous: Int, next: Int, now: Long): Boolean {
        if (previous == next || now - lastTick < 40) return false
        lastTick = now
        return true
    }
}

private suspend fun AwaitPointerEventScope.awaitGalleryRetap(
    down: PointerInputChange,
    target: Rect,
): Boolean = withTimeoutOrNull(viewConfiguration.longPressTimeoutMillis) {
    var pointer: PointerInputChange
    do {
        val event = awaitPointerEvent(PointerEventPass.Initial)
        pointer = event.changes.firstOrNull { it.id == down.id } ?: return@withTimeoutOrNull false
        if (pointer.isConsumed ||
            event.changes.any { it.id != down.id && it.pressed } ||
            (pointer.position - down.position).getDistance() > viewConfiguration.touchSlop
        ) return@withTimeoutOrNull false
        pointer.consume()
    } while (pointer.pressed)
    target.contains(pointer.position)
} == true

@OptIn(ExperimentalFoundationApi::class)
@Composable fun MediaGallery(request:GalleryRequest,model:ReaderViewModel,onClose:()->Unit) {
    val picturesOnly = remember(request) { request.media.none { it.video } }
    val pager=rememberPagerState(initialPage=request.index,pageCount={request.media.size});val scope=rememberCoroutineScope();val context=LocalContext.current
    var videoControlsHeight by remember {mutableIntStateOf(0)}
    var videoFullscreen by remember { mutableStateOf(false) }
    var chrome by rememberSaveable {mutableStateOf(true)};var zoomed by remember {mutableStateOf(false)};var saving by remember {mutableStateOf(false)};var videoMessage by remember {mutableStateOf<Pair<Long,String>?>(null)};var info by remember {mutableStateOf(false)}
    val flight=remember {Animatable(if(request.media[request.index].video)1f else 0f)};var closing by remember {mutableStateOf(false)};var returning by remember {mutableStateOf(false)};var closeJob by remember {mutableStateOf<Job?>(null)}
    val pagePlanes = remember(request) { mutableMapOf<Int, () -> GalleryPlane?>() }
    var closingIndex by remember { mutableIntStateOf(request.index) }
    var closingPlane by remember { mutableStateOf<GalleryPlane?>(null) }
    var closingAnchor by remember { mutableStateOf<GalleryAnchor?>(null) }
    var overlayCoordinates by remember { mutableStateOf<LayoutCoordinates?>(null) }
    var pendingRetap by remember { mutableStateOf<CompletableDeferred<Unit>?>(null) }
    val haptics by rememberUpdatedState(LocalHapticFeedback.current)
    val liquidGlass = LocalSettings.current.optBoolean("use_liquid_glass_effect")
    val hapticView = LocalView.current
    val pageFeedback = remember { GalleryPageFeedback() }
    fun tickPage(previous: Int, next: Int, fromStripDrag: Boolean) {
        if (haptics !== SilentHapticFeedback && pageFeedback.shouldTick(previous, next, SystemClock.uptimeMillis())) {
            if (fromStripDrag) hapticView.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
            else haptics.performHapticFeedback(HapticFeedbackType.VirtualKey)
        }
    }
    val backdrop = rememberBackdrop()
    fun anchor() = if (returning) closingAnchor else request.openingAnchor
    fun image() = if (!returning) request.sourceImage
    else if (request.media[closingIndex].video) null
    else closingPlane?.bitmap ?: request.sourceImage?.takeIf { closingIndex == request.index }
    fun sourceInOverlay(): GalleryAnchor? {
        val origin = overlayCoordinates?.takeIf { it.isAttached }?.positionOnScreen() ?: return null
        return anchor()?.takeIf { origin.isSpecified }?.inOverlay(origin)
    }
    fun hideSource() {
        request.flight.active = request.flight.sourceScope != null && anchor() != null && image() != null
    }
    fun finishOpening() {
        returning = false
        closingPlane = null
        closingAnchor = null
        request.flight.index = pager.currentPage
        request.flight.active = false
    }
    LaunchedEffect(Unit) {
        if (flight.value < 1f) {
            hideSource()
            flight.animateTo(1f, tween(330, easing = LinearEasing))
        }
        finishOpening()
    }
    LaunchedEffect(pager) {
        pager.interactionSource.interactions.collect { interaction ->
            if (interaction is DragInteraction.Start && !closing && flight.value < 1f) {
                flight.snapTo(1f)
                if (!closing) finishOpening()
            }
        }
    }
    fun close() {
        if (closing) return
        closing = true
        if (!returning && flight.value >= .999f) {
            returning = true
            closingIndex = pager.currentPage
            closingAnchor = request.sourceAnchor?.invoke(closingIndex)
            val overlayOrigin = overlayCoordinates?.takeIf { it.isAttached }?.positionInRoot() ?: Offset.Zero
            closingPlane = pagePlanes[closingIndex]?.invoke()?.let {
                it.copy(rect = it.rect.translate(-overlayOrigin), viewport = it.viewport.translate(-overlayOrigin))
            }
            pager.requestScrollToPage(closingIndex)
        }
        request.flight.index = if (returning) closingIndex else request.index
        hideSource()
        closeJob = scope.launch {
            val duration = (200 * flight.value).roundToInt().coerceAtLeast(1)
            flight.animateTo(0f, tween(duration, easing = LinearEasing))
            val needsHandoff = request.flight.active
            request.flight.active = false
            // Keep the endpoint in the dialog while the source thumbnail is revealed.
            if (needsHandoff) withFrameNanos {}
            // A pointer stream that started in this window cannot finish on the thumbnail below it.
            pendingRetap?.await()
            onClose()
        }
    }
    fun reopen() {
        if (!closing || closeJob?.isActive != true) return
        closeJob?.cancel()
        closing = false
        hideSource()
        haptics.performHapticFeedback(HapticFeedbackType.VirtualKey)
        scope.launch {
            val duration = (330 * (1f - flight.value)).roundToInt().coerceAtLeast(1)
            flight.animateTo(1f, tween(duration, easing = LinearEasing))
            finishOpening()
        }
    }
    var selectedMedia by remember {mutableStateOf<Media?>(null)}
    fun videoNotice(text:String){videoMessage=System.nanoTime() to text}
    LaunchedEffect(videoMessage){if(videoMessage!=null){delay(3000);videoMessage=null}}
    LaunchedEffect(pager.currentPage){if (!returning) request.flight.index=pager.currentPage;videoMessage=null}
    fun save(item:Media){if(saving)return;saving=true;scope.launch{try{NativeServices.save(context,item,NativeServices.folder(model.settings,item,request.author,model.state.value.user?.handle.orEmpty()));if(item.video)videoNotice("已保存到系统相册")else model.message("已保存到系统相册")}catch(e:CancellationException){throw e}catch(e:Exception){if(item.video)videoNotice("视频保存失败，请检查网络和相册权限后重试")else model.message("保存到相册失败，请检查网络和相册权限后重试")}finally{saving=false}}}
    val permission=rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()){granted->if(granted)selectedMedia?.let(::save)else if(selectedMedia?.video==true)videoNotice("未授予相册保存权限")else model.message("未授予相册保存权限")}
    fun download(item:Media){selectedMedia=item;if(Build.VERSION.SDK_INT<29 && context.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE)!=PackageManager.PERMISSION_GRANTED)permission.launch(Manifest.permission.WRITE_EXTERNAL_STORAGE)else save(item)}
    Dialog(onDismissRequest=::close,properties=DialogProperties(usePlatformDefaultWidth=false,decorFitsSystemWindows=false)) {
        val window=(LocalView.current.parent as? DialogWindowProvider)?.window
        DisposableEffect(window) { window?.let {it.setWindowAnimations(0);it.setDimAmount(0f);it.setBackgroundDrawable(android.graphics.drawable.ColorDrawable(android.graphics.Color.TRANSPARENT));it.applyReviewStatusBar(dark=true);WindowCompat.getInsetsController(it,it.decorView).isAppearanceLightNavigationBars=false};onDispose {window?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)} }
        LaunchedEffect(chrome){window?.let{val control=WindowCompat.getInsetsController(it,it.decorView);control.systemBarsBehavior=WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE;if(chrome)control.show(WindowInsetsCompat.Type.systemBars())else control.hide(WindowInsetsCompat.Type.systemBars())}}
        BackHandler(onBack=::close)
        CompositionLocalProvider(LocalBackdrop provides backdrop, LocalHapticFeedback provides haptics) {
        BoxWithConstraints(Modifier.fillMaxSize().pointerInput(request) {
            awaitEachGesture {
                val down = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
                if (!closing) return@awaitEachGesture
                down.consume()
                val target = sourceInOverlay()?.visibleBounds ?: return@awaitEachGesture
                if (!target.contains(down.position)) return@awaitEachGesture
                val pending = CompletableDeferred<Unit>()
                pendingRetap = pending
                try {
                    if (awaitGalleryRetap(down, target)) reopen()
                } finally {
                    pendingRetap = null
                    pending.complete(Unit)
                }
            }
        }.onGloballyPositioned { overlayCoordinates = it }.background(Color.Black.copy(alpha = flight.value))) {
            var preparedPage by remember(request) { mutableIntStateOf(request.index) }
            LaunchedEffect(pager.settledPage, constraints.maxWidth, constraints.maxHeight) {
                val page = pager.settledPage
                val direction = if (page < preparedPage) -1 else 1
                preparedPage = page
                val next = request.media.getOrNull(page + direction) ?: return@LaunchedEffect
                if (next.video || !safeMediaUrl(next.url)) return@LaunchedEffect
                val imageRequest = coil.request.ImageRequest.Builder(context)
                    .data(next.viewerImage(constraints.maxWidth.toFloat(), constraints.maxHeight.toFloat()))
                    .size(constraints.maxWidth, constraints.maxHeight)
                    .scale(coil.size.Scale.FIT)
                    .setHeader("User-Agent", ReaderRepository.USER_AGENT)
                    .setHeader("Referer", "https://x.com/")
                    .build()
                val loading = coil.Coil.imageLoader(context).enqueue(imageRequest)
                try { awaitCancellation() } finally { loading.dispose() }
            }
            val source = sourceInOverlay()
            val bitmap = image()
            val drawFlight = source != null && bitmap != null && (flight.value < 1f || closing)
            val thumbs=rememberPagerState(initialPage=request.index,pageCount={request.media.size});val mainDrag by pager.interactionSource.collectIsDraggedAsState();val thumbDrag by thumbs.interactionSource.collectIsDraggedAsState();var driver by remember {mutableStateOf("main")};var settleJob by remember {mutableStateOf<Job?>(null)}
            val stripBottom=if(request.media[pager.currentPage].video&&videoControlsHeight>0)with(LocalDensity.current){videoControlsHeight.toDp()}+8.dp else 32.dp
            var fixedStripBottom by remember {mutableStateOf<Dp?>(null)}
            val freeFling=ScrollableDefaults.flingBehavior()
            val thumbnailFling=remember(freeFling){object:TargetedFlingBehavior {override suspend fun ScrollScope.performFling(initialVelocity:Float,onRemainingDistanceUpdated:(Float)->Unit):Float=with(freeFling){performFling(initialVelocity)}}}
            LaunchedEffect(mainDrag){if(mainDrag){driver="main";fixedStripBottom=null;settleJob?.cancel()}};LaunchedEffect(thumbDrag){if(thumbDrag){driver="thumb";fixedStripBottom=stripBottom;settleJob?.cancel()}}
            LaunchedEffect(pager,thumbs){snapshotFlow{Triple(pager.currentPage,pager.currentPageOffsetFraction,pager.isScrollInProgress)}.collect{(page,offset,_)->if(!closing && driver=="main" && !thumbDrag)thumbs.scrollToPage(page,offset)}}
            LaunchedEffect(thumbs,pager){snapshotFlow{Triple(thumbs.currentPage,thumbs.currentPageOffsetFraction,thumbs.isScrollInProgress)}.collect{(page,offset,moving)->if(!closing && !returning && driver=="thumb" && !mainDrag){
                val previous = pager.currentPage
                pager.scrollToPage(page,offset)
                if (driver == "thumb" && !closing) {
                    tickPage(previous, pager.currentPage, fromStripDrag = true)
                }
                if(!moving){driver="settling";settleJob=scope.launch {try {coroutineScope {launch{pager.animateScrollToPage(page,animationSpec=tween(120,easing=CubicBezierEasing(.215f,.61f,.355f,1f)))};launch{thumbs.animateScrollToPage(page,animationSpec=tween(120,easing=CubicBezierEasing(.215f,.61f,.355f,1f)))}}}finally{if(driver=="settling"){driver="main";fixedStripBottom=null}}}}}}}
            HorizontalPager(pager,Modifier.fillMaxSize().graphicsLayer {alpha=if(drawFlight)0f else flight.value}.recordBackdrop(backdrop),userScrollEnabled=!zoomed&&!closing,beyondViewportPageCount=0) {index->val item=request.media[index]
                if(item.video) {
                    if(index==pager.currentPage) VideoPlayer(item,request,saving=saving,message=videoMessage?.second,onMessage=::videoNotice,active=!closing&&!pager.isScrollInProgress&&!thumbs.isScrollInProgress,showChrome=chrome,onChrome={chrome=it},onBack=::close,onControlsHeight={videoControlsHeight=it},onFullscreen={videoFullscreen=it},onSave={download(it)},onPrevious=if(index>0)({scope.launch{pager.animateScrollToPage(index-1)}})else null,onNext=if(index+1<request.media.size)({scope.launch{pager.animateScrollToPage(index+1)}})else null)
                    else NetworkImage(item.url,item.description,Modifier.fillMaxSize(),ContentScale.Fit)
                } else ZoomImage(item,active=index==pager.currentPage,onZoom={if(index==pager.currentPage)zoomed=it},onTap={position,width->
                    if (!closing && !pager.isScrollInProgress && index == pager.currentPage) {
                        if(position.x>=width/3&&position.x<width*2/3)chrome=!chrome else close()
                    }
                },pageIndex=index,pagePlanes=pagePlanes,preview=request.previewImage?.invoke(index) ?: request.sourceImage?.takeIf { index == request.index })
            }
            if (drawFlight) GalleryFlight(
                source, bitmap, flight.value, Size(constraints.maxWidth.toFloat(), constraints.maxHeight.toFloat()),
                request.sourceRadius, request.sourceCovers, returning, closingPlane,
            )
            if (!closing && flight.value == 1f) {
            AnimatedVisibility(visible=chrome&&!request.media[pager.currentPage].video,modifier=Modifier.align(Alignment.TopCenter),enter=if(liquidGlass)EnterTransition.None else slideInVertically(tween(180,easing=CubicBezierEasing(.215f,.61f,.355f,1f))){-it}+fadeIn(tween(160)),exit=if(liquidGlass)ExitTransition.None else slideOutVertically(tween(180,easing=CubicBezierEasing(.215f,.61f,.355f,1f))){-it}+fadeOut(tween(160))) {Row(Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal=16.dp,vertical=8.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.SpaceBetween) {
                GalleryButton("arrow_back_rounded","返回",::close)
                Text("${pager.currentPage+1} / ${request.media.size}",Modifier.clip(RoundedCornerShape(16.dp)).background(Color.Black.copy(alpha=.45f)).padding(horizontal=14.dp,vertical=6.dp),color=Color.White,fontSize=13.sp,fontWeight=androidx.compose.ui.text.font.FontWeight.Bold)
                Row{if(request.media[pager.currentPage].description.isNotBlank())GalleryButton("info_outline","图片说明",{info=true});if(saving)FlutterProgress(Modifier.padding(12.dp).size(20.dp),color=Color.White,strokeWidth=2.dp)else GalleryButton("download_rounded","保存到相册",{download(request.media[pager.currentPage])})}
            }
            }
            }
            val stripInset = if (picturesOnly) 0.dp else 12.dp
            if(chrome && !closing && !videoFullscreen && flight.value==1f && request.media.size>1)HorizontalPager(thumbs,Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(start=stripInset,end=stripInset,bottom=fixedStripBottom?:stripBottom).height(64.dp),pageSize=PageSize.Fixed((maxWidth-stripInset*2)*.16f),contentPadding=PaddingValues(horizontal=((maxWidth-stripInset*2)*.84f/2).coerceAtLeast(0.dp)),beyondViewportPageCount=2,flingBehavior=thumbnailFling) {index->Box(Modifier.fillMaxSize().padding(horizontal=3.dp,vertical=2.dp).border(2.dp,if(index==pager.currentPage)Color.White else Color.Transparent,RoundedCornerShape(8.dp)).padding(2.dp).clip(RoundedCornerShape(6.dp)).clickable {
                val previous = pager.currentPage
                if (index != previous && !closing) {
                    tickPage(previous, index, fromStripDrag = false)
                    driver = "main"
                    fixedStripBottom = null
                    settleJob?.cancel()
                    scope.launch { pager.animateScrollToPage(index, animationSpec = tween(200)) }
                }
            }){NetworkImage(request.media[index].url,"第 ${index+1} 张图片",Modifier.fillMaxSize());if(index!=pager.currentPage)Box(Modifier.fillMaxSize().background(Color.White.copy(alpha=.5f)))}}
        }
        }
        if(info)FlutterAlertDialog(onDismissRequest={info=false},title={Text("图片说明")},text={androidx.compose.foundation.text.selection.SelectionContainer{Text(request.media[pager.currentPage].description)}},confirmButton={FlutterTextButton(onClick={info=false}){Text("关闭")}})
    }
}
@Composable fun GalleryButton(icon:String,title:String,onClick:()->Unit) {
    val glass=LocalSettings.current.optBoolean("use_liquid_glass_effect")
    if (!glass) {
        PlainGalleryControl(title, true, hapticClick(onClick)) { Glyph(icon, null, size=24, color=Color.White) }
        return
    }
    val interactions=remember {androidx.compose.foundation.interaction.MutableInteractionSource()};val pressed by interactions.collectIsPressedAsState()
    val stretch by animateFloatAsState(if(glass&&pressed)1.06f else 1f,spring(dampingRatio=.8f))
    var drag by remember {mutableStateOf(Offset.Zero)}
    val dragX by animateFloatAsState(drag.x,spring(dampingRatio=.8f,stiffness=500f));val dragY by animateFloatAsState(drag.y,spring(dampingRatio=.8f,stiffness=500f))
    Box(Modifier.size(48.dp).pointerInput(glass){if(glass)awaitEachGesture {val down=awaitFirstDown(requireUnconsumed=false,pass=PointerEventPass.Final);try {do {val event=awaitPointerEvent(PointerEventPass.Final);val point=event.changes.firstOrNull {it.id==down.id}?:break;drag=(point.position-down.position)*.8f}while(point.pressed)}finally{drag=Offset.Zero}}}.graphicsLayer {
        val x=dragX/density;val y=dragY/density
        val geometry=galleryButtonStretch(x,y)
        scaleX=stretch*geometry[0];scaleY=stretch*geometry[1];transformOrigin=TransformOrigin(geometry[2],geometry[3]);translationX=dragX*.15f;translationY=dragY*.15f
    },contentAlignment=Alignment.Center) {
        if(glass)GlassSurface(GlassStyle(Color(0x66000000),thickness=32f,refractiveIndex=1.24f,chromatic=.025f,radius=100f),Modifier.size(48.dp))

        IconButton(onClick=hapticClick(onClick),interactionSource=interactions,modifier=Modifier.fillMaxSize()){Glyph(icon,title,size=22,color=Color.White)}
    }
}
@Composable private fun ZoomImage(item:Media,active:Boolean,onZoom:(Boolean)->Unit,onTap:(Offset,Float)->Unit,pageIndex:Int,pagePlanes:MutableMap<Int,()->GalleryPlane?>,preview:ImageBitmap?) {
    val tap by rememberUpdatedState(onTap);val density=LocalDensity.current.density
    val haptics by rememberUpdatedState(LocalHapticFeedback.current)
    var tapMoved by remember(item.url) { mutableStateOf(false) }
    var centroid by remember {mutableStateOf(Offset.Zero)}
    var zoomJob by remember {mutableStateOf<Job?>(null)};var intrinsic by remember(item.url){mutableStateOf(androidx.compose.ui.unit.IntSize(item.width,item.height))}
    var scale by remember(item.url){mutableFloatStateOf(1f)};var offset by remember(item.url){mutableStateOf(Offset.Zero)};var viewport by remember{mutableStateOf(androidx.compose.ui.unit.IntSize.Zero)};var coordinates by remember{mutableStateOf<LayoutCoordinates?>(null)};var flightImage by remember(item.url){mutableStateOf<Pair<ImageBitmap,Boolean>?>(preview?.let { it to false })};val scope=rememberCoroutineScope()
    fun clamp(value:Offset,zoom:Float):Offset {val ratio=if(intrinsic.width>0&&intrinsic.height>0)intrinsic.width.toFloat()/intrinsic.height else viewport.width.toFloat()/viewport.height.coerceAtLeast(1);val imageWidth=min(viewport.width.toFloat(),viewport.height*ratio);val imageHeight=min(viewport.height.toFloat(),viewport.width/ratio);return Offset(value.x.coerceIn(-((imageWidth*zoom-viewport.width)/2).coerceAtLeast(0f),((imageWidth*zoom-viewport.width)/2).coerceAtLeast(0f)),value.y.coerceIn(-((imageHeight*zoom-viewport.height)/2).coerceAtLeast(0f),((imageHeight*zoom-viewport.height)/2).coerceAtLeast(0f)))}
    val transform=rememberTransformableState {zoom,pan,_->zoomJob?.cancel();val next=(scale*zoom).coerceIn(1f,8f);val focus=centroid-Offset(viewport.width/2f,viewport.height/2f);offset=clamp(focus+(offset-focus)*(next/scale)+pan,next);scale=next}
    LaunchedEffect(scale){onZoom(scale>1.01f)}
    LaunchedEffect(active){if(!active){zoomJob?.cancel();scale=1f;offset=Offset.Zero}}
    DisposableEffect(pagePlanes, pageIndex, item.url) {
        pagePlanes[pageIndex] = capture@{
            val (bitmap, _) = flightImage ?: return@capture null
            val layout = coordinates?.takeIf { it.isAttached } ?: return@capture null
            val bounds=Rect(layout.positionInRoot(),Size(layout.size.width.toFloat(),layout.size.height.toFloat()))
            val fitted=galleryImagePlane(bounds,Size(bitmap.width.toFloat(),bitmap.height.toFloat()),false)
            val center=bounds.center
            val plane=Rect(center.x+(fitted.left-center.x)*scale+offset.x,center.y+(fitted.top-center.y)*scale+offset.y,center.x+(fitted.right-center.x)*scale+offset.x,center.y+(fitted.bottom-center.y)*scale+offset.y)
            GalleryPlane(bitmap, plane, bounds)
        }
        onDispose { pagePlanes.remove(pageIndex) }
    }
    Box(Modifier.fillMaxSize().onGloballyPositioned{viewport=it.size;coordinates=it}.transformable(transform,canPan={scale>1f}).pointerInput(item.url,active){
        awaitEachGesture {
            val down=awaitFirstDown(requireUnconsumed=false,pass=PointerEventPass.Initial)
            tapMoved = false
            zoomJob?.cancel();centroid=down.position
            val tracker=VelocityTracker();tracker.addPosition(down.uptimeMillis,down.position)
            var multiple=false;var moved=false;var released=false
            do {
                val initial=awaitPointerEvent(PointerEventPass.Initial)
                val pointer = initial.changes.firstOrNull { it.id == down.id }
                if (pointer == null ||
                    (pointer.position - down.position).getDistance() > viewConfiguration.touchSlop ||
                    initial.changes.any { it.id != down.id && it.pressed }
                ) tapMoved = true
                centroid=initial.calculateCentroid(useCurrent=false).takeIf{it.isSpecified}?:centroid
                val event=awaitPointerEvent(PointerEventPass.Final)
                if(event.changes.count{it.pressed}>1)multiple=true
                val point=event.changes.firstOrNull{it.id==down.id}?:break
                tracker.addPosition(point.uptimeMillis,point.position)
                moved=moved||(point.isConsumed&&point.position!=point.previousPosition)
                released=!point.pressed
            }while(!released)
            if(active&&scale>1f&&moved&&!multiple&&released) {
                val velocity=tracker.calculateVelocity()
                val delta=galleryInertia(Offset(velocity.x,velocity.y),density)
                if(delta!=Offset.Zero){val initial=offset;zoomJob=scope.launch {
                    animate(0f,1.01f,initialVelocity=.4f,animationSpec=spring(dampingRatio=1f,stiffness=500f,visibilityThreshold=.01f)){progress,_->offset=clamp(initial+delta*progress.coerceIn(0f,1f),scale)}
                }}
            }
        }
    }.pointerInput(item.url){detectTapGestures(onTap={if (!tapMoved) tap(it,size.width.toFloat())},onDoubleTap={point->if (!tapMoved) {haptics.performHapticFeedback(HapticFeedbackType.VirtualKey);zoomJob?.cancel();val start=scale;val target=if(start<=1.05f){if(intrinsic.width>0&&intrinsic.height.toFloat()/intrinsic.width>2f)3.5f else 2.5f}else if(start<=3.6f)6f else 1f;val initial=offset;val end=if(target==1f)Offset.Zero else clamp((Offset(size.width/2f,size.height/2f)-point)*(target-1),target);zoomJob=scope.launch{animate(0f,1f,animationSpec=tween(260,easing=CubicBezierEasing(.215f,.61f,.355f,1f))){fraction,_->scale=start+(target-start)*fraction;offset=initial+(end-initial)*fraction}}}})}) {
        val imageModifier = Modifier.fillMaxSize().graphicsLayer { scaleX=scale;scaleY=scale;translationX=offset.x;translationY=offset.y }
        if (preview != null) Image(preview,item.description,imageModifier,contentScale=ContentScale.Fit)
        else NetworkImage(item.url,item.description,imageModifier,ContentScale.Fit,onImageReady={bitmap->if(flightImage?.second!=true)flightImage=bitmap to false},showProgress=true)
        NetworkImage(item.viewerImage(viewport.width.toFloat(),viewport.height.toFloat()),item.description,Modifier.fillMaxSize().graphicsLayer{scaleX=scale;scaleY=scale;translationX=offset.x;translationY=offset.y},ContentScale.Fit,transparentFallback=true,onDimensions={w,h->intrinsic=IntSize(w,h)},onImageReady={bitmap->flightImage=bitmap to true})
    }
}
private fun Modifier.onSizeChangedCompat(action:(androidx.compose.ui.unit.IntSize)->Unit)=this.then(Modifier.onSizeChanged(action))
fun videoHeight(url:String):Int {val match=Regex("/(\\d+)x(\\d+)/").find(url);return match?.let{min(it.groupValues[1].toInt(),it.groupValues[2].toInt())}?:0}
fun preferredVideo(media:Media,quality:String):VideoVariant? {
    val variants=media.variants.sortedByDescending {it.bitrate};if(quality=="high")return variants.firstOrNull();val cap=if(quality=="data_saver")480 else 720
    return variants.firstOrNull{videoHeight(it.url) in 1..cap} ?: if(quality=="data_saver")variants.lastOrNull()else variants.firstOrNull()
}
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
@OptIn(ExperimentalMaterial3Api::class)
@Composable fun VideoPlayer(media:Media,request:GalleryRequest,saving:Boolean,message:String?,onMessage:(String)->Unit,active:Boolean,showChrome:Boolean,onChrome:(Boolean)->Unit,onBack:()->Unit,onControlsHeight:(Int)->Unit,onSave:(Media)->Unit,onPrevious:(()->Unit)?,onNext:(()->Unit)?,onFullscreen:(Boolean)->Unit={}) {
    val chromeVisible by rememberUpdatedState(showChrome);val chromeAction by rememberUpdatedState(onChrome)
    val haptics by rememberUpdatedState(LocalHapticFeedback.current)
    val context=LocalContext.current;val activity=context as? Activity;val window=(LocalView.current.parent as? DialogWindowProvider)?.window ?: activity?.window
    val reading=LocalReading.current;val actions=LocalActions.current;val model=actions.model;val lifecycle=LocalLifecycleOwner.current.lifecycle
    val accountState by model.state.collectAsStateWithLifecycle()
    var selected by remember(media.url){mutableStateOf(preferredVideo(media,reading.str("videoQuality","balanced")))}
    var speed by rememberSaveable{mutableFloatStateOf(1f)};var gain by rememberSaveable{mutableFloatStateOf(1f)};var muted by rememberSaveable{mutableStateOf(reading.optBoolean("defaultMutedVideo"))}
    var position by remember{mutableLongStateOf(0L)};var duration by remember{mutableLongStateOf(0L)};var playing by remember{mutableStateOf(false)};var buffering by remember{mutableStateOf(true)};var failure by remember{mutableStateOf(false)}
    var delete by remember {mutableStateOf(false)};var buffered by remember {mutableLongStateOf(0L)}
    var landscape by rememberSaveable{mutableStateOf(false)};var menu by remember{mutableStateOf<String?>(null)};var hud by remember{mutableStateOf<String?>(null)};var seekDraft by remember{mutableStateOf<Float?>(null)}
    var gestureActive by remember {mutableStateOf(false)}
    var foreground by remember{mutableStateOf(lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED))};var autoPlay by remember{mutableStateOf(true)};var held by remember{mutableStateOf(false)}
    val scope=rememberCoroutineScope();val initialBrightness=remember(window){window?.attributes?.screenBrightness?:-1f};var brightness by remember{mutableFloatStateOf(if(initialBrightness<0).5f else initialBrightness)}
    val player=remember(media.url){ExoPlayer.Builder(context).setMediaSourceFactory(DefaultMediaSourceFactory(OkHttpDataSource.Factory(AppNetwork.http).setUserAgent(ReaderRepository.USER_AGENT).setDefaultRequestProperties(mapOf("Referer" to "https://x.com/")))).build().apply{setAudioAttributes(AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(),true);setHandleAudioBecomingNoisy(true)}}
    DisposableEffect(player,lifecycle){val listener=object:Player.Listener{override fun onIsPlayingChanged(value:Boolean){playing=value};override fun onPlaybackStateChanged(state:Int){buffering=state==Player.STATE_BUFFERING};override fun onPlayerError(error:PlaybackException){failure=true;buffering=false;DiagnosticLog.record("video.failure",error=error)}};player.addListener(listener)
        val observer=LifecycleEventObserver{_,event->foreground=event==Lifecycle.Event.ON_RESUME || lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED);if(!foreground){autoPlay=false;player.pause();window?.attributes=window?.attributes?.apply{screenBrightness=initialBrightness}}};lifecycle.addObserver(observer)
        onDispose{onFullscreen(false);lifecycle.removeObserver(observer);player.removeListener(listener);player.release();window?.attributes=window?.attributes?.apply{screenBrightness=initialBrightness};window?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);activity?.requestedOrientation=ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED}
    }
    LaunchedEffect(selected){val seek=player.currentPosition;val shouldPlay=player.isPlaying||autoPlay;selected?.let{player.setMediaItem(MediaItem.fromUri(it.url));player.prepare();player.seekTo(seek);failure=false;player.playWhenReady=shouldPlay&&active&&foreground}}
    LaunchedEffect(active,foreground){if(!active||!foreground){player.pause();window?.attributes=window?.attributes?.apply{screenBrightness=initialBrightness}}else if(autoPlay)player.play()}
    LaunchedEffect(speed,held){player.setPlaybackSpeed(if(held)2f else speed)};LaunchedEffect(muted,gain){player.volume=if(muted)0f else gain}
    LaunchedEffect(player){while(isActive){position=player.currentPosition.coerceAtLeast(0);duration=player.duration.coerceAtLeast(0);buffered=player.bufferedPosition.coerceAtLeast(0);delay(250)}}
    LaunchedEffect(playing){if(playing)window?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)else window?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)}
    LaunchedEffect(showChrome,playing,menu,held,gestureActive,active,foreground){if(showChrome&&playing&&menu==null&&!held&&!gestureActive&&active&&foreground){delay(4000);onChrome(false)}}

    LaunchedEffect(landscape) { onFullscreen(landscape) }
    BackHandler(landscape){landscape=false;activity?.requestedOrientation=ActivityInfo.SCREEN_ORIENTATION_PORTRAIT;onChrome(true)}
    Box(Modifier.fillMaxSize().background(Color.Black)) {
        if(duration==0L&&active&&media.url.isNotBlank())NetworkImage(media.url,media.description,Modifier.fillMaxSize(),ContentScale.Fit)
        AndroidView(factory={PlayerView(it).apply{this.player=player;useController=false;setShutterBackgroundColor(android.graphics.Color.TRANSPARENT);setShowBuffering(PlayerView.SHOW_BUFFERING_NEVER);keepScreenOn=false}},modifier=Modifier.fillMaxSize())
        var dragAxis by remember{mutableStateOf("")};var origin by remember{mutableStateOf(Offset.Zero)};var drag by remember{mutableStateOf(Offset.Zero)};var startPosition by remember{mutableLongStateOf(0)};var startBrightness by remember{mutableFloatStateOf(.5f)};var startGain by remember{mutableFloatStateOf(1f)}
        Box(Modifier.fillMaxSize().pointerInput(active,foreground){detectTapGestures(
            onTap={chromeAction(!chromeVisible)},
            onDoubleTap={point->if(active&&foreground&&player.duration>0){if(point.x in size.width*.35f..size.width*.65f){if(player.isPlaying){player.pause();autoPlay=false;chromeAction(true)}else{player.play();autoPlay=true}}else{val delta=if(point.x<size.width*.35f)-10000 else 10000;player.seekTo((player.currentPosition+delta).coerceIn(0,player.duration));hud=if(delta>0)"+10s"else "-10s"}}},
            onPress={tryAwaitRelease();held=false},onLongPress={point->if(active&&foreground&&player.isPlaying&&(point.x<size.width*.45f||point.x>size.width*.55f)){held=true;haptics.performHapticFeedback(androidx.compose.ui.hapticfeedback.HapticFeedbackType.LongPress)}})
        }.pointerInput(active,foreground){detectVerticalDragGestures(
            onDragStart={point->origin=point;drag=Offset.Zero;dragAxis="";gestureActive=true;startBrightness=brightness;startGain=gain},
            onDragEnd={gestureActive=false;dragAxis="";held=false},onDragCancel={gestureActive=false;dragAxis="";held=false;hud=null}) {change,delta->if(active&&foreground){
                drag+=Offset(0f,delta)
                if(dragAxis.isBlank()&&abs(drag.y)>14.dp.toPx())dragAxis=if(origin.x<size.width/2)"brightness"else "volume"
                if(dragAxis.isNotBlank())change.consume()
                if(dragAxis=="brightness"){brightness=(startBrightness-drag.y/(size.height*.65f)).coerceIn(.01f,1f);window?.attributes=window?.attributes?.apply{screenBrightness=brightness};hud="brightness"}
                if(dragAxis=="volume"){gain=(startGain-drag.y/(size.height*.65f)).coerceIn(0f,1f);muted=gain<=0;hud="volume"}
            }}
        })
        LaunchedEffect(hud,gestureActive){if(hud!=null&&!gestureActive){delay(600);hud=null}}
        if(buffering)FlutterProgress(Modifier.align(Alignment.Center),color=Color.White)
        if(failure)Column(Modifier.align(Alignment.Center),horizontalAlignment=Alignment.CenterHorizontally){Text("视频加载失败，请重试",color=Color.White);Button(onClick={failure=false;player.prepare();player.playWhenReady=active&&foreground}){Text("重试")}}
        hud?.let {value->
            Row(Modifier.align(Alignment.Center).shadow(12.dp,RoundedCornerShape(16.dp)).background(Color.Black.copy(alpha=.85f),RoundedCornerShape(16.dp)).border(.8.dp,Color.White.copy(alpha=.24f),RoundedCornerShape(16.dp)).padding(horizontal=20.dp,vertical=12.dp),verticalAlignment=Alignment.CenterVertically) {
                if(value=="brightness"||value=="volume") {
                    val level=if(value=="brightness")brightness else gain;val color=if(value=="brightness")Color(0xFFFFD740)else Color(0xFF18FFFF)
                    Glyph(if(value=="brightness")if(level>.5f)"brightness_7_rounded"else "brightness_4_rounded"else if(level==0f)"volume_off_rounded"else if(level>.5f)"volume_up_rounded"else "volume_down_rounded",size=26,color=color)
                    Spacer(Modifier.width(12.dp));LinearProgressIndicator(progress={level},modifier=Modifier.width(100.dp).height(6.dp).clip(RoundedCornerShape(4.dp)),color=color,trackColor=Color.White.copy(alpha=.24f),gapSize=0.dp,drawStopIndicator={});Spacer(Modifier.width(12.dp));Text("${(level*100).toInt()}%",color=Color.White,fontSize=13.sp,fontWeight=androidx.compose.ui.text.font.FontWeight.Bold)
                }else {Glyph(if(value.startsWith("+"))"forward_10_rounded"else "replay_10_rounded",size=28,color=Color.White);Spacer(Modifier.width(8.dp));Text(value,color=Color.White,fontSize=16.sp,fontWeight=androidx.compose.ui.text.font.FontWeight.Bold)}
            }
        }
        message?.let {Text(it,Modifier.align(Alignment.TopCenter).fillMaxWidth().statusBarsPadding().padding(top=64.dp,start=16.dp,end=16.dp).background(Color.Black.copy(alpha=.87f),RoundedCornerShape(16.dp)).padding(12.dp),textAlign=androidx.compose.ui.text.style.TextAlign.Center,maxLines=3,overflow=androidx.compose.ui.text.style.TextOverflow.Ellipsis,color=Color.White)}
        if(held)Box(Modifier.align(Alignment.TopCenter).statusBarsPadding().padding(top=56.dp)){FlutterLabelChip("2.0X 倍速快进中")}
        if(showChrome){
            Row(Modifier.align(Alignment.TopCenter).fillMaxWidth().statusBarsPadding().background(Color.Black.copy(alpha=.54f)),verticalAlignment=Alignment.CenterVertically) {
                VideoButton("arrow_back","返回",{if(landscape){landscape=false;activity?.requestedOrientation=ActivityInfo.SCREEN_ORIENTATION_PORTRAIT}else onBack()})
                Text(request.post?.author?.name?:request.author,Modifier.weight(1f),maxLines=1,overflow=androidx.compose.ui.text.style.TextOverflow.Ellipsis,color=Color.White)
                Text("${request.media.indexOf(media)+1}/${request.media.size}",color=Color.White.copy(alpha=.7f))
                onPrevious?.let {VideoButton("chevron_left","上一个媒体",it)};onNext?.let {VideoButton("chevron_right","下一个媒体",it)}
                if(saving)Box(Modifier.size(48.dp),contentAlignment=Alignment.Center){FlutterProgress(Modifier.size(20.dp),strokeWidth=2.dp)}else VideoButton("download","保存视频",{selected?.let {onSave(media.copy(variants=listOf(it)))}})
                VideoButton("share","分享视频",{player.pause();runCatching {NativeServices.share(context,request.post?.url?:selected?.url.orEmpty(),"分享视频")}.onFailure {NativeServices.copy(context,request.post?.url?:selected?.url.orEmpty());onMessage("链接已复制")}})
            }
            val screenHeight=LocalConfiguration.current.screenHeightDp.dp
            Column(Modifier.align(Alignment.BottomCenter).onSizeChanged {onControlsHeight(it.height)}.fillMaxWidth().background(Brush.verticalGradient(listOf(Color.Transparent,Color.Black.copy(alpha=.87f),Color.Black))).navigationBarsPadding().padding(start=12.dp,end=12.dp,top=12.dp,bottom=8.dp).heightIn(max=screenHeight*.55f).verticalScroll(rememberScrollState())) {
                request.post?.let {raw->val post=model.effective(raw)
                    Row(Modifier.fillMaxWidth()) {
                        VideoAction("评论","chat_bubble_outline",compact(post.replies),false,Color.White){player.pause();menu="comments"}
                        VideoAction(if(post.reposted)"取消转发"else "转发","repeat",compact(post.reposts),model.blocked(post.id),if(post.reposted)Color(0xFF69F0AE)else Color.White){model.mutate(post,"repost")}
                        VideoAction(if(post.liked)"取消喜欢"else "喜欢",if(post.liked)"favorite"else "favorite_border",compact(post.likes),model.blocked(post.id),if(post.liked)Color(0xFFFF4081)else Color.White){model.mutate(post,"like")}
                        VideoAction(if(post.bookmarked)"移除书签"else "加入书签",if(post.bookmarked)"bookmark"else "bookmark_outline",null,model.blocked(post.id),if(post.bookmarked)Color(0xFF40C4FF)else Color.White){model.mutate(post,"bookmark")}
                    }
                    if(accountState.accountId==post.author.id)FlutterTextButton(onClick={delete=true},enabled=!model.blocked(post.id),modifier=Modifier.align(Alignment.CenterHorizontally)){Glyph("delete_outline",color=Color(0xFFFF5252));Spacer(Modifier.width(8.dp));Text("删除帖子",color=Color(0xFFFF5252))}
                    if(post.id in accountState.uncertain)Text("操作结果待核对，请在帖子详情刷新",color=Color(0xFFFFD740),fontSize=12.sp)
                }
                Box(Modifier.fillMaxWidth().padding(vertical=10.dp).height(5.dp).background(Color.White.copy(alpha=.12f)).pointerInput(duration) {detectTapGestures {if(duration>0)player.seekTo((it.x/size.width*duration).toLong().coerceIn(0,duration))}}.pointerInput(duration) {detectDragGestures {change,_->if(duration>0){change.consume();player.seekTo((change.position.x/size.width*duration).toLong().coerceIn(0,duration))}}}) {
                    Box(Modifier.fillMaxHeight().fillMaxWidth(if(duration>0)(buffered.toFloat()/duration).coerceIn(0f,1f)else 0f).background(Color.White.copy(alpha=.38f)))
                    Box(Modifier.fillMaxHeight().fillMaxWidth(if(duration>0)((seekDraft?:position.toFloat())/duration).coerceIn(0f,1f)else 0f).background(Color.White))
                }
                FlowRow(verticalArrangement=Arrangement.Center,horizontalArrangement=Arrangement.SpaceBetween,modifier=Modifier.fillMaxWidth()) {
                    VideoButton(if(playing)"pause"else "play_arrow",if(playing)"暂停"else "播放",{if(player.isPlaying){player.pause();autoPlay=false}else{if(player.playbackState==Player.STATE_ENDED)player.seekTo(0);player.play();autoPlay=true}},enabled=duration>0)
                    VideoButton(if(muted)"volume_off_rounded"else "volume_up_rounded",if(muted)"取消静音"else "静音",{muted=!muted;if(!muted&&gain==0f)gain=1f},enabled=duration>0)
                    Box(Modifier.width(with(LocalDensity.current){80.sp.toDp()}).height(48.dp),contentAlignment=Alignment.Center){Text(if(duration>0)"${videoTime(position)} / ${videoTime(duration)}"else "--:-- / --:--",fontSize=12.sp,maxLines=1,color=Color.White.copy(alpha=.7f))}
                    FlutterTextButton(onClick={menu="speed"},modifier=Modifier.width(with(LocalDensity.current){56.sp.toDp()}).height(48.dp),contentPadding=PaddingValues(horizontal=6.dp)){Text("${speed}X",color=Color.White)}
                    FlutterTextButton(onClick={menu="quality"},enabled=media.variants.size>1,modifier=Modifier.width(with(LocalDensity.current){56.sp.toDp()}).height(48.dp),contentPadding=PaddingValues(horizontal=6.dp)){Text(selected?.let{val h=videoHeight(it.url);if(h>0)"${h}p"else "高清"}?:"高清",color=Color.White.copy(alpha=.7f))}
                    VideoButton(if(landscape)"fullscreen_exit"else "fullscreen",if(landscape)"竖屏"else "横屏",{landscape=!landscape;activity?.requestedOrientation=if(landscape)ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE else ActivityInfo.SCREEN_ORIENTATION_PORTRAIT;onChrome(true)})
                }
            }
        }

    }
    if(delete)FlutterAlertDialog(onDismissRequest={delete=false},title={Text("删除帖子？")},text={Text("删除后无法恢复。")},confirmButton={FlutterTextButton(onClick={delete=false;request.post?.let {model.mutate(it,"delete")};onBack()}){Text("删除",color=Color.Red)}},dismissButton={FlutterTextButton(onClick={delete=false}){Text("取消")}})
    if(menu!=null)FlutterBottomSheet(onDismissRequest={menu=null},shape=RoundedCornerShape(topStart=if(menu=="comments")28.dp else 16.dp,topEnd=if(menu=="comments")28.dp else 16.dp),containerColor=if(menu=="comments")Color.Unspecified else Color(0xFF212121),contentColor=if(menu=="comments")MaterialTheme.colorScheme.onSurface else Color.White){Column(Modifier.heightIn(max=LocalConfiguration.current.screenHeightDp.dp*.8f).verticalScroll(rememberScrollState()).navigationBarsPadding().padding(vertical=if(menu=="comments")0.dp else 16.dp)) {when(menu){
        "speed"->{Text("播放倍速",Modifier.padding(horizontal=20.dp,vertical=8.dp),color=Color.White.copy(alpha=.7f),fontSize=13.sp,fontWeight=androidx.compose.ui.text.font.FontWeight.Bold);listOf(3f,2f,1.5f,1.25f,1f,.75f,.5f).forEach{value->VideoMenuRow("${value}X",speed==value){speed=value;menu=null;onMessage("已切换至 ${value}X 倍速")}}}
        "quality"->{Text("清晰度选择",Modifier.padding(horizontal=20.dp,vertical=8.dp),color=Color.White.copy(alpha=.7f),fontSize=13.sp,fontWeight=androidx.compose.ui.text.font.FontWeight.Bold);media.variants.forEach{variant->VideoMenuRow(videoHeight(variant.url).let{if(it>0)"${it}p"else "${variant.bitrate/1000} kbps"},selected==variant){menu=null;if(selected!=variant){selected=variant;onMessage("已切换至 ${videoHeight(variant.url).let{if(it>0)"${it}p"else "${variant.bitrate/1000} kbps"}}")}}}}
        "comments"->{SettingRow("查看评论",icon="forum_outlined",onClick={menu=null;onBack();request.post?.let(model::openPost)},trailing={});SettingRow("发表评论",icon="edit_outlined",onClick={menu=null;onBack();request.post?.let{actions.compose(ComposeRequest(reply=it))}},trailing={})}
    }}}

}
fun videoTime(ms:Long):String {val seconds=(ms/1000).coerceAtLeast(0);return if(seconds>=3600)"%d:%02d:%02d".format(seconds/3600,seconds/60%60,seconds%60)else "%02d:%02d".format(seconds/60,seconds%60)}

@Composable private fun VideoButton(icon:String,label:String,onClick:()->Unit,enabled:Boolean=true) {IconButton(onClick=hapticClick(onClick),enabled=enabled,modifier=Modifier.size(48.dp)){Glyph(icon,label,color=if(enabled)Color.White else Color.White.copy(alpha=.38f))}}
@Composable private fun RowScope.VideoAction(label:String,icon:String,count:String?,disabled:Boolean,color:Color,onClick:()->Unit) {
    FlutterTextButton(onClick=onClick,enabled=!disabled,modifier=Modifier.weight(1f).heightIn(min=48.dp),contentPadding=PaddingValues(horizontal=4.dp)) {Glyph(icon,label,size=23,color=if(disabled)Color.White.copy(alpha=.38f)else color);if(count!=null){Spacer(Modifier.width(5.dp));Text(count,color=if(disabled)Color.White.copy(alpha=.38f)else color,maxLines=1)}}
}

internal fun galleryButtonStretch(x:Float,y:Float):FloatArray {
    fun pivot(value:Float):Float {val t=(abs(value)/20f).coerceIn(0f,1f);return .5f-kotlin.math.sign(value)*t*t*(3-2*t)*.5f}
    val rx=abs(x)/48f;val ry=abs(y)/48f
    return floatArrayOf((1+(rx*.8f).coerceAtMost(.3f))*(1-(ry*.3f).coerceAtMost(.15f)),(1+(ry*.8f).coerceAtMost(.3f))*(1-(rx*.3f).coerceAtMost(.15f)),pivot(x),pivot(y))
}

@Composable internal fun VideoMenuRow(title:String,selected:Boolean,onClick:()->Unit) {
    val color=if(selected)MaterialTheme.colorScheme.primary else Color.White
    SettingRow(title,onClick=onClick,trailing={if(selected)Glyph("check_rounded",size=20,color=color)},titleStyle=flutterTileTitle().copy(color=color,fontWeight=if(selected)androidx.compose.ui.text.font.FontWeight.Bold else androidx.compose.ui.text.font.FontWeight.Normal),minHeight=54.dp)
}
