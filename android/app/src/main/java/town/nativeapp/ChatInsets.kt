package town.nativeapp

import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.ime
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.layout.layout

/** Consume the navigation bar's space continuously, using the IME's actual animation. */
@Composable
internal fun Modifier.collapseWithKeyboard(): Modifier {
    val ime = WindowInsets.ime
    return clipToBounds().layout { measurable, constraints ->
        val child = measurable.measure(constraints)
        val remaining = (child.height - ime.getBottom(this)).coerceAtLeast(0)
        layout(child.width, remaining) { child.placeRelative(0, 0) }
    }
}
