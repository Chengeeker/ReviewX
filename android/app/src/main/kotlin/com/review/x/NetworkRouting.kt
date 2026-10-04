package com.review.x

import android.content.Context
import android.net.ConnectivityManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.ProxySelector
import java.net.SocketAddress
import java.net.URI

/** The video plugin uses Media3 DefaultHttpDataSource / HttpURLConnection. */
object NetworkRouting {
    private val systemSelector = ProxySelector.getDefault()
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
                            if (mode == "automatic") ProxySelector.setDefault(systemSelector)
                            else ProxySelector.setDefault(object : ProxySelector() {
                                override fun select(uri: URI): MutableList<Proxy> = mutableListOf(
                                    if (mode == "manual" && uri.scheme in listOf("https", "http"))
                                        Proxy(Proxy.Type.HTTP, InetSocketAddress.createUnresolved(host, port))
                                    else Proxy.NO_PROXY)
                                override fun connectFailed(uri: URI, address: SocketAddress, error: IOException) { /* No direct fallback. */ }
                            })
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
