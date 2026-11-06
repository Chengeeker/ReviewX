package com.review.x

import androidx.compose.foundation.*
import androidx.compose.foundation.interaction.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.*
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.unit.*

/** Flutter's retained Material 3 year2023 slider uses a round thumb and 4 dp track. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable fun OriginalSlider(value:Float,onChange:(Float)->Unit,range:ClosedFloatingPointRange<Float>,divisions:Int,onFinished:()->Unit,label:String?=null) {
    val colors=MaterialTheme.colorScheme
    val source=remember {MutableInteractionSource()}
    val dragged by source.collectIsDraggedAsState();val pressed by source.collectIsPressedAsState()
    val rtl=LocalLayoutDirection.current==LayoutDirection.Rtl
    Slider(value,onChange,modifier=Modifier.fillMaxWidth().padding(horizontal=14.dp),valueRange=range,steps=divisions-1,onValueChangeFinished=onFinished,interactionSource=source,
        thumb={
            Box(Modifier.size(20.dp).shadow(if(pressed||dragged)6.dp else 1.dp,CircleShape).background(colors.primary,CircleShape),contentAlignment=Alignment.Center) {
                if(label!=null&&(pressed||dragged))Surface(Modifier.wrapContentSize(unbounded=true).offset(y=(-36).dp),shape=CircleShape,color=colors.primary,contentColor=colors.onPrimary) {Text(label,Modifier.padding(horizontal=12.dp,vertical=8.dp),style=MaterialTheme.typography.labelMedium,maxLines=1)}
            }
        },track={state->
            Canvas(Modifier.fillMaxWidth().height(6.dp)) {
                val fraction=((state.value-range.start)/(range.endInclusive-range.start)).coerceIn(0f,1f)
                val start=if(rtl)size.width else 0f;val end=if(rtl)0f else size.width;val selected=start+(end-start)*fraction;val y=size.height/2
                drawLine(colors.surfaceContainerHighest,Offset(start,y),Offset(end,y),4.dp.toPx(),StrokeCap.Round)
                drawLine(colors.primary,Offset(start,y),Offset(selected,y),6.dp.toPx(),StrokeCap.Round)
                if(divisions>0&&size.width/divisions>=3.dp.toPx())for(index in 0..divisions) {
                    val t=index.toFloat()/divisions
                    drawCircle((if(t<=fraction)colors.onPrimary else colors.onSurfaceVariant).copy(alpha=.38f),1.dp.toPx(),Offset(start+(end-start)*t,y))
                }
            }
        })
}
