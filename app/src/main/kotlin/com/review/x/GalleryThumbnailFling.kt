package com.review.x

import androidx.compose.animation.core.*
import androidx.compose.animation.rememberSplineBasedDecay
import androidx.compose.foundation.gestures.*
import androidx.compose.foundation.interaction.collectIsDraggedAsState
import androidx.compose.foundation.pager.PagerState
import androidx.compose.runtime.*
import kotlinx.coroutines.flow.*
import kotlin.math.*

@Composable
fun rememberGalleryThumbnailFling(pager: PagerState): TargetedFlingBehavior {
    val decay = rememberSplineBasedDecay<Float>()
    val dragged by pager.interactionSource.collectIsDraggedAsState()
    var direction by remember { mutableFloatStateOf(0f) }
    LaunchedEffect(dragged) {
        if (dragged) {
            direction = 0f
            var previous: Float? = null
            snapshotFlow { pager.currentPage + pager.currentPageOffsetFraction }.collect { position ->
                previous?.let { if (abs(position - it) > .001f) direction = (position - it).sign }
                previous = position
            }
        }
    }
    val motionDirection by rememberUpdatedState(direction)
    return remember(pager, decay) {
        object : TargetedFlingBehavior {
            override suspend fun ScrollScope.performFling(initialVelocity: Float, onRemainingDistanceUpdated: (Float) -> Unit): Float {
                val cell = (pager.layoutInfo.pageSize + pager.layoutInfo.pageSpacing).toFloat()
                if (cell <= 0f || pager.pageCount <= 0) return initialVelocity
                val position = (pager.currentPage + pager.currentPageOffsetFraction).coerceIn(0f, pager.pageCount - 1f)
                val projected = (position + decay.calculateTargetValue(0f, initialVelocity) / cell).coerceIn(0f, pager.pageCount - 1f)
                val motion = if (abs(initialVelocity) > 1f) initialVelocity.sign else motionDirection
                val target = when { motion > 0f -> ceil(projected); motion < 0f -> floor(projected); else -> projected.roundToInt().toFloat() }.coerceIn(0f, pager.pageCount - 1f)
                val distance = (target - position) * cell
                if (abs(distance) < .5f) return 0f
                val duration = (abs(distance) / abs(initialVelocity).coerceAtLeast(cell * 2f) * 2000f).roundToInt().coerceIn(180, 700)
                var consumed = 0f
                animate(0f, distance, animationSpec = tween(duration, easing = LinearOutSlowInEasing)) { value, _ ->
                    consumed += scrollBy(value - consumed)
                    onRemainingDistanceUpdated(distance - consumed)
                }
                return 0f
            }
        }
    }
}