package com.example.exm1

import android.content.Context
import android.view.View
import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature

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
                    "isMultiProfileSupported" -> {
                        result.success(
                            WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)
                        )
                    }
                    else -> result.notImplemented()
                }
            }
    }
}

private class ChatGPTWebViewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val parameters = args as? Map<*, *>
        val profileName = parameters?.get("profileName") as? String
            ?: error("Missing WebView profile name")
        val initialUrl = parameters["initialUrl"] as? String ?: "https://chatgpt.com/"
        return ChatGPTWebPlatformView(context, profileName, initialUrl)
    }
}

private class ChatGPTWebPlatformView(
    context: Context,
    profileName: String,
    initialUrl: String
) : PlatformView {
    private val webView: WebView = WebView(context)

    init {
        // Assign the non-default profile before configuring or loading the WebView.
        check(WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)) {
            "This Android System WebView does not support independent profiles."
        }
        WebViewCompat.setProfile(webView, profileName)

        webView.settings.javaScriptEnabled = true
        webView.settings.domStorageEnabled = true
        webView.settings.databaseEnabled = true
        webView.settings.loadsImagesAutomatically = true
        webView.settings.javaScriptCanOpenWindowsAutomatically = true

        // Use the cookie manager belonging to this profile, never the global default one.
        WebViewCompat.getProfile(webView).cookieManager.apply {
            setAcceptCookie(true)
            setAcceptThirdPartyCookies(webView, true)
        }

        webView.webViewClient = WebViewClient()
        webView.loadUrl(initialUrl)
    }

    override fun getView(): View = webView

    override fun dispose() {
        webView.stopLoading()
        webView.loadUrl("about:blank")
        webView.clearHistory()
        webView.removeAllViews()
        webView.destroy()
    }
}
