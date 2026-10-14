package town.nativeapp
import androidx.compose.material3.*
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
// desktop/renderer/app/styles.css, light and dark tokens.
fun clientColors(dark:Boolean):ColorScheme {
    val bg=Color(if(dark)0xff212121 else 0xffffffff)
    val surface=Color(if(dark)0xff292929 else 0xfff7f7f6)
    val text=Color(if(dark)0xffececec else 0xff242424)
    val secondary=Color(if(dark)0xffadadad else 0xff686868)
    val accent=Color(if(dark)0xffececec else 0xff292929)
    val button=Color(if(dark)0xff242424 else 0xffffffff)
    val scheme=if(dark)darkColorScheme() else lightColorScheme()
    return scheme.copy(primary=accent,onPrimary=button,primaryContainer=surface,onPrimaryContainer=text,secondary=secondary,onSecondary=button,secondaryContainer=surface,onSecondaryContainer=text,tertiary=secondary,onTertiary=button,tertiaryContainer=surface,onTertiaryContainer=text,background=bg,onBackground=text,surface=bg,onSurface=text,surfaceVariant=surface,onSurfaceVariant=secondary,surfaceTint=Color.Transparent,outline=Color(if(dark)0xff858585 else 0xff8b8b89),outlineVariant=Color(if(dark)0xff333333 else 0xffe9e9e7),surfaceContainerLowest=bg,surfaceContainerLow=surface,surfaceContainer=surface,surfaceContainerHigh=surface,surfaceContainerHighest=surface,inverseSurface=text,inverseOnSurface=bg,inversePrimary=bg)
}

// Muse screenshot: blue sent bubble and neutral received bubble.
fun ColorScheme.chatBubble(user:Boolean):Color {
    val dark=background.luminance()<0.5f
    return Color(if(user){if(dark)0xff007aff else 0xff007aff}else{if(dark)0xff383838 else 0xffebebed})
}

fun ColorScheme.feedAction()=Color(if(background.luminance()<0.5f)0xff8abbff else 0xff1767c4)
fun ColorScheme.feedTint()=Color(if(background.luminance()<0.5f)0xff273b54 else 0xffeaf3ff)
fun ColorScheme.fireInk()=Color(if(background.luminance()<0.5f)0xffedba85 else 0xff9b562b)
fun ColorScheme.fireTint()=Color(if(background.luminance()<0.5f)0xff41352b else 0xfff7ecdf)
fun ColorScheme.socialCard(kind:String):Color {
    val dark=background.luminance()<0.5f
    return Color(when(kind){"mail"->if(dark)0xff25303e else 0xfff0f6ff;"bonfire"->if(dark)0xff352d26 else 0xfffbf1e5;else->if(dark)0xff302b27 else 0xfff7f3ee})
}
