package com.mhasanzare82crypto.chatgptaccounts

import android.Manifest
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.content.pm.PackageManager
import android.view.View
import android.view.Gravity
import android.widget.FrameLayout
import android.widget.ProgressBar
import android.widget.TextView
import android.app.AlertDialog
import android.provider.Settings
import android.webkit.WebView
import android.webkit.WebChromeClient
import android.webkit.PermissionRequest
import android.webkit.WebViewClient
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout
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
        requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), microphonePermissionRequestCode)
    }

    fun cancelWebMicrophonePermissionRequest(request: PermissionRequest): Boolean {
        if (pendingWebPermissionRequest != request) return false
        pendingWebPermissionRequest = null
        return true
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == microphonePermissionRequestCode) {
            val request = pendingWebPermissionRequest
            pendingWebPermissionRequest = null
            if (request != null) {
                if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                    request.grant(arrayOf(PermissionRequest.RESOURCE_AUDIO_CAPTURE))
                } else {
                    request.deny()
                    showMicrophoneSettingsDialog()
                }
            }
        } else if (requestCode == 7315) {
            // Flutter rechecks permission when the activity resumes.
        }
    }

    private fun showMicrophoneSettingsDialog() {
        runOnUiThread {
            AlertDialog.Builder(this)
                .setTitle("مجوز میکروفون لازم است")
                .setMessage("برای استفاده از میکروفون در ChatGPT، مجوز میکروفون برنامه را فعال کن. می‌توانی وارد تنظیمات برنامه شوی و دسترسی میکروفون را بدهی.")
                .setNegativeButton("بعداً", null)
                .setPositiveButton("رفتن به تنظیمات") { _, _ ->
                    val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = Uri.fromParts("package", packageName, null)
                    }
                    startActivity(intent)
                }
                .show()
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
                        result.success(ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED)
                    }
                    "requestMicrophonePermission" -> {
                        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
                            result.success(true)
                        } else {
                            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 7315)
                            result.success(true)
                        }
                    }
                    "getAccountLabels" -> {
                        val prefs = getSharedPreferences("account_labels", Context.MODE_PRIVATE)
                        val defaults = arrayOf("حساب ۱", "حساب ۲", "حساب ۳", "حساب ۴")
                        result.success((0..3).map { prefs.getString("label_$it", defaults[it]) ?: defaults[it] })
                    }
                    "saveAccountLabels" -> {
                        val labels = call.argument<List<String>>("labels")
                        if (labels != null && labels.size == 4 && labels.all { it.trim().isNotEmpty() }) {
                            val prefs = getSharedPreferences("account_labels", Context.MODE_PRIVATE).edit()
                            labels.forEachIndexed { index, label -> prefs.putString("label_$index", label.trim()) }
                            result.success(prefs.commit())
                        } else result.success(false)
                    }
                    "isMultiProfileSupported" -> result.success(
                        WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)
                    )
                    "handleBack" -> {
                        val profileName = call.argument<String>("profileName")
                        result.success(profileName?.let { ChatGPTWebPlatformView.goBack(it) } ?: false)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}

private class ChatGPTWebViewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val parameters = args as? Map<*, *> ?: error("Missing WebView parameters")
        val profileName = parameters["profileName"] as? String
            ?: error("Missing WebView profile name")
        val initialUrl = parameters["initialUrl"] as? String ?: "https://chatgpt.com/"
        return ChatGPTWebPlatformView(context, profileName, initialUrl)
    }
}

private class ChatGPTWebPlatformView(
    context: Context,
    private val profileName: String,
    initialUrl: String
) : PlatformView {
    private val swipeRefresh = SwipeRefreshLayout(context)
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
        // Set the isolated profile before settings, attachment, or navigation.
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
            override fun onPageStarted(view: WebView, url: String?, favicon: android.graphics.Bitmap?) {
                loadingIndicator.visibility = View.VISIBLE
                errorMessage.visibility = View.GONE
            }

            override fun onPageFinished(view: WebView, url: String?) {
                swipeRefresh.isRefreshing = false
                loadingIndicator.visibility = View.GONE
            }

            override fun onReceivedError(
                view: WebView,
                request: android.webkit.WebResourceRequest,
                error: android.webkit.WebResourceError
            ) {
                if (request.isForMainFrame) {
                    swipeRefresh.isRefreshing = false
                    loadingIndicator.visibility = View.GONE
                    errorMessage.visibility = View.VISIBLE
                }
            }

            override fun onReceivedHttpError(
                view: WebView,
                request: android.webkit.WebResourceRequest,
                errorResponse: android.webkit.WebResourceResponse
            ) {
                if (request.isForMainFrame && errorResponse.statusCode >= 500) {
                    swipeRefresh.isRefreshing = false
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
                swipeRefresh.isRefreshing = false
                loadingIndicator.visibility = View.GONE
                errorMessage.visibility = View.VISIBLE
            }
        }

        webView.webChromeClient = object : WebChromeClient() {
            override fun onPermissionRequest(request: PermissionRequest) {
                val host = request.origin.host
                val trustedOrigin = host == "chatgpt.com" || host?.endsWith(".chatgpt.com") == true
                val audioOnly = request.resources.size == 1 && request.resources.contains(PermissionRequest.RESOURCE_AUDIO_CAPTURE)
                if (!trustedOrigin || !audioOnly) {
                    request.deny()
                    return
                }
                if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
                    request.grant(arrayOf(PermissionRequest.RESOURCE_AUDIO_CAPTURE))
                } else {
                    (context as? MainActivity)?.requestWebMicrophonePermission(request) ?: request.deny()
                }
            }

            override fun onPermissionRequestCanceled(request: PermissionRequest) {
                (context as? MainActivity)?.cancelWebMicrophonePermissionRequest(request)
            }
        }

        swipeRefresh.setOnRefreshListener {
            webView.reload()
        }
        container.addView(webView, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT
        ))
        container.addView(loadingIndicator, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.CENTER
        ))
        container.addView(errorMessage, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.CENTER
        ))
        swipeRefresh.addView(container)
        swipeRefresh.setColorSchemeResources(android.R.color.holo_green_dark)
        webViews[profileName] = webView
        webView.loadUrl(initialUrl)
    }

    override fun getView(): View = swipeRefresh

    override fun dispose() {
        swipeRefresh.setOnRefreshListener(null)
        webView.stopLoading()
        webView.loadUrl("about:blank")
        webView.clearHistory()
        webView.removeAllViews()
        webView.destroy()
        webViews.remove(profileName)
        swipeRefresh.removeAllViews()
    }

    companion object {
        private val webViews = mutableMapOf<String, WebView>()

        fun goBack(profileName: String): Boolean {
            val view = webViews[profileName] ?: return false
            if (!view.canGoBack()) return false
            view.goBack()
            return true
        }
    }
}
