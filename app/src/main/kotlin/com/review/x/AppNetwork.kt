package com.review.x

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.webkit.ProxyConfig
import androidx.webkit.ProxyController
import androidx.webkit.WebViewFeature
import okhttp3.OkHttpClient
import okhttp3.Request
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.ProxySelector
import java.net.SocketAddress
import java.net.URI
import java.util.concurrent.TimeUnit
import java.util.concurrent.Executor

data class NetworkConfig(val mode: String = "automatic", val host: String = "", val port: Int = 0) {
    fun validate() {
        require(mode in listOf("automatic", "direct", "manual")) { "网络模式无效" }
        if (mode == "manual") { require(host.matches(Regex("[A-Za-z0-9][A-Za-z0-9._-]{0,252}"))) { "请输入代理主机名或 IPv4 地址，不含协议、端口或路径" }; require(port in 1..65535) { "端口应为 1–65535" } }
    }
    fun json() = JSONObject().put("mode", mode).put("host", host).put("port", port)
    companion object { fun parse(raw: JSONObject) = NetworkConfig(raw.str("mode", "automatic"), raw.str("host"), raw.optInt("port")).also { it.validate() } }
}
object AppNetwork {
    val http by lazy { client() }
    private val webViewReady = kotlinx.coroutines.CompletableDeferred<Unit>()
    suspend fun awaitWebView(context:Context) { initialize(context); webViewReady.await() }
    private val system = ProxySelector.getDefault()
    @Volatile private var initialized = false
    @Volatile var warning: String? = null
        private set
    @Synchronized fun initialize(context: Context) {
        if (initialized) return
        val settings=AppSettings(context)
        settings.importFlutter(context)
        val config = NetworkConfig.parse(JSONObject(settings.string("network_config", "{}")))
        if (config.mode != "automatic") ProxySelector.setDefault(object : ProxySelector() {
            override fun select(uri: URI): MutableList<Proxy> = mutableListOf(proxy(config))
            override fun connectFailed(uri: URI, sa: SocketAddress, ioe: java.io.IOException) = Unit
        })
        initialized = true
        Handler(Looper.getMainLooper()).post { configureWebView(config) }
    }
    private fun proxy(config: NetworkConfig) = if (config.mode == "manual") Proxy(Proxy.Type.HTTP, InetSocketAddress.createUnresolved(config.host, config.port)) else Proxy.NO_PROXY
    fun client(config: NetworkConfig? = null): OkHttpClient = OkHttpClient.Builder().connectTimeout(15, TimeUnit.SECONDS).readTimeout(20, TimeUnit.SECONDS).callTimeout(35, TimeUnit.SECONDS)
        .followRedirects(false).followSslRedirects(false).retryOnConnectionFailure(false).apply {
            if (config?.mode == "automatic" && system != null) proxySelector(system)
            else if (config != null) proxy(proxy(config))
        }.build()
    private fun configureWebView(config: NetworkConfig) {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE)) {
            if (config.mode != "automatic") warning = "当前 Android System WebView 不支持应用代理，网页登录仍使用系统网络路由。"
            webViewReady.complete(Unit)
            return
        }
        val executor = Executor { Handler(Looper.getMainLooper()).post(it) }
        try {
            val controller = ProxyController.getInstance()
            if (config.mode == "automatic") controller.clearProxyOverride(executor) { webViewReady.complete(Unit) }
            else controller.setProxyOverride(if (config.mode == "direct") ProxyConfig.Builder().addDirect().build() else ProxyConfig.Builder().addProxyRule("http://${config.host}:${config.port}").build(), executor) { webViewReady.complete(Unit) }
        } catch (_: Exception) { warning = "网页登录代理配置失败，请检查 Android System WebView。"; webViewReady.complete(Unit) }
    }
    suspend fun test(config: NetworkConfig): String = withContext(Dispatchers.IO) {
        config.validate()
        val start = System.nanoTime()
        client(config).newCall(Request.Builder().url("https://x.com/robots.txt").header("User-Agent", ReaderRepository.USER_AGENT).build()).execute().use {
            if (it.code !in 200..399) throw ApiFailure("连接失败（${it.code}），请检查代理设置")
            "连接成功，用时 ${(System.nanoTime() - start) / 1_000_000} ms"
        }
    }
}
