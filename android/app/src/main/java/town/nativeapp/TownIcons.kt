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
fun destinationIcon(id: String): ImageVector = when(id) {
    "chat" -> chat
    "firesides", "contacts" -> people
    "mail" -> mail
    "bonfire" -> flame
    "seeds" -> leaf
    "embers" -> AppIcons.Book
    "scrolls" -> AppIcons.Scroll
    "announcements" -> AppIcons.Announcement
    "home" -> AppIcons.Home
    else -> grid
}
private val down = symbol("Down", "M12,4 L12,20 M5,13 L12,20 L19,13")
val Icons.Outlined.ArrowDownward get() = down

private val mic = symbol("Mic", "M9,5 C9,1 15,1 15,5 L15,11 C15,15 9,15 9,11 Z M5,10 L5,11 C5,20 19,20 19,11 L19,10 M12,18 L12,22 M8,22 L16,22")
val Icons.Outlined.Mic get() = mic

object AppIcons {
    val Settings = symbol("Settings", "M9,3 L15,3 L16,6 L19,7 L22,11 L20,13 L20,17 L16,20 L13,19 L10,21 L6,19 L6,16 L3,14 L3,9 L6,8 L7,5 Z M16,12 A4,4 0,1 1,8,12 A4,4 0,1 1,16,12")
    val Chevron = symbol("Chevron", "M9,5 L16,12 L9,19")
    val List = symbol("QuestionIndex", "M8,5 L21,5 M8,12 L21,12 M8,19 L21,19 M3,5 L3.1,5 M3,12 L3.1,12 M3,19 L3.1,19")
    val Quote = symbol("Quote", "M4,6 L10,6 L10,13 C10,17 7,19 4,19 M4,6 L4,12 L10,12 M14,6 L20,6 L20,13 C20,17 17,19 14,19 M14,6 L14,12 L20,12")
    val Model = symbol("Model", "M7,7 L17,7 L17,17 L7,17 Z M10,10 L14,10 L14,14 L10,14 Z M9,3 L9,7 M15,3 L15,7 M9,17 L9,21 M15,17 L15,21 M3,9 L7,9 M3,15 L7,15 M17,9 L21,9 M17,15 L21,15")
    val Tune = symbol("Tune", "M3,6 L7,6 M11,6 L21,6 M7,3 L7,9 M3,12 L15,12 M19,12 L21,12 M15,9 L15,15 M3,18 L7,18 M11,18 L21,18 M7,15 L7,21")
    val Bell = symbol("Bell", "M5,16 L5,10 C5,1 19,1 19,10 L19,16 L21,18 L3,18 Z M9,21 L15,21")
    val Palette = symbol("Appearance", "M12,3 A9,9 0,1 0,12,21 C16,21 12,17 15,16 L18,16 C23,16 23,3 12,3 M7,8 L7.1,8 M12,6 L12.1,6 M17,8 L17.1,8 M6,13 L6.1,13")
    val Sun = symbol("Light", "M16,12 A4,4 0,1 1,8,12 A4,4 0,1 1,16,12 M12,2 L12,4 M12,20 L12,22 M2,12 L4,12 M20,12 L22,12 M5,5 L6,6 M18,18 L19,19 M5,19 L6,18 M18,6 L19,5")
    val Moon = symbol("Dark", "M20,15 A9,9 0,1 1,9,3 A9,9 0,0 0,20,15 Z")
    val System = symbol("System", "M5,3 L19,3 L19,21 L5,21 Z M10,18 L14,18")
    val Update = symbol("Update", "M20,8 A9,9 0,1 0,21,14 M20,3 L20,8 L15,8 M12,7 L12,17 M8,13 L12,17 L16,13")
    val Type = symbol("ReadingSize", "M3,18 L8,5 L13,18 M5,13 L11,13 M16,18 L19,10 L22,18 M17,15 L21,15")
    val Book = symbol("Book", "M12,5 C9,3 5,3 2,4 L2,20 C5,19 9,19 12,21 C15,19 19,19 22,20 L22,4 C19,3 15,3 12,5 Z M12,5 L12,21")
    val Scroll = symbol("Scroll", "M7,3 L19,3 C22,3 22,7 19,7 L17,7 M7,3 C3,3 3,7 7,7 L7,17 M7,17 L3,17 C3,22 10,22 10,17 L17,17 L17,6 C17,4 18,3 19,3 M10,10 L14,10 M10,13 L14,13")
    val Announcement = symbol("Announcement", "M3,10 L8,10 L20,4 L20,20 L8,14 L3,14 Z M8,14 L10,21 L6,21 L4,14")
    val Home = symbol("Home", "M3,10 L12,3 L21,10 M5,9 L5,21 L19,21 L19,9 M9,21 L9,14 L15,14 L15,21")
}
