package com.review.x

import android.content.Context
import android.net.ConnectivityManager
import android.os.Handler
import android.os.Looper
import androidx.webkit.ProxyConfig
import androidx.webkit.ProxyController
import androidx.webkit.WebViewFeature
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.ProxySelector
import java.net.SocketAddress
import java.net.URI
import java.util.concurrent.Executor

/** The video plugin uses Media3 DefaultHttpDataSource / HttpURLConnection. */
object NetworkRouting {
    private val systemSelector = ProxySelector.getDefault()
    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile private var webViewMode = "automatic"
    @Volatile private var webViewProxySupported = true

    fun webViewProxyWarning(): String? =
        if (webViewMode != "automatic" && !webViewProxySupported) {
            "当前 Android System WebView 不支持应用代理，网页登录仍使用系统网络路由。"
        } else null

    fun register(engine: FlutterEngine, context: Context) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "com.review.x/network")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "systemProxy" -> {
                        val proxy = (context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager).defaultProxy
                        result.success(mapOf("host" to (proxy?.host ?: ""), "port" to (proxy?.port ?: 0),
                            "exclusions" to (proxy?.exclusionList?.toList() ?: emptyList<String>())))
                    }
                    "configure" -> {
                        val mode = call.argument<String>("mode") ?: "automatic"
                        val host = call.argument<String>("host") ?: ""
                        val port = call.argument<Int>("port") ?: 0
                        if (mode !in listOf("automatic", "direct", "manual") ||
                            (mode == "manual" && (!Regex("^[a-zA-Z0-9][a-zA-Z0-9._-]{0,252}$").matches(host) || port !in 1..65535))) {
                            result.error("INVALID", "代理配置无效", null)
                        } else {
                            webViewMode = mode
                            if (mode == "automatic") ProxySelector.setDefault(systemSelector)
                            else ProxySelector.setDefault(object : ProxySelector() {
                                override fun select(uri: URI): MutableList<Proxy> = mutableListOf(
                                    if (mode == "manual" && uri.scheme in listOf("https", "http"))
                                        Proxy(Proxy.Type.HTTP, InetSocketAddress.createUnresolved(host, port))
                                    else Proxy.NO_PROXY)
                                override fun connectFailed(uri: URI, address: SocketAddress, error: IOException) { /* No direct fallback. */ }
                            })
                            configureWebViewProxy(mode, host, port) { result.success(null) }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun configureWebViewProxy(mode: String, host: String, port: Int, done: () -> Unit) {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE)) {
            webViewProxySupported = false
            done()
            return
        }

        val callbackExecutor = Executor { command ->
            if (Looper.myLooper() == Looper.getMainLooper()) command.run()
            else mainHandler.post(command)
        }
        val completed = Runnable {
            webViewProxySupported = true
            done()
        }
        try {
            val controller = ProxyController.getInstance()
            when (mode) {
                "automatic" -> controller.clearProxyOverride(callbackExecutor, completed)
                "direct" -> controller.setProxyOverride(
                    ProxyConfig.Builder().addDirect().build(), callbackExecutor, completed)
                "manual" -> controller.setProxyOverride(
                    ProxyConfig.Builder().addProxyRule("http://$host:$port").build(),
                    callbackExecutor,
                    completed)
            }
        } catch (_: Exception) {
            webViewProxySupported = false
            mainHandler.post { done() }
        }
    }
}
