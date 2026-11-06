package com.review.x

import androidx.compose.animation.core.*
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.progressSemantics

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.background
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.layout.FirstBaseline
import androidx.compose.ui.layout.LastBaseline
import androidx.compose.ui.layout.AlignmentLine
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.layout
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.*
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.Dialog
import kotlin.math.roundToInt

@Composable internal fun flutterWeight(weight:Int)=FontWeight((weight+(LocalFontDelta.current/100f).roundToInt()*100).coerceIn(100,900))
@Composable internal fun flutterTileTitle()=MaterialTheme.typography.bodyMedium.copy(fontSize=15.sp,lineHeight=20.25.sp,fontWeight=flutterWeight(600),color=MaterialTheme.colorScheme.onSurface)
@Composable internal fun flutterTileSubtitle()=MaterialTheme.typography.bodyMedium.copy(fontSize=12.5.sp,lineHeight=17.5.sp,fontWeight=flutterWeight(400),color=MaterialTheme.colorScheme.onSurfaceVariant)

// Android protects natural font extents outside a short line height; Flutter uses the specified line box.
internal fun Modifier.flutterLineHeight(height:TextUnit)=layout {measurable,constraints->
    val child=measurable.measure(constraints)
    val first=child[FirstBaseline];val last=child[LastBaseline]
    if(first==AlignmentLine.Unspecified||last==AlignmentLine.Unspecified||height==TextUnit.Unspecified)layout(child.width,child.height){child.placeRelative(0,0)}
    else {
        val boxHeight=constraints.constrainHeight(last-first+height.roundToPx())
        val offset=(boxHeight-child.height)/2
        layout(child.width,boxHeight,mapOf(FirstBaseline to first+offset,LastBaseline to last+offset)){child.placeRelative(0,offset)}
    }
}

@Composable internal fun FlutterTileText(modifier:Modifier=Modifier,targetHeight:Dp,titleStyle:TextStyle,subtitleStyle:TextStyle,headline:@Composable ()->Unit,supporting:(@Composable ()->Unit)?=null) {
    Layout(modifier=modifier,content={
        Box(Modifier.flutterLineHeight(titleStyle.lineHeight)){ProvideTextStyle(titleStyle){headline()}}
        if(supporting!=null)Box(Modifier.flutterLineHeight(subtitleStyle.lineHeight)){ProvideTextStyle(subtitleStyle){supporting()}}
    }){measurables,constraints->
        val loose=constraints.copy(minWidth=0,minHeight=0)
        val title=measurables[0].measure(loose);val subtitle=measurables.getOrNull(1)?.measure(loose)
        val padding=8.dp.roundToPx();val target=targetHeight.roundToPx()
        val titleY:Int;var subtitleY=0;val height:Int
        if(subtitle==null){height=maxOf(target,title.height+2*padding);titleY=(height-title.height)/2}
        else {
            val top=32.dp.roundToPx()-(title[FirstBaseline].takeUnless{it==AlignmentLine.Unspecified}?:title.height)
            val bottom=52.dp.roundToPx()-(subtitle[FirstBaseline].takeUnless{it==AlignmentLine.Unspecified}?:subtitle.height)
            val overlap=maxOf(top+title.height-bottom,0)/2
            if(top-overlap<padding||bottom+overlap+subtitle.height+padding>target){titleY=padding;subtitleY=padding+title.height;height=2*padding+title.height+subtitle.height}
            else{titleY=top-overlap;subtitleY=bottom+overlap;height=target}
        }
        layout(constraints.constrainWidth(maxOf(title.width,subtitle?.width?:0)),constraints.constrainHeight(height)){title.placeRelative(0,titleY);subtitle?.placeRelative(0,subtitleY)}
    }
}

