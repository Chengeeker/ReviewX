package com.review.x

import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.util.Log
import android.webkit.WebView

internal object XLoginDiagnostics {
    private const val PREFS = "x_login_diagnostics"
    private const val EVENTS = "events"
    private const val STARTED_AT = "started_at"
    private const val MAX_EVENTS = 80
    private const val TAG = "ReviewXLogin"
    private val eventPattern = Regex("[a-z0-9._-]{1,56}")
    private val seenProtocolRequests = mutableSetOf<String>()

    @Synchronized
    fun begin(context: Context) {
        seenProtocolRequests.clear()
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs.edit().clear().putLong(STARTED_AT, SystemClock.elapsedRealtime()).apply()
        record(context, "login.begin")
        val webViewVersion = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WebView.getCurrentWebViewPackage()?.versionName
        } else null
        val safeVersion = webViewVersion.orEmpty()
            .take(48)
            .filter { it.isLetterOrDigit() || it in ".-_+" }
            .ifEmpty { "unknown" }
        record(context, "runtime", code = Build.VERSION.SDK_INT, version = safeVersion)
    }

    @Synchronized
    fun record(
        context: Context,
        event: String,
        target: String? = null,
        code: Int? = null,
        mainFrame: Boolean? = null,
        method: String? = null,
        version: String? = null,
    ) {
        if (!eventPattern.matches(event)) return
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val elapsed = (SystemClock.elapsedRealtime() - prefs.getLong(STARTED_AT, 0L)).coerceAtLeast(0L)
        val safeTarget = target?.takeIf { Regex("(x|twitter|google|apple|captcha|other)/(login|jetfuel|onboarding|robots|other)").matches(it) }
        val safeMethod = method?.takeIf { it in setOf("GET", "POST", "PUT", "DELETE", "OTHER") }
        if (event == "webview.protocol_request" &&
            !seenProtocolRequests.add("$safeTarget|$mainFrame|$safeMethod")) return
        val safeVersion = version?.take(48)?.filter { it.isLetterOrDigit() || it in ".-_+" }
        val line = buildString {
            append('+').append(elapsed).append("ms ").append(event)
            safeTarget?.let { append(" target=").append(it) }
            code?.let { append(" code=").append(it) }
            mainFrame?.let { append(if (it) " frame=main" else " frame=sub") }
            safeMethod?.let { append(" method=").append(it) }
            safeVersion?.takeIf(String::isNotEmpty)?.let { append(" version=").append(it) }
        }
        val lines = prefs.getString(EVENTS, "").orEmpty()
            .lineSequence().filter(String::isNotBlank).toList()
        val updated = (lines + line).takeLast(MAX_EVENTS).joinToString("\n")
        prefs.edit().putString(EVENTS, updated).apply()
        Log.i(TAG, line)
    }

    fun read(context: Context): String = context
        .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        .getString(EVENTS, "")
        .orEmpty()

    fun target(uri: Uri): String {
        val rawHost = uri.host?.lowercase().orEmpty()
        val host = when {
            isHost(rawHost, "x.com") -> "x"
            isHost(rawHost, "twitter.com") -> "twitter"
            isHost(rawHost, "google.com") || isHost(rawHost, "gstatic.com") ||
                isHost(rawHost, "googleusercontent.com") -> "google"
            isHost(rawHost, "apple.com") -> "apple"
            isHost(rawHost, "captcha-delivery.com") || isHost(rawHost, "recaptcha.net") -> "captcha"
            else -> "other"
        }
        val path = uri.path.orEmpty()
        val page = when {
            path == "/robots.txt" -> "robots"
            path.contains("/i/jf/") -> "jetfuel"
            path.contains("onboarding", ignoreCase = true) -> "onboarding"
            path == "/i/flow/login" || path.startsWith("/i/flow/login/") -> "login"
            else -> "other"
        }
        return "$host/$page"
    }

    fun isLoginProtocolRequest(uri: Uri): Boolean {
        val host = uri.host?.lowercase().orEmpty()
        return isHost(host, "x.com") || isHost(host, "twitter.com")
    }

    private fun isHost(host: String, domain: String): Boolean =
        host == domain || host.endsWith(".$domain")
}
