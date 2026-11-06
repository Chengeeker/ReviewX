package com.review.x

import android.os.Build
import android.content.Context
import android.graphics.RenderEffect
import android.graphics.RuntimeShader
import androidx.annotation.RequiresApi
import androidx.compose.foundation.layout.Box
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.*
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.*
import androidx.compose.ui.graphics.layer.GraphicsLayer
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import kotlin.math.roundToInt

@RequiresApi(33)
private class GlassOptics(context: Context) {
    val shader =
        RuntimeShader(
            context.assets.open("glass/liquid_glass.agsl").bufferedReader().use { it.readText() }
        )

    fun configure(
        size: Size,
        shape: Rect,
        density: Float,
        dark: Boolean,
        lens: Boolean = false,
        pressed: Float = 0f,
        dragging: Boolean = false,
        kind: Int = 0,
        touch: Float = 0f,
    ) {
        val fade = if (lens) pressed.coerceIn(.001f, 1f) else 1f
        val dpr = density / 3f
        val ri = if (lens) 1f + .18f * fade else if (kind == 1) 1.24f else 1.16f
        val thickness = (if (lens) 20f * fade else if (kind == 1) 32f else 10f) * dpr
        val rgb =
            if (lens) {
                if (dark) 1f else 0f
            } else {
                if (dark || kind == 1) 0f else 1f
            }
        shader.apply {
            setFloatUniform("uSize", size.width, size.height)
            setFloatUniform("shape", shape.center.x, shape.center.y, shape.width, shape.height)
            setFloatUniform("uGeometryOffset", shape.left, shape.top)
            setFloatUniform("uGeometrySize", shape.width, shape.height)
            setFloatUniform(
                "uGlassColor",
                rgb,
                rgb,
                rgb,
                (if (lens) {
                    if (dark) 38f / 255 else 24f / 255
                } else {
                    if (dark || kind == 1) .4f else 240f / 255
                }) * fade,
            )
            setFloatUniform(
                "uOpticalProps",
                ri,
                if (lens || kind == 1) .025f * fade else .008f,
                thickness,
                1f,
            )
            setFloatUniform(
                "uLightConfig",
                (if (lens) 2f else .25f) * fade,
                0f,
                if (lens || kind == 1) 1.5f else 1f,
            )
            setFloatUniform("uLightDirection", -.7071068f, .7071068f)
            setFloatUniform("uWhiten", 0f)
            setFloatUniform("uWhitenGated", 1f)
            setFloatUniform(
                "uPinchStrength",
                if (lens && dragging) .7f * (1 - (1 - fade) * (1 - fade)) else 0f,
            )
            setFloatUniform("uBackgroundFallback", 0f, 0f, 0f, 0f)
            setFloatUniform("uCaptureOffset", 0f, 0f)
            setFloatUniform("uEdgeConfig", 0f, fade, dpr, 0f)
            setFloatUniform("uPlatformViewMode", 0f)
            setFloatUniform("uBodyMode", 1f)
            setFloatUniform("uTouchPosition", shape.center.x, shape.center.y)
            setFloatUniform("uTouchIntensity", (if (kind == 1) touch else pressed) * .125f)
            setFloatUniform(
                "uRimConfig",
                if (lens && !dark) .12f * fade else 0f,
                (if (kind == 1) 0f
                else if (dark) {
                    if (lens || kind == 3) 0f else .12f
                } else {
                    if (lens) .35f else 1f
                }) * fade,
                .2f,
            )
            setFloatUniform("uLensModel", 0f)
            setFloatUniform("uFrost", 0f, 0f, 0f, 1f)
            setFloatUniform("uBodyShade", 0f)
            setFloatUniform("uNativeEdge", if (!dark && lens) 1f else 0f)
        }
    }

    fun effect(): androidx.compose.ui.graphics.RenderEffect =
        RenderEffect.createRuntimeShaderEffect(shader, "background").asComposeRenderEffect()
}