@Composable fun FlutterAlertDialog(onDismissRequest:()->Unit,confirmButton:@Composable ()->Unit,
    modifier:Modifier=Modifier,dismissButton:(@Composable ()->Unit)?=null,title:(@Composable ()->Unit)?=null,
    text:(@Composable ()->Unit)?=null,shape:Shape=RoundedCornerShape(28.dp),
    contentPadding:PaddingValues=PaddingValues(start=24.dp,top=if(title==null)24.dp else 16.dp,end=24.dp,bottom=24.dp),centerActions:Boolean=false) {
    val scheme=MaterialTheme.colorScheme
    val titleStyle=TextStyle(fontSize=18.sp,fontWeight=flutterWeight(700),color=scheme.onSurface)
    val contentStyle=TextStyle(fontSize=14.sp,fontWeight=flutterWeight(400),color=scheme.onSurfaceVariant)
    Dialog(onDismissRequest,properties=DialogProperties(usePlatformDefaultWidth=false)) {
        Box(Modifier.fillMaxWidth(),contentAlignment=androidx.compose.ui.Alignment.Center) {
        val maximumWidth=minOf(560.dp,LocalConfiguration.current.screenWidthDp.dp-80.dp)
        Surface(modifier.widthIn(min=minOf(280.dp,maximumWidth),max=maximumWidth).width(IntrinsicSize.Max).heightIn(max=LocalConfiguration.current.screenHeightDp.dp-48.dp),shape=shape,color=scheme.surfaceContainerHigh,contentColor=scheme.onSurface,tonalElevation=0.dp) {
            Column {
                if(title!=null)Box(Modifier.padding(start=24.dp,top=24.dp,end=24.dp,bottom=if(text==null)24.dp else 0.dp)){ProvideTextStyle(titleStyle){title()}}
                if(text!=null)Box(Modifier.weight(1f,fill=false).padding(contentPadding)){ProvideTextStyle(contentStyle){text()}}
                FlowRow(Modifier.fillMaxWidth().padding(start=24.dp,end=24.dp,bottom=24.dp),horizontalArrangement=if(centerActions)Arrangement.spacedBy(8.dp,androidx.compose.ui.Alignment.CenterHorizontally)else Arrangement.spacedBy(8.dp,androidx.compose.ui.Alignment.End),verticalArrangement=Arrangement.spacedBy(8.dp)){dismissButton?.invoke();confirmButton()}
            }
        }
        }
    }
}

@Composable internal fun FlutterRadio(selected:Boolean) {
    val position by animateFloatAsState(if(selected)1f else 0f,tween(200,easing=if(selected)CubicBezierEasing(.42f,0f,1f,1f)else CubicBezierEasing(0f,0f,.58f,1f)),label="radio")
    val colors=MaterialTheme.colorScheme
    val color=androidx.compose.ui.graphics.lerp(colors.onSurfaceVariant,colors.primary,position)
    Canvas(Modifier.size(40.dp)){
        drawCircle(color,radius=8.dp.toPx(),style=androidx.compose.ui.graphics.drawscope.Stroke(2.dp.toPx()))
        if(position>0f)drawCircle(color,radius=4.5.dp.toPx()*position)
    }
}

