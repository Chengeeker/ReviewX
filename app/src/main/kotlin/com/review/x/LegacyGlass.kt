package com.review.x

import android.graphics.Bitmap
import android.opengl.EGL14.*
import android.opengl.GLES30.*
import android.opengl.GLUtils
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlinx.coroutines.asCoroutineDispatcher

/** GLES 3 uses the same reference optics before RuntimeShader is available. Thread confined. */
internal class LegacyGlass(fragment:String,basic:String,frost:String):AutoCloseable {
    private val display=eglGetDisplay(EGL_DEFAULT_DISPLAY)
    private var context=EGL_NO_CONTEXT
    private var surface=EGL_NO_SURFACE
    private val config:android.opengl.EGLConfig
    private var optics=0
    private var galleryOptics=0
    private var frostOptics=0
    private var blur=0
    private val textures=IntArray(3)
    private val framebuffer=IntArray(1)
    private var width=0;private var height=0
    private var pixels=ByteBuffer.allocateDirect(4).order(ByteOrder.nativeOrder())
    init {
      try {
        check(display!=EGL_NO_DISPLAY && eglInitialize(display,IntArray(2),0,IntArray(2),0))
        val configurations=arrayOfNulls<android.opengl.EGLConfig>(1);val count=IntArray(1)
        check(eglChooseConfig(display,intArrayOf(EGL_RENDERABLE_TYPE,0x40,EGL_SURFACE_TYPE,EGL_PBUFFER_BIT,EGL_RED_SIZE,8,EGL_GREEN_SIZE,8,EGL_BLUE_SIZE,8,EGL_ALPHA_SIZE,8,EGL_NONE),0,configurations,0,1,count,0)&&count[0]>0)
        config=requireNotNull(configurations[0]);context=eglCreateContext(display,config,EGL_NO_CONTEXT,intArrayOf(EGL_CONTEXT_CLIENT_VERSION,3,EGL_NONE),0)
        check(context!=EGL_NO_CONTEXT)
        surface=eglCreatePbufferSurface(display,config,intArrayOf(EGL_WIDTH,1,EGL_HEIGHT,1,EGL_NONE),0)
        check(eglMakeCurrent(display,surface,surface,context))
        optics=program(fragment)
        galleryOptics=program(basic)
        frostOptics=program(frost)
        blur=program("""#version 300 es
            precision highp float;
            uniform sampler2D image;
            uniform vec2 size;
            uniform vec2 direction;
            uniform float sigma;
            out vec4 result;
            void main() {
                vec2 uv=gl_FragCoord.xy/size;
                vec4 sum=vec4(0.0);float weights=0.0;
                for(int i=-48;i<=48;i++) {
                    float x=float(i);
                    if(abs(x)>ceil(3.0*sigma))continue;
                    float weight=exp(-x*x/(2.0*max(sigma*sigma,0.01)));
                    sum+=texture(image,uv+direction*x/size)*weight;weights+=weight;
                }
                result=sum/weights;
            }
        """.trimIndent())
        glGenTextures(3,textures,0);glGenFramebuffers(1,framebuffer,0)
        textures.forEach {glBindTexture(GL_TEXTURE_2D,it);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_S,GL_CLAMP_TO_EDGE);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_T,GL_CLAMP_TO_EDGE)}
      }catch(e:Exception){close();throw e}
    }
    private fun program(fragment:String):Int {
        fun shader(type:Int,source:String):Int {
            val value=glCreateShader(type);glShaderSource(value,source);glCompileShader(value);val result=IntArray(1);glGetShaderiv(value,GL_COMPILE_STATUS,result,0)
            check(result[0]!=0) {"Glass shader compilation failed: "+glGetShaderInfoLog(value)};return value
        }
        val vertex=shader(GL_VERTEX_SHADER,"""#version 300 es
            void main(){vec2 p=vec2(float((gl_VertexID<<1)&2),float(gl_VertexID&2));gl_Position=vec4(p*2.0-1.0,0.0,1.0);}
        """.trimIndent())
        val pixel=shader(GL_FRAGMENT_SHADER,fragment);val value=glCreateProgram();glAttachShader(value,vertex);glAttachShader(value,pixel);glLinkProgram(value)
        glDeleteShader(vertex);glDeleteShader(pixel);val result=IntArray(1);glGetProgramiv(value,GL_LINK_STATUS,result,0)
        check(result[0]!=0) {"Glass program link failed: "+glGetProgramInfoLog(value)};return value
    }
    fun render(input:Bitmap,style:GlassStyle,dpr:Float,padding:Float=0f,reference:androidx.compose.ui.unit.IntSize=androidx.compose.ui.unit.IntSize(input.width,input.height)):Bitmap {
        require(input.width>0 && input.height>0 && input.width.toLong()*input.height<=4_194_304)
        if(width!=input.width || height!=input.height) {
            width=input.width;height=input.height
            eglMakeCurrent(display,EGL_NO_SURFACE,EGL_NO_SURFACE,context);eglDestroySurface(display,surface)
            surface=eglCreatePbufferSurface(display,config,intArrayOf(EGL_WIDTH,width,EGL_HEIGHT,height,EGL_NONE),0)
            check(eglMakeCurrent(display,surface,surface,context));pixels=ByteBuffer.allocateDirect(width*height*4).order(ByteOrder.nativeOrder())
            textures.drop(1).forEach {glBindTexture(GL_TEXTURE_2D,it);glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA,width,height,0,GL_RGBA,GL_UNSIGNED_BYTE,null)}
        }
        glViewport(0,0,width,height);glDisable(GL_BLEND);glActiveTexture(GL_TEXTURE0);glBindTexture(GL_TEXTURE_2D,textures[0])
        val cpu=if(android.os.Build.VERSION.SDK_INT>=26 && input.config==Bitmap.Config.HARDWARE)requireNotNull(input.copy(Bitmap.Config.ARGB_8888,false))else input
        GLUtils.texImage2D(GL_TEXTURE_2D,0,cpu,0);if(cpu!==input)cpu.recycle()
        var source=textures[0]
        if(style.blur>0) {
            glUseProgram(blur);glUniform1i(glGetUniformLocation(blur,"image"),0);glUniform2f(glGetUniformLocation(blur,"size"),width.toFloat(),height.toFloat());glUniform1f(glGetUniformLocation(blur,"sigma"),style.blur*dpr)
            for(pass in 0..1) {
                glBindFramebuffer(GL_FRAMEBUFFER,framebuffer[0]);glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,textures[pass+1],0)
                check(glCheckFramebufferStatus(GL_FRAMEBUFFER)==GL_FRAMEBUFFER_COMPLETE)
                glBindTexture(GL_TEXTURE_2D,source);glUniform2f(glGetUniformLocation(blur,"direction"),if(pass==0)1f else 0f,if(pass==0)0f else 1f);glDrawArrays(GL_TRIANGLES,0,3);source=textures[pass+1]
            }
        }
        val selected=if(style.frosted)frostOptics else if(style.basicGallery)galleryOptics else optics
        glBindFramebuffer(GL_FRAMEBUFFER,0);glUseProgram(selected);glBindTexture(GL_TEXTURE_2D,source);glUniform1i(glGetUniformLocation(selected,"uBackgroundTexture"),0)
        style.uniforms(width,height,dpr,padding,reference).forEach {(name,value)->val location=glGetUniformLocation(selected,name);when(value.size){1->glUniform1fv(location,1,value,0);2->glUniform2fv(location,1,value,0);3->glUniform3fv(location,1,value,0);4->glUniform4fv(location,1,value,0)}}
        glDrawArrays(GL_TRIANGLES,0,3);pixels.clear();glReadPixels(0,0,width,height,GL_RGBA,GL_UNSIGNED_BYTE,pixels)
        check(glGetError()==GL_NO_ERROR) {"Glass render failed"}
        val colors=IntArray(width*height)
        for(y in 0 until height)for(x in 0 until width){val offset=((height-1-y)*width+x)*4;colors[y*width+x]=((pixels.get(offset+3).toInt() and 255) shl 24) or ((pixels.get(offset).toInt() and 255) shl 16) or ((pixels.get(offset+1).toInt() and 255) shl 8) or (pixels.get(offset+2).toInt() and 255)}
        return Bitmap.createBitmap(colors,width,height,Bitmap.Config.ARGB_8888)
    }
    override fun close() {
        if(display==EGL_NO_DISPLAY)return
        if(context!=EGL_NO_CONTEXT) {
        glDeleteTextures(3,textures,0);glDeleteFramebuffers(1,framebuffer,0);glDeleteProgram(optics);glDeleteProgram(galleryOptics);glDeleteProgram(frostOptics);glDeleteProgram(blur)
        eglMakeCurrent(display,EGL_NO_SURFACE,EGL_NO_SURFACE,EGL_NO_CONTEXT);eglDestroySurface(display,surface);eglDestroyContext(display,context)
        }
        eglTerminate(display);eglReleaseThread()
    }
}

internal object LegacyGlassEngine {
    val dispatcher=java.util.concurrent.Executors.newSingleThreadExecutor {r->Thread(r,"ReviewX-glass").apply {isDaemon=true}}.asCoroutineDispatcher()
    private var users=0
    private var renderer:LegacyGlass?=null
    fun acquire(context:android.content.Context):LegacyGlass {
        if(renderer==null) {
            fun read(name:String)=context.assets.open("glass/$name.frag").bufferedReader().use {it.readText()}
            renderer=LegacyGlass(read("premium"),read("gallery"),read("frost"))
        }
        users++;return requireNotNull(renderer)
    }
    fun release() {if(--users==0){renderer?.close();renderer=null}}
}