// RedNote Compose 1.1.0-compose.11 shared shader and GPU passes with ReviewX backdrop placement.
@RequiresApi(Build.VERSION_CODES.TIRAMISU)
@Composable
internal fun LiquidNavigationGpu(
    backdrop: Backdrop?,
    labels: GraphicsLayer,
    activeLabels: GraphicsLayer,
    position: State<Float>,
    lens: State<Float>,
    modifier: Modifier,
) {
    val context = LocalContext.current
    val optics = remember(context) {
        runCatching {
            GlassOptics(context) to GlassOptics(context)
        }.onFailure { DiagnosticLog.record("glass.navigation", error = it) }.getOrNull()
    }
    val crop = rememberGraphicsLayer()
    val blurred = rememberGraphicsLayer()
    val body = rememberGraphicsLayer()
    val underPill = rememberGraphicsLayer()
    val pillBlur = rememberGraphicsLayer()
    val combined = rememberGraphicsLayer()
    val water = rememberGraphicsLayer()
    var coordinates by remember { mutableStateOf<LayoutCoordinates?>(null) }
    var velocity by remember { mutableFloatStateOf(0f) }
    val hasWater by remember(lens) { derivedStateOf { lens.value > .001f } }
    LaunchedEffect(hasWater) {
        velocity = 0f
        if (hasWater) {
            var lastFrame = withFrameNanos { it }
            var lastLens = position.value
            while (true) {
                val frame = withFrameNanos { it }
                velocity = (position.value - lastLens) * 1_000_000_000f / (frame - lastFrame)
                lastFrame = frame
                lastLens = position.value
            }
        }
    }
    val dark = LocalDarkTheme.current
    val scene = LocalChrome.current.background
    val fallback = MaterialTheme.colorScheme.surfaceContainerHigh
    val selection = if (dark) Color(0x26FFFFFF) else Color(0x26000000)
    Box(modifier.onGloballyPositioned { coordinates = it }.drawWithCache {
        val dpr = density
        val dimensions = IntSize(size.width.roundToInt(), size.height.roundToInt())
        val bar = Rect(20.dp.toPx(), 15.dp.toPx(), size.width - 20.dp.toPx(), size.height - 15.dp.toPx())
        val slot = (bar.width - 8.dp.toPx()) / 3
        val labelOffset = bar.topLeft + Offset(4.dp.toPx(), 0f)
        val mask = Path()
        fun blur(sigma: Float): BlurEffect {
            val radius = ((sigma * dpr - .5f) / .57735f).coerceAtLeast(.01f)
            return BlurEffect(radius, radius, TileMode.Clamp)
        }
        blurred.renderEffect = blur(1.5f)
        pillBlur.renderEffect = blur(6f)
        body.renderEffect = optics?.first?.let {
            it.configure(size, bar, dpr, dark)
            it.effect()
        }

        onDrawBehind {
            val strength = lens.value.coerceIn(0f, 1f)
            val center = labelOffset.x + slot * (position.value + .5f)
            val jelly = jellyScale(velocity, strength)
            val halfWidth = (slot * (1f + .06f * strength) / 2f + 12.dp.toPx() * strength) * jelly[0]
            val halfHeight = (24.dp.toPx() * (1f + .06f * strength) + 8.dp.toPx() * strength) * jelly[1]
            val pill = Rect(center - halfWidth, bar.center.y - halfHeight, center + halfWidth, bar.center.y + halfHeight)
            mask.rewind()
            mask.addRoundRect(RoundRect(pill, CornerRadius(minOf(halfWidth, halfHeight))))
            val rest = 1f - strength
            val target = coordinates?.takeIf { it.isAttached }
            val source = backdrop?.coordinates?.takeIf { it.isAttached }
            fun DrawScope.drawLabels() {
                clipPath(mask, ClipOp.Difference) {
                    translate(labelOffset.x, labelOffset.y) { drawLayer(labels) }
                }
                clipPath(mask) {
                    translate(labelOffset.x, labelOffset.y) { drawLayer(activeLabels) }
                }
            }
            if (optics == null || target == null || source == null ||
                !drawContext.canvas.nativeCanvas.isHardwareAccelerated
            ) {
                drawRoundRect(fallback, bar.topLeft, bar.size, CornerRadius(bar.height / 2))
                drawPath(mask, selection)
                drawLabels()
                return@onDrawBehind
            }
            val origin = target.localToRoot(Offset.Zero)
            val extent = target.localToRoot(Offset(size.width, size.height)) - origin
            if (extent.x <= 0f || extent.y <= 0f) return@onDrawBehind
            val sourceOffset = source.localToRoot(Offset.Zero) - origin
            crop.record(this, layoutDirection, dimensions) {
                clipRect {
                    drawRect(scene)
                    scale(size.width / extent.x, size.height / extent.y, Offset.Zero) {
                        translate(sourceOffset.x, sourceOffset.y) { drawLayer(backdrop.layer) }
                    }
                }
            }
            blurred.record(this, layoutDirection, dimensions) { drawLayer(crop) }
            body.record(this, layoutDirection, dimensions) { drawLayer(blurred) }
            if (rest > .001f) {
                underPill.record(this, layoutDirection, dimensions) {
                    drawLayer(crop)
                    drawLayer(body)
                }
                pillBlur.record(this, layoutDirection, dimensions) { drawLayer(underPill) }
                pillBlur.alpha = rest
            }
            combined.record(this, layoutDirection, dimensions) {
                drawLayer(body)
                if (rest > .001f) clipPath(mask) {
                    drawLayer(pillBlur)
                    drawRect(selection.copy(alpha = selection.alpha * rest))
                }
                drawLabels()
            }
            drawLayer(combined)
            if (strength > .001f) {
                optics.second.configure(size, pill, dpr, dark, lens = true, pressed = strength, dragging = true)
                water.renderEffect = optics.second.effect()
                water.alpha = strength
                water.record(this, layoutDirection, dimensions) {
                    drawLayer(crop)
                    drawLayer(combined)
                }
                drawLayer(water)
            }
        }
    })
}
