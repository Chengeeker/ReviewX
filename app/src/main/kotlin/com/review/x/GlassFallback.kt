package com.review.x

import android.graphics.Bitmap
import kotlin.math.*

// The original glass library falls back to blur and tint when shaders are unavailable.
internal fun glassFallback(input:Bitmap,sigma:Float):Bitmap {
    val divisor=max(4,ceil(sigma/4f).toInt())
    val reduced=Bitmap.createScaledBitmap(input,max(1,input.width/divisor),max(1,input.height/divisor),true)
    val software=if(android.os.Build.VERSION.SDK_INT>=26&&reduced.config==Bitmap.Config.HARDWARE)requireNotNull(reduced.copy(Bitmap.Config.ARGB_8888,false))else reduced
    try {
        val pixels=IntArray(software.width*software.height)
        software.getPixels(pixels,0,software.width,0,0,software.width,software.height)
        return Bitmap.createBitmap(gaussianBlur(pixels,software.width,software.height,sigma/divisor),software.width,software.height,Bitmap.Config.ARGB_8888)
    }finally {
        if(software!==reduced)software.recycle()
        if(reduced!==input)reduced.recycle()
    }
}

internal fun gaussianBlur(pixels:IntArray,width:Int,height:Int,sigma:Float):IntArray {
    require(width>0&&height>0&&width.toLong()*height==pixels.size.toLong())
    require(sigma.isFinite()&&sigma>=0f&&sigma<=4f)
    if(sigma<=.01f)return pixels.copyOf()
    val radius=ceil(3*sigma).toInt()
    val weights=FloatArray(radius*2+1){exp(-((it-radius)*(it-radius)).toFloat()/(2*sigma*sigma))}
    val total=weights.sum();weights.indices.forEach{weights[it]/=total}
    var source=pixels
    repeat(2){pass->
        val output=IntArray(pixels.size)
        for(y in 0 until height)for(x in 0 until width) {
            var a=0f;var r=0f;var g=0f;var b=0f
            for(step in -radius..radius) {
                val color=source[if(pass==0)y*width+(x+step).coerceIn(0,width-1)else (y+step).coerceIn(0,height-1)*width+x]
                val weight=weights[step+radius]
                a+=(color ushr 24)*weight;r+=((color ushr 16)and 255)*weight;g+=((color ushr 8)and 255)*weight;b+=(color and 255)*weight
            }
            output[y*width+x]=(a.roundToInt().coerceIn(0,255) shl 24)or(r.roundToInt().coerceIn(0,255) shl 16)or(g.roundToInt().coerceIn(0,255) shl 8)or b.roundToInt().coerceIn(0,255)
        }
        source=output
    }
    return source
}
