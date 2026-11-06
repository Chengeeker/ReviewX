package com.review.x

import android.graphics.RenderEffect
import android.graphics.RuntimeShader
import android.graphics.Shader
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.layer.GraphicsLayer
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.IntSize
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.merge
import kotlinx.coroutines.flow.map
import kotlin.math.roundToInt

class Backdrop(val layer:GraphicsLayer) {
    var coordinates: LayoutCoordinates? = null
    var origin=Offset.Zero
    var captureInset=0
    var referenceSize=IntSize.Zero
    var version=0L
    val changes=MutableSharedFlow<Long>(replay=1,extraBufferCapacity=1,onBufferOverflow=BufferOverflow.DROP_OLDEST)
}
val LocalBackdrop=staticCompositionLocalOf<Backdrop?> {null}
@Composable fun rememberBackdrop():Backdrop {val layer=rememberGraphicsLayer();return remember(layer){Backdrop(layer)}}
fun Modifier.recordBackdrop(source:Backdrop,background:Backdrop?=null,padding:androidx.compose.ui.unit.Dp=androidx.compose.ui.unit.Dp(0f),notify:Boolean=true)=then(if (notify) Modifier.graphicsLayer() else Modifier).onGloballyPositioned {
    source.coordinates = it
    source.origin = it.positionInWindow()
}.drawWithContent {
    val inset=padding.roundToPx();val origin=source.origin-Offset(inset.toFloat(),inset.toFloat())
    source.layer.record(size=IntSize(size.width.roundToInt()+2*inset,size.height.roundToInt()+2*inset)) {
        if(background!=null&&background.layer.size.width>0)translate(background.origin.x-background.captureInset-origin.x,background.origin.y-background.captureInset-origin.y){drawLayer(background.layer)}
        translate(inset.toFloat(),inset.toFloat()){this@drawWithContent.drawContent()}
    }
    translate(-inset.toFloat(),-inset.toFloat()){drawLayer(source.layer)}
    source.captureInset=inset
    source.referenceSize=background?.referenceSize?.takeIf{it.width>0}?:source.layer.size
    if (notify) source.changes.tryEmit(++source.version)
}

data class GlassStyle(val tint:Color,val thickness:Float=10f,val refractiveIndex:Float=1.19f,val chromatic:Float=.008f,
    val light:Float=.25f,val saturation:Float=1.5f,val rimShade:Float=0f,val rimLight:Float=1f,val pinch:Float=0f,val blur:Float=2f,val radius:Float=32f,val basicGallery:Boolean=false,val frosted:Boolean=false) {
    fun uniforms(width:Int,height:Int,dpr:Float,padding:Float=0f,reference:IntSize=IntSize(width,height)):Map<String,FloatArray> = linkedMapOf(
        "uSize" to floatArrayOf(width.toFloat(),height.toFloat()),"uGeometryOffset" to floatArrayOf(padding,padding),
        "uGeometrySize" to floatArrayOf(width-2*padding,height-2*padding),"uBackdropSize" to floatArrayOf(reference.width.toFloat(),reference.height.toFloat()),"uGlassColor" to floatArrayOf(tint.red,tint.green,tint.blue,tint.alpha),
        "uOpticalProps" to floatArrayOf(refractiveIndex,chromatic,thickness*dpr/3f,1f),"uLightConfig" to floatArrayOf(light,0f,saturation),
        "uLightDirection" to floatArrayOf(-.70710677f,.70710677f),"uWhiten" to floatArrayOf(0f),"uWhitenGated" to floatArrayOf(1f),
        "uPinchStrength" to floatArrayOf(pinch),"uBackgroundFallback" to floatArrayOf(0f,0f,0f,0f),"uCaptureOffset" to floatArrayOf(0f,0f),
        "uEdgeConfig" to floatArrayOf(0f,1f,dpr/3f,0f),"uPlatformViewMode" to floatArrayOf(0f),"uBodyMode" to floatArrayOf(1f),
        "uTouchPosition" to floatArrayOf(0f,0f),"uTouchIntensity" to floatArrayOf(0f),"uRimConfig" to floatArrayOf(rimShade,rimLight,0f),
        "uLensModel" to floatArrayOf(0f),"uFrost" to floatArrayOf(0f,0f,0f,0f),"uBodyShade" to floatArrayOf(0f),
        "uDpr" to floatArrayOf(dpr),"uRadius" to floatArrayOf(radius*dpr))
}

@RequiresApi(33)
private class GlassEffect(source:String) {
    val shader=RuntimeShader(source)
    fun configure(style:GlassStyle,size:IntSize,dpr:Float,padding:Float,reference:IntSize):androidx.compose.ui.graphics.RenderEffect {
        style.uniforms(size.width,size.height,dpr,padding,reference).filterKeys {(!style.basicGallery&&!style.frosted) || it=="uSize"}.forEach {(name,value)->shader.setFloatUniform(name,value)}
        val effect=RenderEffect.createRuntimeShaderEffect(shader,"uBackgroundTexture")
        return (if(style.blur>0)RenderEffect.createChainEffect(effect,RenderEffect.createBlurEffect(style.blur*dpr,style.blur*dpr,Shader.TileMode.CLAMP))else effect).asComposeRenderEffect()
    }
}

