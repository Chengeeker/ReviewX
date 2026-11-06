package com.review.x

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.geometry.isSpecified
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.layout.positionOnScreen
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import kotlin.math.max
import kotlin.math.min

data class GalleryPlane(val bitmap: ImageBitmap, val rect: Rect, val viewport: Rect)

data class GalleryAnchor(val bounds: Rect, val visibleBounds: Rect) {
    internal fun inOverlay(originOnScreen: Offset): GalleryAnchor = GalleryAnchor(
        bounds.translate(-originOnScreen), visibleBounds.translate(-originOnScreen),
    )
}

internal fun LayoutCoordinates.galleryAnchor(): GalleryAnchor? {
    if (!isAttached) return null
    val screen = positionOnScreen()
    if (!screen.isSpecified) return null
    val visible = boundsInWindow().translate(screen - positionInWindow())
    if (visible.width <= 0f || visible.height <= 0f) return null
    return GalleryAnchor(Rect(screen, Size(size.width.toFloat(), size.height.toFloat())), visible)
}

class GalleryFlightState(
    val sourceScope: Any?,
    val sourceImage: ImageBitmap?,
    initialIndex: Int,
) {
    var index by mutableIntStateOf(initialIndex)
    var active by mutableStateOf(false)
}

internal val LocalGalleryFlight = staticCompositionLocalOf<GalleryFlightState?> { null }

@Composable
internal fun Modifier.hideGallerySource(scope: Any, index: Int): Modifier {
    val flight = LocalGalleryFlight.current ?: return this
    if (flight.sourceScope !== scope || flight.index != index) return this
    return drawWithContent { if (!flight.active) drawContent() }
}

internal fun galleryImagePlane(bounds: Rect, image: Size, crop: Boolean): Rect {
    if (bounds.width <= 0f || bounds.height <= 0f || image.width <= 0f || image.height <= 0f)
        return bounds
    val scaleX = bounds.width / image.width
    val scaleY = bounds.height / image.height
    val scale = if (crop) max(scaleX, scaleY) else min(scaleX, scaleY)
    val width = image.width * scale
    val height = image.height * scale
    return Rect(
        bounds.center.x - width / 2,
        bounds.center.y - height / 2,
        bounds.center.x + width / 2,
        bounds.center.y + height / 2,
    )
}

internal fun galleryHeroProgress(progress: Float, returning: Boolean): Float {
    val value = progress.coerceIn(0f, 1f)
    return if (returning) 1f - FastOutSlowInEasing.transform(1f - value)
    else FastOutSlowInEasing.transform(value)
}

internal data class FlightGeometry(val frame: Rect, val clip: Rect, val image: Rect)

internal fun galleryGeometry(
    source: GalleryAnchor,
    full: Rect,
    image: Size,
    fraction: Float,
    covers: Boolean,
    fullImage: Rect = galleryImagePlane(full, image, crop = false),
    fullClip: Rect = full,
): FlightGeometry {
    val sourceImage = galleryImagePlane(source.bounds, image, crop = covers)
    return FlightGeometry(
        lerpRect(source.bounds, fullClip, fraction),
        lerpRect(source.visibleBounds, fullClip, fraction),
        lerpRect(sourceImage, fullImage, fraction),
    )
}

private fun lerpRect(start: Rect, end: Rect, fraction: Float) = when {
    fraction <= 0f -> start
    fraction >= 1f -> end
    else -> Rect(
        start.left + (end.left - start.left) * fraction,
        start.top + (end.top - start.top) * fraction,
        start.right + (end.right - start.right) * fraction,
        start.bottom + (end.bottom - start.bottom) * fraction,
    )
}

@Composable
internal fun GalleryFlight(
    source: GalleryAnchor,
    image: ImageBitmap,
    progress: Float,
    viewport: Size,
    sourceRadius: Float,
    sourceCovers: Boolean,
    returning: Boolean,
    closingPlane: GalleryPlane?,
) {
    val routeProgress = if (returning) 1f - progress else progress
    val t = galleryHeroProgress(routeProgress, returning)
    val fraction = if (returning) 1f - t else t
    val full = Rect(0f, 0f, viewport.width, viewport.height)
    val imageSize = Size(image.width.toFloat(), image.height.toFloat())
    val fullImage = closingPlane?.rect ?: galleryImagePlane(full, imageSize, crop = false)
    val fullClip = if (returning) {
        fullImage.intersect(full).intersect(closingPlane?.viewport ?: full)
            .takeUnless { it.isEmpty } ?: full
    } else full
    val (frame, clip, plane) = galleryGeometry(source, full, imageSize, fraction, sourceCovers, fullImage, fullClip)
    val radius = with(LocalDensity.current) { sourceRadius.dp.toPx() } * (1f - fraction)

    Canvas(Modifier.fillMaxSize()) {
        val path = Path().apply {
            addRoundRect(RoundRect(frame, CornerRadius(radius.coerceAtMost(min(frame.width, frame.height) / 2))))
        }
        clipRect(clip.left, clip.top, clip.right, clip.bottom) {
            clipPath(path) {
                translate(plane.left, plane.top) {
                    scale(plane.width / image.width, plane.height / image.height, Offset.Zero) {
                        drawImage(image)
                    }
                }
            }
        }
    }
}

// Same 400 logical px/s threshold and 120 logical px travel as ExtendedImage 8.3.1.
internal fun galleryInertia(velocity: Offset, density: Float): Offset {
    val magnitude = velocity.getDistance()
    return if (density > 0f && magnitude.isFinite() && magnitude >= 400f * density)
        velocity / magnitude * (120f * density)
    else Offset.Zero
}
