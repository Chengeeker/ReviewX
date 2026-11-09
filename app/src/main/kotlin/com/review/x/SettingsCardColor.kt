package com.review.x

import androidx.compose.material3.ColorScheme
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.graphics.luminance

internal fun ColorScheme.settingsCardColor(pageColor: Color = background): Color {
    val pageBackground = if (pageColor == Color.Unspecified) background else pageColor
    val page = pageBackground.luminance() + .05f
    val card = surfaceContainerHigh.luminance() + .05f
    // Some wallpaper palettes leave the high container too close to the actual page color.
    return if (maxOf(page, card) >= minOf(page, card) * 1.12f) surfaceContainerHigh
    else onSurface.copy(alpha = .10f).compositeOver(pageBackground)
}
