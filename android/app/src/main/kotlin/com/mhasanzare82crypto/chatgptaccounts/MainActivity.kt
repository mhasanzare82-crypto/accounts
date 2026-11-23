package com.mhasanzare82crypto.chatgptaccounts

import android.content.Context
import android.view.View
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class MainActivity : FlutterActivity() {
    private val channelName = "com.example.chatgpt_accounts/profiles"

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
