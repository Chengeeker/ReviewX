package com.review.x

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.*
import androidx.compose.material.ripple.RippleAlpha
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.foundation.layout.size
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import org.json.JSONObject

val LocalSettings = staticCompositionLocalOf { JSONObject() }
val LocalReading = staticCompositionLocalOf { AppSettings.validatedReading(JSONObject()) }
data class ChromeColors(val background: Color, val appBar: Color, val card: Color, val navigation: Color)
val LocalChrome = staticCompositionLocalOf { ChromeColors(Color.Unspecified, Color.Unspecified, Color.Unspecified, Color.Unspecified) }
val LocalDarkTheme = staticCompositionLocalOf { false }
val LocalFontDelta = staticCompositionLocalOf { 0 }
private val LocalIcons = staticCompositionLocalOf { JSONObject() }
private val iconFont = FontFamily(Font(R.font.material_icons))

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReviewTheme(settings: JSONObject, content: @Composable (Boolean) -> Unit) {
    val context = LocalContext.current
    val tokens = remember { JSONObject(context.assets.open("flutter_theme_tokens.json").bufferedReader().use { it.readText() }) }
    val icons = remember { JSONObject(context.assets.open("flutter_icons.json").bufferedReader().use { it.readText() }) }
    val dark = when (settings.optInt("theme_mode")) { 1 -> false; 2 -> true; else -> isSystemInDarkTheme() }
    val black = dark && settings.optBoolean("key_is_pure_black_dark")
    val key = (if (black) "black" else if (dark) "dark" else "light") + "_" + settings.optInt("key_theme_color_index").coerceIn(0,7)
    val token = tokens.getJSONObject(key); val colors = token.getJSONObject("colors")
    fun c(name: String) = Color(colors.getLong(name))
    var scheme = (if (dark) darkColorScheme() else lightColorScheme()).copy(
        primary=c("primary"), onPrimary=c("onPrimary"), primaryContainer=c("primaryContainer"), onPrimaryContainer=c("onPrimaryContainer"),
        secondary=c("secondary"), onSecondary=c("onSecondary"), secondaryContainer=c("secondaryContainer"), onSecondaryContainer=c("onSecondaryContainer"),
        tertiary=c("tertiary"), onTertiary=c("onTertiary"), tertiaryContainer=c("tertiaryContainer"), onTertiaryContainer=c("onTertiaryContainer"),
        background=c("background"), onBackground=c("onSurface"), surface=c("surface"), onSurface=c("onSurface"), surfaceVariant=c("surfaceVariant"), onSurfaceVariant=c("onSurfaceVariant"),
        error=c("error"), onError=c("onError"), errorContainer=c("errorContainer"), onErrorContainer=c("onErrorContainer"), outline=c("outline"), outlineVariant=c("outlineVariant"),
        inverseSurface=c("inverseSurface"), inverseOnSurface=c("inverseOnSurface"), inversePrimary=c("inversePrimary"), scrim=c("scrim"), surfaceTint=c("primary"),
        surfaceBright=c("surfaceBright"), surfaceDim=c("surfaceDim"), surfaceContainer=c("surfaceContainer"), surfaceContainerLow=c("surfaceContainerLow"),
        surfaceContainerLowest=c("surfaceContainerLowest"), surfaceContainerHigh=c("surfaceContainerHigh"), surfaceContainerHighest=c("surfaceContainerHighest"))
    if (settings.optBoolean("use_dynamic_color") && Build.VERSION.SDK_INT >= 31) scheme = if (dark) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
    if (black) scheme = scheme.copy(surface=Color.Black,surfaceContainer=Color(0xFF121212),surfaceContainerHigh=Color(0xFF181818),surfaceContainerHighest=Color(0xFF222222))
    val config = LocalConfiguration.current
    val delta = if (settings.optBoolean("custom_font_weight")) settings.optInt("font_weight_delta") else if (Build.VERSION.SDK_INT >= 31) config.fontWeightAdjustment.takeUnless { it == Int.MAX_VALUE } ?: 0 else 0
    fun style(name: String): TextStyle {
        val s = token.getJSONObject("typography").getJSONObject(name)
        val size = s.getDouble("size").toFloat()
        return TextStyle(platformStyle=androidx.compose.ui.text.PlatformTextStyle(includeFontPadding=false),lineHeightStyle=androidx.compose.ui.text.style.LineHeightStyle(androidx.compose.ui.text.style.LineHeightStyle.Alignment.Center,androidx.compose.ui.text.style.LineHeightStyle.Trim.None),fontSize=size.sp,lineHeight=(size*s.getDouble("height")).toFloat().sp,letterSpacing=0.sp,
            fontWeight=FontWeight((s.getInt("weight") + kotlin.math.round(delta / 100f).toInt()*100).coerceIn(100,900)))
    }
    val typography = Typography(displayLarge=style("displayLarge"),displayMedium=style("displayMedium"),displaySmall=style("displaySmall"),
        headlineLarge=style("headlineLarge"),headlineMedium=style("headlineMedium"),headlineSmall=style("headlineSmall"),
        titleLarge=style("titleLarge"),titleMedium=style("titleMedium"),titleSmall=style("titleSmall").copy(color=scheme.onSurfaceVariant),
        bodyLarge=style("bodyLarge"),bodyMedium=style("bodyMedium"),bodySmall=style("bodySmall").copy(color=scheme.onSurfaceVariant),
        labelLarge=style("labelLarge"),labelMedium=style("labelMedium"),labelSmall=style("labelSmall"))
    val reading = AppSettings.validatedReading(runCatching { JSONObject(settings.str("reading_settings", "{}")) }.getOrDefault(JSONObject()))
    val density = LocalDensity.current
    val appScale=reading.optDouble("appTextScale",1.0).toFloat()
    val scaledDensity=remember(density,appScale) { object:Density by density {
        override val fontScale=density.fontScale*appScale
        override fun TextUnit.toDp():Dp=with(density) { (value*appScale).sp.toDp() }
        override fun Dp.toSp():TextUnit { val value=this;return (with(density) { value.toSp() }.value/appScale).sp }
    } }
    val chrome = ChromeColors(if (dark) c("background") else scheme.surface, if (dark) c("appBar") else scheme.surface, if (dark) c("card") else scheme.surfaceContainerLowest, if (dark) c("navigationBar") else scheme.surfaceContainer)
    val feedback = androidx.compose.ui.platform.LocalHapticFeedback.current
    CompositionLocalProvider(LocalSettings provides settings, LocalDarkTheme provides dark, LocalReading provides reading, LocalFontDelta provides delta, LocalChrome provides chrome,
        androidx.compose.ui.platform.LocalHapticFeedback provides if (settings.optBoolean("haptics", true)) feedback else SilentHapticFeedback,
        LocalIcons provides icons, LocalDensity provides scaledDensity) {
        MaterialTheme(colorScheme=scheme, typography=typography) {
            CompositionLocalProvider(LocalContentColor provides scheme.onSurface, LocalRippleConfiguration provides RippleConfiguration(rippleAlpha=RippleAlpha(0f,0.12f,0.08f,0f))) { ProvideTextStyle(typography.bodyMedium) { content(dark) } }
        }
    }
}

@Composable
fun Glyph(name: String, description: String? = null, size: Int = 24, color: Color = LocalContentColor.current, modifier: Modifier = Modifier) {
    val icons = LocalIcons.current
    val code = icons.optInt(name, icons.optInt("info_outline_rounded", 0xe88e))
    val textSize=with(LocalDensity.current) { size.dp.toSp() }
    Text(String(Character.toChars(code)), modifier.size(size.dp).clearAndSetSemantics { if (description != null) contentDescription=description },
        style=TextStyle(fontFamily=iconFont,fontWeight=FontWeight.Normal,fontStyle=androidx.compose.ui.text.font.FontStyle.Normal,fontSynthesis=androidx.compose.ui.text.font.FontSynthesis.None,platformStyle=androidx.compose.ui.text.PlatformTextStyle(includeFontPadding=false),fontSize=textSize,lineHeight=textSize,color=color))
}
