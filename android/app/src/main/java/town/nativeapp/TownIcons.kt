package town.nativeapp

import androidx.compose.material.icons.Icons
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.unit.dp

// Keep only the small set of symbols the app needs; no full icon catalog in the APK.
private fun symbol(name: String, path: String): ImageVector = ImageVector.Builder(name, 24.dp, 24.dp, 24f, 24f)
    .addPath(PathParser().parsePathString(path).toNodes(), fill = null, stroke = SolidColor(Color.Black), strokeLineWidth = 1.7f, strokeLineCap = StrokeCap.Round, strokeLineJoin = StrokeJoin.Round).build()
private val spark = symbol("Spark", "M12,3 C13,9 15,11 21,12 C15,13 13,15 12,21 C11,15 9,13 3,12 C9,11 11,9 12,3 Z")
private val leaf = symbol("Leaf", "M20,4 C8,1 2,7 5,14 C8,21 20,20 20,4 Z M5,6 C8,11 12,15 21,20")
private val notes = symbol("Notes", "M4,5 L20,5 M4,10 L17,10 M4,15 L20,15 M4,20 L12,20")
private val northwest = symbol("NorthWest", "M18,18 L6,6 M6,15 L6,6 L15,6")
private val stop = symbol("Stop", "M6,6 L18,6 L18,18 L6,18 Z")
private val link = symbol("Link", "M9,15 L15,9 M7,12 L5,14 C1,18 6,23 10,19 L12,17 M12,7 L14,5 C18,1 23,6 19,10 L17,12")
private val up = symbol("Up", "M12,20 L12,4 M5,11 L12,4 L19,11")
private val chat = symbol("Chat", "M4,4 L20,4 L20,17 L10,17 L4,21 Z")
private val trash = symbol("Delete", "M3,6 L21,6 M8,6 L8,3 L16,3 L16,6 M6,6 L7,21 L17,21 L18,6 M10,10 L10,17 M14,10 L14,17")
val Icons.Outlined.AutoAwesome get() = spark
val Icons.Outlined.Eco get() = leaf
val Icons.Outlined.Notes get() = notes
val Icons.Outlined.NorthWest get() = northwest
val Icons.Outlined.Stop get() = stop
val Icons.Outlined.Link get() = link
val Icons.Outlined.ArrowUpward get() = up
val Icons.Outlined.ChatBubbleOutline get() = chat
val Icons.Outlined.DeleteOutline get() = trash
private val people = symbol("People","M9,11 C5,11 5,3 9,3 C13,3 13,11 9,11 M2,21 C2,12 16,12 16,21 Z M17,3 C22,3 22,11 17,11 M18,14 C22,14 23,17 23,21")
private val mail = symbol("Mail","M3,5 L21,5 L21,19 L3,19 Z M3,5 L12,13 L21,5")
private val flame = symbol("Flame","M12,2 C19,9 23,15 18,20 C10,27 0,16 8,9 C7,14 11,15 12,2 Z")
private val grid = symbol("Grid","M3,3 L9,3 L9,9 L3,9 Z M15,3 L21,3 L21,9 L15,9 Z M3,15 L9,15 L9,21 L3,21 Z M15,15 L21,15 L21,21 L15,21 Z")
fun destinationIcon(id: String): ImageVector = when(id) {"chat"->chat;"firesides","contacts"->people;"mail"->mail;"bonfire"->flame;"seeds"->leaf;"scrolls","embers","announcements"->notes;else->grid}
private val down = symbol("Down", "M12,4 L12,20 M5,13 L12,20 L19,13")
val Icons.Outlined.ArrowDownward get() = down

private val mic = symbol("Mic", "M9,5 C9,1 15,1 15,5 L15,11 C15,15 9,15 9,11 Z M5,10 L5,11 C5,20 19,20 19,11 L19,10 M12,18 L12,22 M8,22 L16,22")
val Icons.Outlined.Mic get() = mic
