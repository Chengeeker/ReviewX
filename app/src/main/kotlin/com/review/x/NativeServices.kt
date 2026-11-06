package com.review.x

import android.content.*
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.media.MediaScannerConnection
import androidx.browser.customtabs.CustomTabsIntent
import androidx.core.content.FileProvider
import coil.Coil
import kotlinx.coroutines.*
import okhttp3.Request
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.json.JSONArray
import java.io.File
import java.util.concurrent.TimeUnit

object NativeServices {
    fun open(context:Context,url:String) {
        require(safeLink(url)) { "不支持的链接" }
        CustomTabsIntent.Builder().setShowTitle(true).build().launchUrl(context,Uri.parse(url))
    }
    fun share(context:Context,text:String,title:String="分享") {
        context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT,text),title))
    }
    fun copy(context:Context,text:String) { context.getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText("ReviewX",text)) }
    fun folder(settings:AppSettings,media:Media,author:String,me:String)=when(settings.reading().str(if(media.video)"videoStorageFolder" else "imageStorageFolder","default")) { "me"->me;"author"->author;else->"" }.replace(Regex("[^A-Za-z0-9_-]"),"_").take(80)
    private val mediaHttp by lazy { AppNetwork.http.newBuilder().readTimeout(2,TimeUnit.MINUTES).callTimeout(5,TimeUnit.MINUTES).build() }
    suspend fun download(context:Context,media:Media):Pair<File,String> = withContext(Dispatchers.IO) {
        val url=if(media.video) media.variants.firstOrNull()?.url ?: throw ApiFailure("视频地址不可用") else media.original
        require(safeMediaUrl(url)); val uri=url.toHttpUrl(); val format=uri.queryParameter("format")
        val ext=when { media.video->"mp4"; format=="png" || uri.encodedPath.endsWith(".png")->"png";format=="webp" || uri.encodedPath.endsWith(".webp")->"webp";else->"jpg" }
        val mime=if(media.video)"video/mp4" else if(ext=="jpg")"image/jpeg" else "image/$ext"
        val dir=File(context.cacheDir,"shared-media").apply { mkdirs() }
        dir.listFiles()?.filter { System.currentTimeMillis()-it.lastModified()>86400000 }?.forEach { it.delete() }
        val file=File.createTempFile("Review_X_${System.currentTimeMillis()}",".$ext",dir)
        val call=mediaHttp.newCall(Request.Builder().url(url).header("User-Agent",ReaderRepository.USER_AGENT).header("Referer","https://x.com/").build())
        try {
            call.execute().use { response ->
                require(response.isSuccessful) { "媒体下载失败" }; val body=response.body ?: error("媒体为空")
                require(body.contentLength()<=512L*1024*1024) { "媒体文件超过 512 MiB" }
                body.byteStream().use { input -> file.outputStream().use { out ->
                    val buffer=ByteArray(64*1024); var total=0L
                    while(true) { currentCoroutineContext().ensureActive();val n=input.read(buffer);if(n<0)break;total+=n;require(total<=512L*1024*1024) { "媒体文件超过 512 MiB" };out.write(buffer,0,n) }
                } }
            }
            file to mime
        } catch(error:Exception) { call.cancel();file.delete();throw error }
    }
    suspend fun save(context:Context,media:Media,folder:String) = withContext(Dispatchers.IO) {
        require(folder.matches(Regex("[A-Za-z0-9_-]{0,80}")))
        val (file,mime)=download(context,media)
        try {
            val video=media.video;val base=if(video)Environment.DIRECTORY_MOVIES else Environment.DIRECTORY_PICTURES
            val relative="$base/ReviewX"+if(folder.isBlank())"" else "/$folder"
            val name="Review_X_${System.currentTimeMillis()*1000}.${file.extension}"
            if(Build.VERSION.SDK_INT>=29) {
                val resolver=context.contentResolver
                val collection=if(video)MediaStore.Video.Media.EXTERNAL_CONTENT_URI else MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                val uri=resolver.insert(collection,ContentValues().apply { put(MediaStore.MediaColumns.DISPLAY_NAME,name);put(MediaStore.MediaColumns.MIME_TYPE,mime);put(MediaStore.MediaColumns.RELATIVE_PATH,relative);put(MediaStore.MediaColumns.IS_PENDING,1) }) ?: error("相册创建失败")
                try { resolver.openOutputStream(uri)?.use { out->file.inputStream().use { it.copyTo(out) } } ?: error("相册写入失败");check(resolver.update(uri,ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING,0) },null,null)>0) }
                catch(error:Exception) { resolver.delete(uri,null,null);throw error }
            } else {
                val directory=File(Environment.getExternalStoragePublicDirectory(base),"ReviewX"+if(folder.isBlank())"" else "/$folder")
                check(directory.exists() || directory.mkdirs());val destination=File(directory,name)
                try { file.copyTo(destination,false) } catch(error:Exception) { destination.delete();throw error }
                MediaScannerConnection.scanFile(context,arrayOf(destination.path),arrayOf(mime),null)
            }
        } finally { file.delete() }
    }
    suspend fun shareMedia(context:Context,media:Media) {
        val (file,mime)=download(context,media)
        val uri=FileProvider.getUriForFile(context,"com.review.x.compose.files",file)
        withContext(Dispatchers.Main) { context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType(mime).putExtra(Intent.EXTRA_STREAM,uri).apply { clipData=ClipData.newRawUri("媒体",uri);addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION) },"分享媒体")) }
    }
    private fun roots(context:Context)=listOf(context.cacheDir,context.codeCacheDir)+context.externalCacheDirs.filterNotNull()
    fun cache(context:Context):Map<String,Long> {
        val sizes=mutableMapOf("total" to 0L,"images" to 0L,"network" to 0L,"system" to 0L)
        roots(context).forEach { root -> if(root.exists()) root.walkTopDown().onEnter { it.canonicalPath.startsWith(root.canonicalPath+File.separator)||it==root }.filter { it.isFile }.forEach { file ->
            val path=file.path.lowercase();val size=file.length();val key=when { "image" in path || file.extension.lowercase() in listOf("png","jpg","jpeg","webp","gif","mp4","m4v","mov","webm","mkv")->"images";listOf("http","webview","dio").any { it in path } || path.endsWith(".tmp")->"network";else->"system" }
            sizes["total"]=sizes.getValue("total")+size;sizes[key]=sizes.getValue(key)+size
        } };return sizes
    }
    @OptIn(coil.annotation.ExperimentalCoilApi::class)
    suspend fun clearCache(context:Context):Long=withContext(Dispatchers.IO) {
        val size=cache(context).getValue("total")
        val loader = Coil.imageLoader(context)
        val diskCache = loader.diskCache
        val imageDirectory = diskCache?.directory?.toFile()?.canonicalFile
        loader.memoryCache?.clear()
        diskCache?.clear()
        roots(context).forEach { root -> root.listFiles()?.forEach { child ->
            val canonical = child.canonicalFile
            require(canonical.path.startsWith(root.canonicalPath + File.separator))
            if (canonical != imageDirectory) check(child.deleteRecursively() || !child.exists())
        } }
        size
    }
    private val translations=android.util.LruCache<String,String>(200)
    fun cachedTranslation(text:String):String?=translations.get(text)
    fun needsTranslation(text:String)=text.trim().length>=3 && !Regex("[\\u4e00-\\u9fa5]").containsMatchIn(text) && Regex("[a-zA-Z\\u3040-\\u30ff\\uac00-\\ud7af]").containsMatchIn(text)
    suspend fun translate(text:String):String=withContext(Dispatchers.IO) {
        translations.get(text)?.let { return@withContext it }
        val url="https://translate.googleapis.com/translate_a/single".toHttpUrl().newBuilder().addQueryParameter("client","gtx").addQueryParameter("sl","auto").addQueryParameter("tl","zh-CN").addQueryParameter("dt","t").addQueryParameter("q",text).build()
        AppNetwork.http.newCall(Request.Builder().url(url).build()).execute().use {
            require(it.isSuccessful) { "翻译暂时不可用" };val source=it.body?.source() ?: error("翻译为空");source.request(1024*1024+1);require(source.buffer.size<=1024*1024)
            val parts=JSONArray(source.readUtf8()).getJSONArray(0);val translated=(0 until parts.length()).joinToString("") { i->parts.getJSONArray(i).optString(0) }
            require(translated.isNotBlank()) { "翻译为空" };translations.put(text,translated);translated
        }
    }
}
