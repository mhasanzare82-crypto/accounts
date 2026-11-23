package com.mhasanzare82crypto.chatgptaccounts

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.view.View
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

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == microphonePermissionRequestCode) {
            val request = pendingWebPermissionRequest
            pendingWebPermissionRequest = null
            if (request != null) {
                if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                    request.grant(arrayOf(PermissionRequest.RESOURCE_AUDIO_CAPTURE))
                } else request.deny()
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
    private val webView = WebView(context)

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
            override fun onPageFinished(view: WebView, url: String?) {
                swipeRefresh.isRefreshing = false
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
                } else if (pendingWebPermissionRequest == null) {
                    (context as? MainActivity)?.requestWebMicrophonePermission(request) ?: request.deny()
                } else request.deny()
            }

            override fun onPermissionRequestCanceled(request: PermissionRequest) {
                if ((context as? MainActivity)?.cancelWebMicrophonePermissionRequest(request) == true) { }
            }
        }

        swipeRefresh.setOnRefreshListener {
            webView.reload()
        }
        swipeRefresh.addView(webView)
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
