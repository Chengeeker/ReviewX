package com.review.x

import android.os.Build
import android.view.Window
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.SubcomposeLayout
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.unit.*
import androidx.core.view.WindowCompat
import kotlin.math.ceil

internal fun Window.applyReaderWindow(scaffold: Color) {
    val lightBars = scaffold.luminance() > .5f
    setBackgroundDrawable(android.graphics.drawable.ColorDrawable(scaffold.toArgb()))
    applyReviewStatusBar(dark = !lightBars)
    WindowCompat.getInsetsController(this, decorView).isAppearanceLightNavigationBars = lightBars
}

@Suppress("DEPRECATION")
internal fun Window.applyReviewStatusBar(dark: Boolean) {
    if (Build.VERSION.SDK_INT < 35) statusBarColor = android.graphics.Color.TRANSPARENT
    if (Build.VERSION.SDK_INT < 35) navigationBarColor = if (Build.VERSION.SDK_INT >= 26) android.graphics.Color.TRANSPARENT else android.graphics.Color.BLACK
    if (Build.VERSION.SDK_INT >= 29) {
        isStatusBarContrastEnforced = false
        isNavigationBarContrastEnforced = false
    }
    WindowCompat.getInsetsController(this, decorView).isAppearanceLightStatusBars = !dark
}

@Composable
internal fun SettingsStatusBar() {
    val background = LocalChrome.current.background
    Spacer(
        Modifier.fillMaxWidth().windowInsetsTopHeight(WindowInsets.statusBars)
            .background(Brush.verticalGradient(
                0f to background,
                .65f to background.copy(alpha = .88f),
                1f to background.copy(alpha = 0f),
            )),
    )
}

@Composable
internal fun ReaderPageLayout(
    overlap: Boolean,
    bottomInset: Dp,
    header: @Composable () -> Unit,
    body: @Composable (Dp) -> Unit,
    overlay: @Composable (Dp) -> Unit,
) {
    SubcomposeLayout(Modifier.fillMaxSize()) { constraints ->
        val width = constraints.maxWidth
        val height = constraints.maxHeight
        val pageHeight = (height - bottomInset.roundToPx()).coerceAtLeast(0)
        val chrome = subcompose("header", header).single().measure(
            Constraints(minWidth = width, maxWidth = width, maxHeight = pageHeight)
        )
        val bodyTop = if (overlap) 0 else chrome.height
        val content = subcompose("body") {
            body(if (overlap) chrome.height.toDp() else 0.dp)
        }.single().measure(Constraints.fixed(width, pageHeight - bodyTop))
        val overlays = subcompose("overlay") { overlay(chrome.height.toDp()) }
            .map { it.measure(Constraints(maxWidth = width, maxHeight = height)) }
        layout(width, height) {
            content.place(0, bodyTop)
            chrome.place(0, 0)
            overlays.forEach { it.place(0, 0) }
        }
    }
}

@Composable
internal fun HeaderSurface(frosted: Boolean, content: @Composable ColumnScope.() -> Unit) {
    val base = LocalChrome.current.appBar
    val backdrop = LocalBackdrop.current
    if (!frosted) {
        Column(Modifier.fillMaxWidth(), content = content)
        return
    }
    Box(Modifier.fillMaxWidth().clipToBounds()) {
        if (backdrop != null) {
            if (Build.VERSION.SDK_INT >= 31) {
                FrostedHeaderBackdrop(backdrop, base.copy(alpha = .45f), Modifier.matchParentSize())
            } else {
                GlassSurface(
                    GlassStyle(Color.Transparent, blur = 20f, frosted = true),
                    Modifier.matchParentSize(),
                )
            }
        }
        // Foreground chrome must paint above the sampled background even when a GPU effect fails.
        Column(Modifier.fillMaxWidth()
            .then(if (Build.VERSION.SDK_INT < 31) Modifier.background(base.copy(alpha = .45f)) else Modifier)
            .background(Brush.verticalGradient(listOf(base.copy(alpha = .95f), Color.Transparent)))) {
            content()
            HorizontalDivider(thickness = .5.dp, color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = .24f))
        }
    }
}

// RedNote FrostedDiscovery's clipped GPU blur, adapted to the measured ReviewX toolbar.
@Composable
private fun FrostedHeaderBackdrop(backdrop: Backdrop, tint: Color, modifier: Modifier) {
    val blur = rememberGraphicsLayer()
    val scene = LocalChrome.current.background
    var coordinates by remember { mutableStateOf<LayoutCoordinates?>(null) }
    Box(modifier.onGloballyPositioned { coordinates = it }.drawWithCache {
        val sigma = 20.dp.toPx()
        val radius = ((sigma - .5f) / .57735f).coerceAtLeast(.01f)
        blur.renderEffect = BlurEffect(radius, radius, TileMode.Clamp)
        val sampleSize = IntSize(size.width.toInt(), ceil(size.height + 3 * sigma).toInt())
        val headerSize = size
        onDrawBehind {
            val target = coordinates?.takeIf { it.isAttached }
            val source = backdrop.coordinates?.takeIf { it.isAttached }
            if (!drawContext.canvas.nativeCanvas.isHardwareAccelerated || target == null || source == null) {
                drawRect(tint)
            } else {
                val offset = source.localToRoot(Offset.Zero) - target.localToRoot(Offset.Zero)
                blur.record(this, layoutDirection, sampleSize) {
                    clipRect {
                        drawRect(scene)
                        translate(offset.x, offset.y) { drawLayer(backdrop.layer) }
                        drawRect(tint, size = Size(headerSize.width, headerSize.height))
                    }
                }
                drawLayer(blur)
            }
        }
    })
}
