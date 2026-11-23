package com.mhasanzare82crypto.chatgptaccounts

import android.Manifest
import android.app.AlertDialog
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.Gravity
import android.view.View
import android.webkit.PermissionRequest
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.ProgressBar
import android.widget.TextView
import androidx.core.content.ContextCompat
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class MainActivity : FlutterActivity() {
    private var pendingWebPermissionRequest: PermissionRequest? = null
    private val microphonePermissionRequestCode = 7314
    private val channelName = "com.example.chatgpt_accounts/profiles"

    fun requestWebMicrophonePermission(request: PermissionRequest) {
        if (pendingWebPermissionRequest != null) {
            request.deny()
            return
        }
        pendingWebPermissionRequest = request
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            shouldShowRequestPermissionRationale(Manifest.permission.RECORD_AUDIO)
        ) {
            AlertDialog.Builder(this)
                .setTitle("اجازه استفاده از میکروفون")
                .setMessage("صفحه وب برای قابلیت صوتی به میکروفون نیاز دارد. آیا اجازه می‌دهی؟")
                .setNegativeButton("رد کردن") { _, _ ->
                    pendingWebPermissionRequest?.deny()
                    pendingWebPermissionRequest = null
                }
                .setPositiveButton("اجازه دادن") { _, _ ->
                    requestPermissions(
                        arrayOf(Manifest.permission.RECORD_AUDIO),
                        microphonePermissionRequestCode
                    )
                }
                .setOnCancelListener {
                    pendingWebPermissionRequest?.deny()
                    pendingWebPermissionRequest = null
                }
                .show()
        } else {
            requestPermissions(
                arrayOf(Manifest.permission.RECORD_AUDIO),
                microphonePermissionRequestCode
            )
        }
    }

    fun cancelWebMicrophonePermissionRequest(request: PermissionRequest) {
        if (pendingWebPermissionRequest == request) pendingWebPermissionRequest = null
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == microphonePermissionRequestCode) {
            val request = pendingWebPermissionRequest
            pendingWebPermissionRequest = null
            if (request != null) {
                if (grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED
                ) {
                    request.grant(arrayOf(PermissionRequest.RESOURCE_AUDIO_CAPTURE))
                } else {
                    request.deny()
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        flutterEngine.platformViewsController.registry.registerViewFactory(
            "chatgpt/accounts_webview",
            ChatGPTWebViewFactory()
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasMicrophonePermission" -> {
                        result.success(
                            ContextCompat.checkSelfPermission(
                                this,
                                Manifest.permission.RECORD_AUDIO
                            ) == PackageManager.PERMISSION_GRANTED
                        )
                    }
                    "isMultiProfileSupported" -> {
                        result.success(
                            WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)
                        )
                    }
                    "getTabConfigs" -> {
                        val prefs = getSharedPreferences("web_tab_configs", Context.MODE_PRIVATE)
                        val defaults = listOf(
                            "صفحه اول" to "https://chatgpt.com/",
                            "صفحه دوم" to "https://chatgpt.com/",
                            "صفحه سوم" to "https://chatgpt.com/"
                        )
                        result.success(defaults.mapIndexed { index, pair ->
                            mapOf(
                                "name" to (prefs.getString("name_$index", pair.first) ?: pair.first),
                                "url" to (prefs.getString("url_$index", pair.second) ?: pair.second)
                            )
                        })
                    }
                    "saveTabConfigs" -> {
                        val tabs = call.argument<List<Map<String, String>>>("tabs")
                        val valid = tabs != null && tabs.size == 3 && tabs.all { tab ->
                            val name = tab["name"]?.trim().orEmpty()
                            val url = tab["url"]?.trim().orEmpty()
                            name.isNotEmpty() && isAllowedHttpsUrl(url)
                        }
                        if (!valid || tabs == null) {
                            result.success(false)
                        } else {
                            val editor = getSharedPreferences(
                                "web_tab_configs",
                                Context.MODE_PRIVATE
                            ).edit()
                            tabs.forEachIndexed { index, tab ->
                                editor.putString("name_$index", tab["name"]!!.trim())
                                editor.putString("url_$index", Uri.parse(tab["url"]!!.trim()).toString())
                            }
                            result.success(editor.commit())
                        }
                    }
                    "loadAccountUrl" -> {
                        val profileName = call.argument<String>("profileName")
                        val url = call.argument<String>("url")
                        result.success(
                            profileName != null && url != null &&
                                isAllowedHttpsUrl(url) &&
                                ChatGPTWebPlatformView.loadUrl(profileName, url)
                        )
                    }
                    "handleBack" -> {
                        val profileName = call.argument<String>("profileName")
                        result.success(
                            profileName?.let { ChatGPTWebPlatformView.goBack(it) } ?: false
                        )
                    }
                    "reloadAccount" -> {
                        val profileName = call.argument<String>("profileName")
                        result.success(
                            profileName?.let { ChatGPTWebPlatformView.reload(it) } ?: false
                        )
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun isAllowedHttpsUrl(value: String): Boolean {
        return try {
            val uri = Uri.parse(value.trim())
            uri.scheme.equals("https", ignoreCase = true) &&
                !uri.host.isNullOrBlank() &&
                uri.userInfo.isNullOrEmpty()
        } catch (_: Exception) {
            false
        }
    }
}

private class ChatGPTWebViewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val parameters = args as? Map<*, *> ?: error("Missing WebView parameters")
        val profileName = parameters["profileName"] as? String
            ?: error("Missing WebView profile name")
        val initialUrl = parameters["initialUrl"] as? String
            ?: "https://chatgpt.com/"
        require(initialUrl.startsWith("https://", ignoreCase = true)) {
            "Only HTTPS URLs are allowed."
        }
        return ChatGPTWebPlatformView(context, profileName, initialUrl)
    }
}