@Composable fun FlutterDivider(modifier:Modifier=Modifier,height:Dp=16.dp,color:Color=Color.Unspecified) {
    val line=if(color!=Color.Unspecified)color else if(LocalDarkTheme.current&&LocalSettings.current.optBoolean("key_is_pure_black_dark"))Color.White.copy(alpha=.1f)else MaterialTheme.colorScheme.outlineVariant.copy(alpha=if(LocalDarkTheme.current).2f else .3f)
    Box(modifier.height(height),contentAlignment=androidx.compose.ui.Alignment.Center){HorizontalDivider(thickness=.5.dp,color=line)}
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable fun FlutterBottomSheet(onDismissRequest:()->Unit,shape:Shape=RoundedCornerShape(topStart=28.dp,topEnd=28.dp),containerColor:Color=Color.Unspecified,contentColor:Color=MaterialTheme.colorScheme.onSurface,content:@Composable ColumnScope.()->Unit) {
    val scheme=MaterialTheme.colorScheme
    val background=if(containerColor!=Color.Unspecified)containerColor else if(LocalDarkTheme.current&&LocalSettings.current.optBoolean("key_is_pure_black_dark"))Color(0xFF141414)else scheme.surfaceContainerLow
    ModalBottomSheet(onDismissRequest=onDismissRequest,shape=shape,containerColor=background,contentColor=contentColor,tonalElevation=0.dp,
        dragHandle={BottomSheetDefaults.DragHandle(width=38.dp,height=4.5.dp,color=scheme.onSurfaceVariant.copy(alpha=.4f))},content=content)
}

@Composable fun FlutterListItem(headlineContent:@Composable ()->Unit,modifier:Modifier=Modifier,supportingContent:(@Composable ()->Unit)?=null,leadingContent:(@Composable ()->Unit)?=null,trailingContent:(@Composable ()->Unit)?=null) {
    Row(modifier.fillMaxWidth().heightIn(min=if(supportingContent==null)62.dp else 78.dp).padding(horizontal=16.dp,vertical=3.dp),verticalAlignment=androidx.compose.ui.Alignment.CenterVertically) {
        if(leadingContent!=null){Box(Modifier.widthIn(min=24.dp)){CompositionLocalProvider(LocalContentColor provides MaterialTheme.colorScheme.onSurfaceVariant){leadingContent()}};Spacer(Modifier.width(16.dp))}
        FlutterTileText(Modifier.weight(1f),if(supportingContent==null)56.dp else 72.dp,flutterTileTitle(),flutterTileSubtitle(),headlineContent,supportingContent)
        if(trailingContent!=null){Spacer(Modifier.width(16.dp));CompositionLocalProvider(LocalContentColor provides MaterialTheme.colorScheme.onSurfaceVariant){trailingContent()}}
    }
}
@Composable fun FlutterCard(modifier:Modifier=Modifier,onClick:(()->Unit)?=null,content:@Composable ColumnScope.()->Unit) {
    val border=if(LocalDarkTheme.current&&LocalSettings.current.optBoolean("key_is_pure_black_dark"))Color.White.copy(alpha=.12f)else MaterialTheme.colorScheme.outlineVariant.copy(alpha=if(LocalDarkTheme.current).2f else .25f)
    Card(modifier=modifier,shape=RoundedCornerShape(22.dp),colors=CardDefaults.cardColors(containerColor=LocalChrome.current.card),elevation=CardDefaults.cardElevation(0.dp),border=androidx.compose.foundation.BorderStroke(.8.dp,border)){
        Column(Modifier.fillMaxWidth().then(if(onClick==null)Modifier else Modifier.hapticClickable(onClick=onClick)),content=content)
    }
}

@Composable fun FlutterOutlinedButton(onClick:()->Unit,modifier:Modifier=Modifier,enabled:Boolean=true,content:@Composable RowScope.()->Unit) {
    val scheme=MaterialTheme.colorScheme
    OutlinedButton(hapticClick(onClick),modifier,enabled,colors=ButtonDefaults.outlinedButtonColors(contentColor=scheme.primary),border=androidx.compose.foundation.BorderStroke(1.dp,if(enabled)scheme.outline else scheme.onSurface.copy(alpha=.12f)),contentPadding=PaddingValues(start=16.dp,end=24.dp),content=content)
}
@Composable fun FlutterColorChip(title:String,color:Color,selected:Boolean,onClick:()->Unit) {
    Box(Modifier.height(48.dp),contentAlignment=androidx.compose.ui.Alignment.Center) {
        CompositionLocalProvider(LocalMinimumInteractiveComponentSize provides 0.dp){
            FilterChip(selected,hapticClick(onClick),modifier=Modifier.height(38.dp),label={Text(title,Modifier.padding(horizontal=1.dp))},colors=FilterChipDefaults.filterChipColors(containerColor=MaterialTheme.colorScheme.surface),leadingIcon={
                Box(Modifier.size(20.dp).background(color,androidx.compose.foundation.shape.CircleShape),contentAlignment=androidx.compose.ui.Alignment.Center){if(selected){Box(Modifier.matchParentSize().background(Color(0x60191919),androidx.compose.foundation.shape.CircleShape));Glyph("check",size=15,color=MaterialTheme.colorScheme.onSecondaryContainer)}}
            })
        }
    }
}

@Composable internal fun FlutterLabelChip(title:String) {
    Box(Modifier.height(48.dp),contentAlignment=androidx.compose.ui.Alignment.Center){
        Surface(shape=RoundedCornerShape(8.dp),color=MaterialTheme.colorScheme.surface,border=androidx.compose.foundation.BorderStroke(1.dp,MaterialTheme.colorScheme.outlineVariant)){
            Text(title,Modifier.padding(horizontal=(17f-4f*(androidx.compose.ui.platform.LocalDensity.current.fontScale-1f).coerceIn(0f,1f)).dp,vertical=9.dp),style=MaterialTheme.typography.labelLarge,color=MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

// Flutter's retained Material indicator uses a 36dp path with a centered square stroke.
@Composable internal fun FlutterProgress(modifier:Modifier=Modifier,color:Color=MaterialTheme.colorScheme.primary,strokeWidth:Dp=4.dp) {
    val animation=rememberInfiniteTransition(label="Flutter progress")
    val path by animation.animateFloat(0f,1f,infiniteRepeatable(tween(1333,easing=LinearEasing)),label="arc")
    val rotation by animation.animateFloat(0f,1f,infiniteRepeatable(tween(2222,easing=LinearEasing)),label="rotation")
    Canvas(modifier.size(36.dp).progressSemantics()){
        val head=FastOutSlowInEasing.transform((path*2).coerceIn(0f,1f))
        val tail=FastOutSlowInEasing.transform((path*2-1).coerceIn(0f,1f))
        drawArc(color,startAngle=-90f+tail*270f+rotation*360f+path*90f,sweepAngle=((head-tail)*270f).coerceAtLeast(.05729578f),useCenter=false,style=androidx.compose.ui.graphics.drawscope.Stroke(strokeWidth.toPx(),cap=androidx.compose.ui.graphics.StrokeCap.Square))
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable internal fun FlutterDenseField(value:String,onValueChange:(String)->Unit,label:String,icon:String,enabled:Boolean,placeholder:String?=null,password:Boolean=false,error:String?=null) {
    val interactions=remember{androidx.compose.foundation.interaction.MutableInteractionSource()}
    val scheme=MaterialTheme.colorScheme;val colors=OutlinedTextFieldDefaults.colors()
    val transformation=if(password)androidx.compose.ui.text.input.PasswordVisualTransformation()else androidx.compose.ui.text.input.VisualTransformation.None
    androidx.compose.foundation.text.BasicTextField(value,onValueChange,modifier=Modifier.fillMaxWidth().defaultMinSize(minHeight=48.dp),enabled=enabled,singleLine=true,
        textStyle=MaterialTheme.typography.bodyLarge.copy(color=if(enabled)scheme.onSurface else scheme.onSurface.copy(alpha=.38f)),interactionSource=interactions,cursorBrush=androidx.compose.ui.graphics.SolidColor(scheme.primary),visualTransformation=transformation,
        keyboardOptions=if(password)androidx.compose.foundation.text.KeyboardOptions(keyboardType=androidx.compose.ui.text.input.KeyboardType.Password,autoCorrectEnabled=false)else androidx.compose.foundation.text.KeyboardOptions.Default,
        decorationBox={inner->OutlinedTextFieldDefaults.DecorationBox(value=value,innerTextField=inner,enabled=enabled,singleLine=true,visualTransformation=transformation,interactionSource=interactions,isError=error!=null,label={Text(label)},placeholder=if(placeholder!=null)({Text(placeholder)})else null,leadingIcon={Glyph(icon,size=18)},supportingText=if(error!=null)({Text(error)})else null,colors=colors,contentPadding=PaddingValues(horizontal=16.dp,vertical=12.dp),container={OutlinedTextFieldDefaults.Container(enabled,error!=null,interactions,colors=colors,shape=RoundedCornerShape(4.dp))})})
}

@Composable fun FlutterTextButton(onClick:()->Unit,modifier:Modifier=Modifier,enabled:Boolean=true,colors:ButtonColors=ButtonDefaults.textButtonColors(),contentPadding:PaddingValues=PaddingValues(horizontal=12.dp,vertical=8.dp),content:@Composable RowScope.()->Unit) {
    androidx.compose.material3.TextButton(hapticClick(onClick),modifier.defaultMinSize(minWidth=64.dp),enabled,colors=colors,contentPadding=contentPadding,content=content)
}
