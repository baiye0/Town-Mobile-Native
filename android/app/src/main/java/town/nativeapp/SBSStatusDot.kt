package town.nativeapp

import androidx.compose.animation.core.*
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.unit.dp

@Composable fun SBSStatusDot(enabled: Boolean, active: Boolean) {
    val pulse = if (active) {
        val transition = rememberInfiniteTransition(label = "SBS 活动")
        val opacity by transition.animateFloat(.45f, 1f, infiniteRepeatable(tween(800), RepeatMode.Reverse), label = "SBS 状态点")
        opacity
    } else 1f
    val color = if (enabled || active) Color(if (MaterialTheme.colorScheme.background.luminance() < .5f) 0xff7fc797 else 0xff36935c) else MaterialTheme.colorScheme.onSurfaceVariant
    Canvas(Modifier.size(14.dp)) {
        val radius = 5.dp.toPx()
        if (enabled || active) drawCircle(color, radius, alpha = pulse)
        else drawCircle(color, radius - 1.dp.toPx(), style = Stroke(2.dp.toPx()))
    }
}
