package com.review.x

import android.os.Build
import androidx.compose.animation.core.*
import androidx.compose.foundation.*
import androidx.compose.foundation.gestures.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.*
import androidx.compose.ui.draw.*
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.layer.GraphicsLayer
import androidx.compose.ui.input.pointer.*
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.*
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.*
import kotlinx.coroutines.*
import kotlin.math.abs

@Composable fun LiquidNavigation(selected:Int,onSelect:(Int)->Unit,onDouble:(Int)->Unit,width:Dp) {
    val light=!LocalDarkTheme.current
    val haptics by rememberUpdatedState(LocalHapticFeedback.current)
    val select by rememberUpdatedState(onSelect);val double by rememberUpdatedState(onDouble);val current by rememberUpdatedState(selected)
    var touching by remember { mutableStateOf(false) }
    var dragging by remember { mutableStateOf(false) }
    var longPressed by remember { mutableStateOf(false) }
    var target by remember { mutableFloatStateOf(selected.toFloat()) }
    val (position, lens) = navigationGlassMotion(selected, touching, dragging, target, longPressed)
    val slot = (width - 8.dp) / 3
    val page=LocalBackdrop.current;val labels=listOf("首页","探索","设置");val icons=listOf("home_outlined","explore_outlined","settings_outlined");val active=listOf("home_rounded","explore","settings_rounded")
    val interaction=Modifier.pointerInput(Unit) {
        coroutineScope {
            var lastTapTime=0L;var lastTab=-1;var pending:Job?=null
            awaitEachGesture {
                val down=awaitFirstDown(requireUnconsumed=false);val start=down.position;val startIndex=current
                val tracker=VelocityTracker();tracker.addPosition(down.uptimeMillis,down.position)
                var destination=(start.x/size.width*3).toInt().coerceIn(0,2);var moved=false;var cancelled=false;var held=false
                touching = true; target = (start.x / size.width * 3 - .5f).coerceIn(0f, 2f)
                val hold = launch {
                    delay(220)
                    held = true
                    dragging = true
                    longPressed = true
                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                }
                var released=down
                try {
                    do {
                        val change = awaitPointerEvent(PointerEventPass.Initial).changes.firstOrNull { it.id == down.id } ?: break
                        released = change
                        if (change.isConsumed && !change.pressed) {
                            cancelled = true
                            break
                        }
                        tracker.addPosition(change.uptimeMillis, change.position)
                        val delta = change.position - start
                        if (delta.getDistance() > viewConfiguration.touchSlop) hold.cancel()
                        if (!moved && abs(delta.y) > viewConfiguration.touchSlop && abs(delta.y) > abs(delta.x)) {
                            cancelled = true
                        }
                        if (!cancelled && abs(delta.x) > viewConfiguration.touchSlop && abs(delta.x) > abs(delta.y)) {
                            moved = true
                            dragging = true
                        }
                        if (!cancelled && (moved || held)) {
                            target = (change.position.x / size.width * 3 - .5f).coerceIn(0f, 2f)
                            destination = (change.position.x / size.width * 3).toInt().coerceIn(0, 2)
                            change.consume()
                        }
                    } while (released.pressed)
                } finally {
                    hold.cancel()
                    touching = false
                    dragging = false
                    longPressed = false
                }
                if(!cancelled && !released.pressed) {
                    if(moved && abs(tracker.calculateVelocity().x)>1000*density)destination=destination.coerceIn((startIndex-1).coerceAtLeast(0),(startIndex+1).coerceAtMost(2))
                    if(moved||held){pending?.cancel();if(destination!=startIndex)select(destination)}
                    else if (destination != current) {
                        pending?.cancel()
                        lastTab = -1
                        select(destination)
                    } else if (destination == 2) {
                        pending?.cancel()
                        lastTab = -1
                    }
                    else if(lastTab==destination && down.uptimeMillis-lastTapTime<=viewConfiguration.doubleTapTimeoutMillis){pending?.cancel();lastTab=-1;double(destination)}
                    else {lastTab=destination;lastTapTime=down.uptimeMillis;pending?.cancel();pending=launch {delay(viewConfiguration.doubleTapTimeoutMillis);if (destination != current) return@launch;select(destination)}}
                }
            }
        }
    }
    @Composable fun tabIcons(selectedLayer: Boolean, layer: GraphicsLayer? = null, mask: Path? = null) {
        Row(Modifier.fillMaxSize().padding(horizontal = 4.dp)
            .then(if (selectedLayer) Modifier.clearAndSetSemantics {} else Modifier)
            .drawWithContent {
                if (layer != null) layer.record { this@drawWithContent.drawContent() }
                else if (mask != null) {
                    val localMask = Path().apply { addPath(mask, Offset(-4.dp.toPx(), 0f)) }
                    clipPath(localMask, if (selectedLayer) ClipOp.Intersect else ClipOp.Difference) {
                        this@drawWithContent.drawContent()
                    }
                }
            }) {labels.forEachIndexed {i,label->
            val color=if(selectedLayer)MaterialTheme.colorScheme.primary else if(light)MaterialTheme.colorScheme.onSurfaceVariant else Color.White
            Column(Modifier.weight(1f).fillMaxHeight().graphicsLayer{if(selectedLayer){scaleX=1f+.15f*lens.value;scaleY=1f+.15f*lens.value}}.semantics(mergeDescendants=true){this.selected=i==selected;role=Role.Tab;onClick {select(i);true}},horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.Center) {
                Glyph(if(selectedLayer)active[i]else icons[i],size=24,color=color)
                Spacer(Modifier.height(4.dp))
                Text(label, Modifier.flutterLineHeight(16.sp), fontSize = 11.sp, lineHeight = 16.sp,
                    fontWeight = if(selectedLayer)FontWeight.SemiBold else FontWeight.Normal, color = color)
            }
        }}
    }
    Box(Modifier.width(width).height(56.dp).then(interaction)) {
        if (light) Box(Modifier.fillMaxSize().glassEdgeShadow(
            GlassShadow(4.4f, 1.1f, Color.Black.copy(alpha = .033f)),
            GlassShadow(1.1f, .55f, Color.Black.copy(alpha = .011f)),
        ))
        if (Build.VERSION.SDK_INT >= 33) {
            val labelsLayer = rememberGraphicsLayer()
            val selectedLayer = rememberGraphicsLayer()
            tabIcons(false, layer = labelsLayer)
            tabIcons(true, layer = selectedLayer)
            LiquidNavigationGpu(
                page, labelsLayer, selectedLayer, position, lens,
                Modifier.requiredSize(width + 40.dp, 86.dp).align(Alignment.Center),
            )
        } else {
            val base = rememberBackdrop()
            val bar = rememberBackdrop()
            val pressure = lens.value.coerceIn(0f, 1f)
            val expansion = (12.dp + slot * .03f) * pressure
            val vertical = (8.dp + 24.dp * .06f) * pressure
            val restOpacity = 1f - pressure
            val density = LocalDensity.current
            val pill = with(density) {
                Rect((4.dp + slot * position.value - expansion).toPx(), (4.dp - vertical).toPx(),
                    (4.dp + slot * (position.value + 1) + expansion).toPx(), (52.dp + vertical).toPx())
            }
            val mask = remember(pill) { Path().apply { addRoundRect(RoundRect(pill, CornerRadius(pill.height / 2))) } }
            Box(Modifier.fillMaxSize().recordBackdrop(bar,page,16.dp)) {
                GlassSurface(GlassStyle(if(light)Color(0xF0FFFFFF)else Color(0x66000000),
                    refractiveIndex=1.16f,saturation=1f,blur=1.5f,rimLight=if(light)1f else .12f,radius=100f),
                    Modifier.fillMaxSize().recordBackdrop(base))
                CompositionLocalProvider(LocalBackdrop provides base) {
                    if(restOpacity>0f)GlassSurface(GlassStyle(Color.Transparent,blur=6f,radius=100f,frosted=true),Modifier.offset(x=4.dp+slot*position.value,y=4.dp).size(slot,48.dp).graphicsLayer{alpha=restOpacity}.clip(RoundedCornerShape(100.dp))) {Box(Modifier.fillMaxSize().background(if(light)Color(0x26000000)else Color(0x26FFFFFF)))}
                }
                tabIcons(false, mask = mask);tabIcons(true, mask = mask)
            }
            CompositionLocalProvider(LocalBackdrop provides bar) {
                if(pressure>.001f)GlassSurface(GlassStyle(
                    (if(light)Color(0x18000000)else Color(0x26FFFFFF)).let{it.copy(alpha=it.alpha*pressure)},
                    thickness=20f*pressure,refractiveIndex=1f+.18f*pressure,chromatic=.025f*pressure,
                    light=2f*pressure,rimShade=if(light).12f*pressure else 0f,rimLight=if(light).35f*pressure else 0f,
                    pinch=(1f-(1f-pressure)*(1f-pressure))*.7f,blur=0f,radius=100f),
                    Modifier.offset(x=4.dp+slot*position.value-expansion,y=4.dp-vertical)
                        .size(slot+expansion*2,48.dp+vertical*2).graphicsLayer{alpha=pressure})
            }
        }
        if(light)Box(Modifier.fillMaxSize().border(1.dp,Color(0xF5FFFFFF),RoundedCornerShape(100.dp)))
    }
}