@Composable fun GlassSurface(style:GlassStyle,modifier:Modifier=Modifier,content:@Composable BoxScope.()->Unit={}) {
    val backdrop=LocalBackdrop.current
    val context=LocalContext.current;val dpr=LocalDensity.current.density;val crop=rememberGraphicsLayer()
    var position by remember {mutableStateOf(Offset.Zero)};var dimensions by remember {mutableStateOf(IntSize.Zero)}
    var frame by remember {mutableLongStateOf(0)}
    val currentStyle by rememberUpdatedState(style)
    val padding=if(style.basicGallery)0 else kotlin.math.ceil(kotlin.math.max(24f,style.blur*3f)*dpr).toInt()
    val currentPadding by rememberUpdatedState(padding)
    val asset=if(style.frosted)"frost"else if(style.basicGallery)"gallery"else "premium"
    val effect=if(Build.VERSION.SDK_INT>=33)remember(asset) {runCatching {GlassEffect(context.assets.open("glass/$asset.agsl").bufferedReader().use{it.readText()})}.onFailure {DiagnosticLog.record("glass.shader",error=it)}.getOrNull()}else null
    var shaderFailed by remember(asset) {mutableStateOf(effect==null&&Build.VERSION.SDK_INT>=33)}
    var legacyFallback by remember {mutableStateOf(false)}
    var legacyImage by remember {mutableStateOf<ImageBitmap?>(null)}
    LaunchedEffect(backdrop,asset) {
        if(backdrop==null)return@LaunchedEffect
        if(Build.VERSION.SDK_INT>=33)backdrop.changes.collect {frame=it}
        else {
            // Only the small control crop crosses the GPU boundary on API 24–32.
            val dispatcher=LegacyGlassEngine.dispatcher
            val renderer=withContext(dispatcher){runCatching {LegacyGlassEngine.acquire(context)}.onFailure {DiagnosticLog.record("glass.legacy",error=it)}.getOrNull()}
            legacyFallback=renderer==null
            try {merge(backdrop.changes.map {Unit},snapshotFlow {Triple(currentStyle,position,dimensions)}.map {Unit}).collect {
                if(dimensions.width<=0 || dimensions.height<=0)return@collect
                frame++
                withFrameNanos { }
                val captured=crop.toImageBitmap().asAndroidBitmap()
                val rendered=try {withContext(dispatcher){
                    if(renderer==null||legacyFallback)glassFallback(captured,currentStyle.blur*dpr)
                    else {
                        val input=if(currentStyle.frosted)android.graphics.Bitmap.createScaledBitmap(captured,(captured.width/4).coerceAtLeast(1),(captured.height/4).coerceAtLeast(1),true)else captured
                        try {renderer.render(input,currentStyle,if(currentStyle.frosted)dpr/4 else dpr,if(currentStyle.frosted)currentPadding/4f else currentPadding.toFloat(),backdrop.referenceSize)}catch(e:Exception){
                            DiagnosticLog.record("glass.render",error=e);legacyFallback=true;glassFallback(captured,currentStyle.blur*dpr)
                        }finally {if(input!==captured)input.recycle()}
                    }
                }}finally {captured.recycle()}
                legacyImage=rendered.asImageBitmap()
                delay(33)
            }}finally {withContext(NonCancellable+dispatcher){if(renderer!=null)LegacyGlassEngine.release()}}
        }
    }
    val fallbackClip=remember(dimensions,style.radius,dpr){Path().apply{addRoundRect(androidx.compose.ui.geometry.RoundRect(0f,0f,dimensions.width.toFloat(),dimensions.height.toFloat(),androidx.compose.ui.geometry.CornerRadius(style.radius*dpr)))}}
    Box(modifier.onGloballyPositioned {position=it.positionInWindow();dimensions=it.size}.graphicsLayer().drawWithContent {
        frame
        if(backdrop!=null && backdrop.layer.size.width>0) {
            val delta=position-backdrop.origin+Offset(backdrop.captureInset.toFloat(),backdrop.captureInset.toFloat())
            val capturedSize=IntSize(size.width.roundToInt()+2*padding,size.height.roundToInt()+2*padding)
            crop.record(size=capturedSize) {translate(padding-delta.x,padding-delta.y){drawLayer(backdrop.layer)}}
            if(Build.VERSION.SDK_INT>=33) {
                crop.renderEffect=if(effect!=null&&!shaderFailed)try{effect.configure(style,capturedSize,dpr,padding.toFloat(),backdrop.layer.size)}catch(e:Exception){DiagnosticLog.record("glass.effect",error=e);shaderFailed=true;null}else null
                if(shaderFailed&&style.blur>0)crop.renderEffect=RenderEffect.createBlurEffect(style.blur*dpr,style.blur*dpr,Shader.TileMode.CLAMP).asComposeRenderEffect()
                clipPath(fallbackClip){translate(-padding.toFloat(),-padding.toFloat()){drawLayer(crop)}}
            }
            else legacyImage?.let {image->clipPath(fallbackClip){drawImage(image,dstOffset=androidx.compose.ui.unit.IntOffset(-padding,-padding),dstSize=capturedSize,filterQuality=FilterQuality.Medium)}}
        }
        if(shaderFailed||legacyFallback)drawRoundRect(style.tint,cornerRadius=androidx.compose.ui.geometry.CornerRadius(style.radius*dpr))
        drawContent()
    },content=content)
}