private class ChatGPTWebPlatformView(
    context: Context,
    private val profileName: String,
    initialUrl: String
) : PlatformView {
    private val container = FrameLayout(context)
    private val webView = WebView(context)
    private val loadingIndicator = ProgressBar(context)
    private val errorMessage = TextView(context).apply {
        text = "صفحه بارگذاری نشد. اتصال اینترنت را بررسی کن و برای تلاش دوباره لمس کن."
        textSize = 15f
        gravity = Gravity.CENTER
        setPadding(32, 24, 32, 24)
        visibility = View.GONE
        setOnClickListener { webView.reload() }
    }

    init {
        check(WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)) {
            "This Android System WebView does not support independent profiles."
        }
        WebViewCompat.setProfile(webView, profileName)

        webView.settings.javaScriptEnabled = true
        webView.settings.domStorageEnabled = true
        webView.settings.databaseEnabled = true
        webView.settings.loadsImagesAutomatically = true
        webView.settings.javaScriptCanOpenWindowsAutomatically = true

        WebViewCompat.getProfile(webView).cookieManager.apply {
            setAcceptCookie(true)
            setAcceptThirdPartyCookies(webView, true)
        }

        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(
                view: WebView,
                request: WebResourceRequest
            ): Boolean {
                // Refuse insecure top-level navigation and redirects.
                return request.url.scheme != "https"
            }

            override fun onPageStarted(
                view: WebView,
                url: String?,
                favicon: android.graphics.Bitmap?
            ) {
                loadingIndicator.visibility = View.VISIBLE
                errorMessage.visibility = View.GONE
            }

            override fun onPageFinished(view: WebView, url: String?) {
                loadingIndicator.visibility = View.GONE
            }

            override fun onReceivedError(
                view: WebView,
                request: WebResourceRequest,
                error: android.webkit.WebResourceError
            ) {
                if (request.isForMainFrame) {
                    loadingIndicator.visibility = View.GONE
                    errorMessage.visibility = View.VISIBLE
                }
            }

            override fun onReceivedSslError(
                view: WebView,
                handler: android.webkit.SslErrorHandler,
                error: android.net.http.SslError
            ) {
                handler.cancel()
                loadingIndicator.visibility = View.GONE
                errorMessage.visibility = View.VISIBLE
            }
        }

        webView.webChromeClient = object : WebChromeClient() {
            override fun onPermissionRequest(request: PermissionRequest) {
                val secureOrigin = request.origin.scheme.equals("https", ignoreCase = true) &&
                    !request.origin.host.isNullOrBlank()
                val audioOnly = request.resources.size == 1 &&
                    request.resources.contains(PermissionRequest.RESOURCE_AUDIO_CAPTURE)

                if (!secureOrigin || !audioOnly) {
                    request.deny()
                    return
                }

                if (ContextCompat.checkSelfPermission(
                        context,
                        Manifest.permission.RECORD_AUDIO
                    ) == PackageManager.PERMISSION_GRANTED
                ) {
                    request.grant(arrayOf(PermissionRequest.RESOURCE_AUDIO_CAPTURE))
                } else {
                    (context as? MainActivity)?.requestWebMicrophonePermission(request)
                        ?: request.deny()
                }
            }

            override fun onPermissionRequestCanceled(request: PermissionRequest) {
                (context as? MainActivity)?.cancelWebMicrophonePermissionRequest(request)
            }
        }

        container.addView(
            webView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )
        container.addView(
            loadingIndicator,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER
            )
        )
        container.addView(
            errorMessage,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER
            )
        )
        webViews[profileName] = webView
        webView.loadUrl(initialUrl)
    }

    override fun getView(): View = container

    override fun dispose() {
        webView.stopLoading()
        webView.loadUrl("about:blank")
        webView.clearHistory()
        webView.removeAllViews()
        webView.destroy()
        webViews.remove(profileName)
    }

    companion object {
        private val webViews = mutableMapOf<String, WebView>()

        fun loadUrl(profileName: String, url: String): Boolean {
            val view = webViews[profileName] ?: return false
            view.loadUrl(url)
            return true
        }

        fun goBack(profileName: String): Boolean {
            val view = webViews[profileName] ?: return false
            if (!view.canGoBack()) return false
            view.goBack()
            return true
        }

        fun reload(profileName: String): Boolean {
            val view = webViews[profileName] ?: return false
            view.reload()
            return true
        }
    }
}
