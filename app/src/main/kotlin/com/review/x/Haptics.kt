package com.review.x

import androidx.compose.foundation.clickable
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedback
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback

internal object SilentHapticFeedback : HapticFeedback {
    override fun performHapticFeedback(hapticFeedbackType: HapticFeedbackType) = Unit
}

@Composable
internal fun hapticClick(onClick: () -> Unit): () -> Unit {
    val feedback = LocalHapticFeedback.current
    return {
        feedback.performHapticFeedback(HapticFeedbackType.VirtualKey)
        onClick()
    }
}

@Composable
internal fun Modifier.hapticClickable(
    enabled: Boolean = true,
    onClickLabel: String? = null,
    onClick: () -> Unit,
): Modifier = clickable(enabled = enabled, onClickLabel = onClickLabel, onClick = hapticClick(onClick))
