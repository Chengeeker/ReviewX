package com.review.x

import android.app.Activity
import android.app.AlertDialog
import android.app.Dialog
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.WindowManager
import android.webkit.CookieManager
import android.webkit.SafeBrowsingResponse
import android.webkit.SslErrorHandler
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebStorage
import android.webkit.WebView
import android.webkit.WebViewClient
import android.window.OnBackInvokedCallback
import android.window.OnBackInvokedDispatcher
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import androidx.webkit.WebSettingsCompat
import androidx.webkit.WebStorageCompat
import androidx.webkit.WebViewFeature
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

class XLoginActivity : Activity() {
    companion object {
        @Volatile var active: XLoginActivity? = null
        @Volatile var candidateValidator: ((Map<String, String>, (Boolean) -> Unit) -> Unit)? = null
        const val EXTRA_EXIT_REASON = "x_login_exit_reason"
        private const val POLL_INTERVAL_MS = 2_000L
        private const val RETRY_INTERVAL_MS = 60_000L
        private const val LOGIN_PAGE_URL = "https://x.com/i/flow/login"
        private const val MAX_RENDERER_RECOVERIES = 1
        private val SESSION_COOKIE_NAMES = setOf("auth_token", "ct0", "twid", "gt")
        private val COOKIE_URLS = listOf(
            "https://x.com", "https://www.x.com", "https://mobile.x.com",
            "https://twitter.com", "https://www.twitter.com", "https://mobile.twitter.com"
        )
        private val LOGIN_HOSTS = setOf(
            "x.com", "twitter.com", "google.com", "gstatic.com", "googleusercontent.com",
            "apple.com", "captcha-delivery.com", "recaptcha.net"
        )

        fun validateCandidate(cookies: Map<String, String>, result: MethodChannel.Result) {
            val activity = active
            if (activity == null) {
                result.success(false)
            } else {
                activity.runOnUiThread { activity.validateCandidate(cookies, result) }
            }
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private lateinit var shell: LinearLayout
    private lateinit var webContainer: FrameLayout
    private lateinit var status: TextView
    private lateinit var progress: ProgressBar
    private var webView: WebView? = null
    private var popupWebView: WebView? = null
    private var popupDialog: Dialog? = null
    private var closingPopup = false
    private var closing = false
    private var validating = false
    private var latestFingerprint: String? = null
    private var rejectedFingerprint: String? = null
    private var rejectedAt = 0L
    private var siteDataCleared = false
    private var lastLoginUrl = LOGIN_PAGE_URL
    private var rendererRecoveryCount = 0
    private var backConfirmation: AlertDialog? = null
    private var backInvokedCallback: Any? = null

    private val pollCandidate = object : Runnable {
        override fun run() {
            if (closing) return
            readCandidate()?.let(::requestValidation)
            handler.postDelayed(this, POLL_INTERVAL_MS)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        XLoginDiagnostics.record(this, "activity.created", code = if (savedInstanceState == null) 0 else 1)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val callback = OnBackInvokedCallback { handleSystemBack(1) }
            backInvokedCallback = callback
            onBackInvokedDispatcher.registerOnBackInvokedCallback(
                OnBackInvokedDispatcher.PRIORITY_DEFAULT, callback)
        }
        active = this
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
        buildShell()
        CookieManager.getInstance().setAcceptCookie(true)
        XLoginDiagnostics.record(this, "site_data.clear_started")
        status.text = "正在准备 X 登录页面…"
        clearLoginSiteData {
            if (!isFinishing) {
                siteDataCleared = true
                loadLoginPage()
                handler.postDelayed(pollCandidate, POLL_INTERVAL_MS)
            }
        }
    }

    override fun onStart() {
        super.onStart()
        XLoginDiagnostics.record(this, "activity.started")
    }

    override fun onResume() {
        super.onResume()
        XLoginDiagnostics.record(this, "activity.resumed")
    }

    override fun onPause() {
        XLoginDiagnostics.record(this, "activity.paused", code = if (isFinishing) 1 else 0)
        super.onPause()
    }

    override fun onStop() {
        XLoginDiagnostics.record(this, "activity.stopped", code = if (isFinishing) 1 else 0)
        super.onStop()
    }

    override fun onUserLeaveHint() {
        XLoginDiagnostics.record(this, "activity.user_leave_hint")
        super.onUserLeaveHint()
    }

    private fun buildShell() {
        shell = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.rgb(18, 18, 18))
            fitsSystemWindows = true
            setOnApplyWindowInsetsListener { v, insets ->
                val topInset = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    insets.getInsets(WindowInsets.Type.statusBars()).top
                } else {
                    @Suppress("DEPRECATION")
                    insets.systemWindowInsetTop
                }
                v.setPadding(0, topInset, 0, 0)
                insets
            }
        }
        status = TextView(this)
        progress = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply {
            max = 100
            visibility = View.GONE
        }
        shell.addView(progress, LinearLayout.LayoutParams(-1, dp(2)))
        webContainer = FrameLayout(this)
        shell.addView(webContainer, LinearLayout.LayoutParams(-1, 0, 1f))
        setContentView(shell)
    }

    private fun loadLoginPage(url: String = LOGIN_PAGE_URL) {
        siteDataCleared = false
        val view = createWebView(isPopup = false)
        webView = view
        webContainer.removeAllViews()
        webContainer.addView(view, FrameLayout.LayoutParams(-1, -1))
        lastLoginUrl = if (isAllowedLoginUrl(url)) url else LOGIN_PAGE_URL
        XLoginDiagnostics.record(this, "webview.load_requested", target = XLoginDiagnostics.target(Uri.parse(lastLoginUrl)))
        val routeWarning = NetworkRouting.webViewProxyWarning()
        val loginHint = "请在 X 页面完成登录和安全验证；ReviewX 会在保存前核验会话。"
        status.text = listOfNotNull(routeWarning, loginHint).joinToString("\n")
        view.loadUrl(lastLoginUrl)
    }

    private fun isAllowedLoginUrl(url: String): Boolean {
        val uri = Uri.parse(url)
        val host = uri.host?.lowercase() ?: return false
        return uri.scheme == "https" && LOGIN_HOSTS.any { host == it || host.endsWith(".$it") }
    }

    private fun createWebView(isPopup: Boolean): WebView {
        XLoginDiagnostics.record(this, if (isPopup) "webview.popup_created" else "webview.created")
        return WebView(this).apply {
        settings.javaScriptEnabled = true
        settings.domStorageEnabled = true
        settings.databaseEnabled = true
        settings.allowFileAccess = false
        settings.allowContentAccess = false
        settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
        settings.javaScriptCanOpenWindowsAutomatically = true
        settings.setSupportMultipleWindows(true)
        if (android.os.Build.VERSION.SDK_INT >= 26) settings.safeBrowsingEnabled = true
        try {
            if (WebViewFeature.isFeatureSupported(WebViewFeature.WEB_AUTHENTICATION)) {
                WebSettingsCompat.setWebAuthenticationSupport(
                    settings, WebSettingsCompat.WEB_AUTHENTICATION_SUPPORT_NONE)
                XLoginDiagnostics.record(this@XLoginActivity, "webview.webauthn_disabled")
            }
        } catch (_: Exception) {
        }
        CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)
        webViewClient = loginWebViewClient()
        webChromeClient = loginChromeClient(isPopup)
        }
    }

    private fun loginWebViewClient(): WebViewClient = object : WebViewClient() {
        override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
            val uri = request.url
            val allowed = isAllowedLoginUrl(uri.toString())
            XLoginDiagnostics.record(
                this@XLoginActivity, "webview.navigation",
                target = XLoginDiagnostics.target(uri), code = if (allowed) 1 else 0,
                mainFrame = request.isForMainFrame, method = request.method
            )
            if (!allowed) status.text = "已阻止离开 X 登录页面。"
            return !allowed
        }

        override fun onPageStarted(view: WebView, url: String?, favicon: android.graphics.Bitmap?) {
            XLoginDiagnostics.record(
                this@XLoginActivity,
                if (view === popupWebView) "webview.popup_page_started" else "webview.page_started",
                target = url?.let { XLoginDiagnostics.target(Uri.parse(it)) }, mainFrame = true
            )
            progress.visibility = View.VISIBLE
            if (view === webView && url != null && isAllowedLoginUrl(url)) lastLoginUrl = url
        }

        override fun onPageFinished(view: WebView, url: String?) {
            XLoginDiagnostics.record(
                this@XLoginActivity,
                if (view === popupWebView) "webview.popup_page_finished" else "webview.page_finished",
                target = url?.let { XLoginDiagnostics.target(Uri.parse(it)) }, mainFrame = true
            )
            progress.visibility = View.GONE
            if (view === webView && url != null && isAllowedLoginUrl(url)) lastLoginUrl = url
        }

        override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
            val uri = request.url
            val target = XLoginDiagnostics.target(uri)
            if (XLoginDiagnostics.isLoginProtocolRequest(uri) && !target.endsWith("/other")) {
                XLoginDiagnostics.record(
                    this@XLoginActivity, "webview.protocol_request", target = target,
                    mainFrame = request.isForMainFrame, method = request.method
                )
            }
            return null
        }

        override fun onReceivedError(
            view: WebView, request: WebResourceRequest, error: WebResourceError
        ) {
            if (request.isForMainFrame ||
                (XLoginDiagnostics.isLoginProtocolRequest(request.url) &&
                    !XLoginDiagnostics.target(request.url).endsWith("/other"))) {
                XLoginDiagnostics.record(
                    this@XLoginActivity, "webview.resource_error",
                    target = XLoginDiagnostics.target(request.url), code = error.errorCode,
                    mainFrame = request.isForMainFrame, method = request.method
                )
            }
            if (request.isForMainFrame && !closing) {
                progress.visibility = View.GONE
                val reason = when (error.errorCode) {
                    ERROR_HOST_LOOKUP -> "域名解析失败"
                    ERROR_CONNECT -> "连接失败"
                    ERROR_TIMEOUT -> "连接超时"
                    ERROR_PROXY_AUTHENTICATION -> "代理要求认证"
                    ERROR_FAILED_SSL_HANDSHAKE -> "TLS 握手失败"
                    else -> "网络请求失败"
                }
                status.text = "X 登录页网络请求失败（${error.errorCode}：$reason）。请检查应用代理或 VPN 后重载，也可导入 Cookie。"
            }
        }

        override fun onReceivedHttpError(
            view: WebView, request: WebResourceRequest, errorResponse: WebResourceResponse
        ) {
            if (request.isForMainFrame ||
                (XLoginDiagnostics.isLoginProtocolRequest(request.url) &&
                    !XLoginDiagnostics.target(request.url).endsWith("/other"))) {
                XLoginDiagnostics.record(
                    this@XLoginActivity, "webview.http_error",
                    target = XLoginDiagnostics.target(request.url), code = errorResponse.statusCode,
                    mainFrame = request.isForMainFrame, method = request.method
                )
            }
        }

        override fun onReceivedSslError(view: WebView, errorHandler: SslErrorHandler, error: android.net.http.SslError) {
            XLoginDiagnostics.record(
                this@XLoginActivity, "webview.ssl_error",
                target = XLoginDiagnostics.target(Uri.parse(error.url)), code = error.primaryError
            )
            errorHandler.cancel()
            if (!closing) status.text = "X 安全连接验证失败，请检查设备时间或网络。"
        }

        override fun onSafeBrowsingHit(
            view: WebView,
            request: WebResourceRequest,
            threatType: Int,
            callback: SafeBrowsingResponse
        ) {
            XLoginDiagnostics.record(
                this@XLoginActivity, "webview.safe_browsing_block",
                target = XLoginDiagnostics.target(request.url), code = threatType,
                mainFrame = request.isForMainFrame
            )
            callback.backToSafety(true)
            if (!closing) status.text = "安全浏览已阻止可疑页面。"
        }

        override fun onRenderProcessGone(view: WebView, detail: android.webkit.RenderProcessGoneDetail): Boolean {
            XLoginDiagnostics.record(
                this@XLoginActivity,
                if (view === popupWebView) "webview.popup_renderer_gone" else "webview.renderer_gone",
                code = if (detail.didCrash()) 1 else 0, mainFrame = view === webView
            )
            if (view === popupWebView) {
                closePopup()
                if (!closing) status.text = "辅助验证页面已关闭；可继续登录或重新载入。"
            } else if (view === webView) {
                val resumeUrl = view.url?.let { if (isAllowedLoginUrl(it)) it else lastLoginUrl } ?: lastLoginUrl
                webContainer.removeView(view)
                webView = null
                view.stopLoading()
                view.destroy()
                progress.visibility = View.GONE
                if (!closing && rendererRecoveryCount < MAX_RENDERER_RECOVERIES) {
                    rendererRecoveryCount++
                    XLoginDiagnostics.record(this@XLoginActivity, "webview.renderer_recovery_scheduled", code = rendererRecoveryCount)
                    status.text = "X 登录页面发生临时故障，正在恢复…"
                    handler.postDelayed({
                        if (!closing && webView == null) loadLoginPage(resumeUrl)
                    }, 500)
                } else if (!closing) {
                    status.text = "X 登录页面意外关闭，请点“重新载入”后重试。"
                }
            }
            return true
        }
    }

    private fun loginChromeClient(isPopup: Boolean): WebChromeClient = object : WebChromeClient() {
        override fun onProgressChanged(view: WebView, newProgress: Int) {
            progress.progress = newProgress
            progress.visibility = if (newProgress >= 100) View.GONE else View.VISIBLE
        }

        override fun onCreateWindow(
            view: WebView, isDialog: Boolean, isUserGesture: Boolean, resultMsg: android.os.Message
        ): Boolean {
            val refusal = when {
                isPopup -> 1
                !isUserGesture -> 2
                popupWebView != null -> 3
                closing -> 4
                else -> 0
            }
            XLoginDiagnostics.record(this@XLoginActivity, "webview.popup_request", code = refusal)
            if (refusal != 0) return false
            openPopup(resultMsg)
            return popupWebView != null
        }

        override fun onCloseWindow(window: WebView) {
            if (window === popupWebView) closePopup()
        }
    }

    private fun openPopup(resultMsg: android.os.Message) {
        XLoginDiagnostics.record(this, "webview.popup_opened")
        val child = createWebView(isPopup = true)
        popupWebView = child
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            addView(Button(this@XLoginActivity).apply {
                text = "关闭辅助登录"
                setOnClickListener { closePopup() }
            }, LinearLayout.LayoutParams(-1, dp(48)))
            addView(child, LinearLayout.LayoutParams(-1, 0, 1f))
        }
        val dialog = Dialog(this)
        popupDialog = dialog
        dialog.setTitle("X 辅助验证")
        dialog.setContentView(content)
        dialog.setOnDismissListener {
            if (!closingPopup && popupWebView === child) destroyPopupView(child)
        }
        dialog.show()
        dialog.window?.setLayout(-1, (resources.displayMetrics.heightPixels * 0.9).toInt())
        val transport = resultMsg.obj as? WebView.WebViewTransport ?: run {
            XLoginDiagnostics.record(this, "webview.popup_transport_missing")
            closePopup()
            return
        }
        transport.webView = child
        resultMsg.sendToTarget()
    }

    private fun closePopup() {
        val dialog = popupDialog
        closingPopup = true
        popupDialog = null
        val child = popupWebView
        if (dialog != null || child != null) XLoginDiagnostics.record(this, "webview.popup_closed")
        popupWebView = null
        if (dialog?.isShowing == true) dialog.dismiss()
        if (child != null) destroyPopupView(child)
        closingPopup = false
    }

    private fun destroyPopupView(view: WebView) {
        XLoginDiagnostics.record(this, "webview.popup_destroyed")
        if (popupWebView === view) popupWebView = null
        (view.parent as? ViewGroup)?.removeView(view)
        view.stopLoading()
        view.destroy()
    }

    private fun readCandidate(): Map<String, String>? {
        val raw = CookieManager.getInstance().getCookie("https://x.com") ?: return null
        val parsed = mutableMapOf<String, String>()
        raw.split(';').forEach { part ->
            val at = part.indexOf('=')
            if (at > 0) {
                val key = part.substring(0, at).trim()
                if (key in SESSION_COOKIE_NAMES) parsed[key] = part.substring(at + 1).trim()
            }
        }
        if (parsed["auth_token"].isNullOrEmpty() || parsed["ct0"].isNullOrEmpty()) return null
        return parsed
    }

    private fun requestValidation(cookies: Map<String, String>) {
        if (closing || validating) return
        val fingerprint = MessageDigest.getInstance("SHA-256")
            .digest(cookies.toSortedMap().entries.joinToString(";") { "${it.key}=${it.value}" }.toByteArray())
            .joinToString("") { "%02x".format(it) }
        val candidateChanged = fingerprint != latestFingerprint
        if (candidateChanged) {
            latestFingerprint = fingerprint
            rejectedFingerprint = null
            XLoginDiagnostics.record(this, "session.candidate_changed")
        }
        if (fingerprint == rejectedFingerprint &&
            SystemClock.elapsedRealtime() - rejectedAt < RETRY_INTERVAL_MS) return
        val validator = candidateValidator ?: run {
            if (candidateChanged) XLoginDiagnostics.record(this, "session.validator_missing")
            return
        }
        validating = true
        XLoginDiagnostics.record(this, "session.validation_started")
        status.text = "正在确认 X 账号…"
        validator(cookies) { accepted ->
            runOnUiThread {
                validating = false
                if (closing) return@runOnUiThread
                XLoginDiagnostics.record(this, "session.validation_result", code = if (accepted) 1 else 0)
                if (accepted) {
                    finishLogin()
                } else {
                    rejectedFingerprint = fingerprint
                    rejectedAt = SystemClock.elapsedRealtime()
                    status.text = "X 尚未确认此会话。请继续完成验证；仍失败时可重新载入或使用 Cookie 导入。"
                }
            }
        }
    }

    private fun validateCandidate(cookies: Map<String, String>, result: MethodChannel.Result) {
        if (closing || !validating) {
            result.success(false)
            return
        }
        val current = readCandidate()
        if (current == null || current["auth_token"] != cookies["auth_token"] || current["ct0"] != cookies["ct0"]) {
            validating = false
            result.success(false)
            return
        }
        result.success(true)
    }

    private fun finishLogin() {
        if (closing) return
        XLoginDiagnostics.record(this, "login.verified")
        closing = true
        handler.removeCallbacks(pollCandidate)
        closePopup()
        status.text = "登录已验证，正在清理临时网页登录数据…"
        clearLoginSiteData {
            siteDataCleared = true
            setResult(Activity.RESULT_OK, Intent()
                .putExtra("authenticated", true)
                .putExtra(EXTRA_EXIT_REASON, 1))
            finish()
        }
    }

    private fun cancelLogin(reason: Int) {
        if (closing) return
        XLoginDiagnostics.record(this, "login.cancelled", code = reason)
        closing = true
        handler.removeCallbacks(pollCandidate)
        closePopup()
        clearLoginSiteData {
            siteDataCleared = true
            setResult(Activity.RESULT_CANCELED, Intent().putExtra(EXTRA_EXIT_REASON, reason))
            finish()
        }
    }

    private fun clearLoginSiteData(done: () -> Unit) {
        val webStorage = WebStorage.getInstance()
        if (WebViewFeature.isFeatureSupported(WebViewFeature.DELETE_BROWSING_DATA)) {
            try {
                WebStorageCompat.deleteBrowsingDataForSite(webStorage, "https://x.com", Runnable {
                    WebStorageCompat.deleteBrowsingDataForSite(webStorage, "https://twitter.com", Runnable(done))
                })
                return
            } catch (_: Exception) {
                // Fall back to deleting the X session cookies on older WebView providers.
            }
        }
        clearSessionCookies(done)
    }

    private fun clearSessionCookies(done: () -> Unit) {
        val manager = CookieManager.getInstance()
        val operations = mutableListOf<Pair<String, String>>()
        COOKIE_URLS.forEach { url ->
            val root = if (Uri.parse(url).host.orEmpty().endsWith("twitter.com")) "twitter.com" else "x.com"
            manager.getCookie(url).orEmpty().split(';').forEach { part ->
                val name = part.substringBefore('=').trim()
                if (name.matches(Regex("[A-Za-z0-9_\\-]+"))) {
                    operations += url to "$name=; Max-Age=0; Path=/; Domain=.$root; Secure"
                    operations += url to "$name=; Max-Age=0; Path=/; Secure"
                }
            }
        }
        if (operations.isEmpty()) {
            done()
            return
        }
        var remaining = operations.size
        operations.forEach { (url, value) ->
            manager.setCookie(url, value) {
                remaining--
                if (remaining == 0) {
                    manager.flush()
                    WebStorage.getInstance().deleteOrigin("https://x.com")
                    WebStorage.getInstance().deleteOrigin("https://twitter.com")
                    done()
                }
            }
        }
    }

    @Deprecated("System back is handled by the OnBackInvoked callback on Android 13+")
    override fun onBackPressed() {
        handleSystemBack(2)
    }

    private fun handleSystemBack(source: Int) {
        val unexpectedFinish = source in 3..6
        if (unexpectedFinish) {
            val event = when (source) {
                4 -> "activity.unexpected_finish_affinity"
                5 -> "activity.unexpected_finish_remove_task"
                6 -> "activity.unexpected_finish_transition"
                else -> "activity.unexpected_finish"
            }
            XLoginDiagnostics.record(this, event)
        }
        else XLoginDiagnostics.record(this, "back.received", code = source)
        if (closing) return
        if (!unexpectedFinish && popupDialog?.isShowing == true) {
            XLoginDiagnostics.record(this, "back.popup_closed")
            closePopup()
            return
        }
        if (!unexpectedFinish && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
            window.decorView.rootWindowInsets?.isVisible(WindowInsets.Type.ime()) == true) {
            XLoginDiagnostics.record(this, "back.ime_hidden")
            window.decorView.windowInsetsController?.hide(WindowInsets.Type.ime())
            return
        }
        if (!unexpectedFinish && webView?.canGoBack() == true) {
            XLoginDiagnostics.record(this, "back.web_history")
            webView?.goBack()
            return
        }
        if (backConfirmation?.isShowing == true) {
            XLoginDiagnostics.record(this, "back.confirmation_already_shown")
            return
        }
        XLoginDiagnostics.record(this, "back.confirmation_shown")
        val dialog = AlertDialog.Builder(this)
            .setTitle("结束当前登录？")
            .setMessage("X 登录尚未完成。你可以继续当前页面，或确认结束并返回 ReviewX。")
            .setNegativeButton("继续登录") { _, _ -> XLoginDiagnostics.record(this, "back.confirmation_continue") }
            .setPositiveButton("结束登录") { _, _ -> cancelLogin(2) }
            .create()
        backConfirmation = dialog
        dialog.setOnDismissListener { if (backConfirmation === dialog) backConfirmation = null }
        dialog.show()
    }

    override fun onDestroy() {
        XLoginDiagnostics.record(this, "activity.destroyed", code = if (isFinishing) 1 else 0)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            (backInvokedCallback as? OnBackInvokedCallback)?.let {
                onBackInvokedDispatcher.unregisterOnBackInvokedCallback(it)
            }
        }
        backInvokedCallback = null
        backConfirmation?.dismiss()
        backConfirmation = null
        handler.removeCallbacksAndMessages(null)
        closePopup()
        webView?.let { view ->
            XLoginDiagnostics.record(this, "webview.destroyed")
            (view.parent as? ViewGroup)?.removeView(view)
            view.stopLoading()
            view.destroy()
        }
        webView = null
        if (!siteDataCleared) clearLoginSiteData { siteDataCleared = true }
        if (active === this) active = null
        super.onDestroy()
    }

    override fun finish() {
        if (!closing) {
            XLoginDiagnostics.record(this, "activity.finish_blocked")
            handleSystemBack(3)
            return
        }
        super.finish()
    }

    override fun finishAffinity() {
        if (!closing) {
            XLoginDiagnostics.record(this, "activity.finish_affinity_blocked")
            handleSystemBack(4)
            return
        }
        super.finishAffinity()
    }

    override fun finishAndRemoveTask() {
        if (!closing) {
            XLoginDiagnostics.record(this, "activity.finish_remove_task_blocked")
            handleSystemBack(5)
            return
        }
        super.finishAndRemoveTask()
    }

    override fun finishAfterTransition() {
        if (!closing) {
            XLoginDiagnostics.record(this, "activity.finish_transition_blocked")
            handleSystemBack(6)
            return
        }
        super.finishAfterTransition()
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

}
