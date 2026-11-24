package com.mhasanzare82crypto.chatgptaccounts

import android.Manifest
import android.app.AlertDialog
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
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
import org.json.JSONArray
import org.json.JSONObject

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
                    requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), microphonePermissionRequestCode)
                }
                .setOnCancelListener {
                    pendingWebPermissionRequest?.deny()
                    pendingWebPermissionRequest = null
                }
                .show()
        } else {
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), microphonePermissionRequestCode)
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
                if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
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
                    "hasMicrophonePermission" -> result.success(
                        ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) ==
                            PackageManager.PERMISSION_GRANTED
                    )
                    "isMultiProfileSupported" -> result.success(
                        WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)
                    )
                    "getTabConfigs" -> result.success(readTabConfigs())
                    "saveTabConfigs" -> {
                        val tabs = call.argument<List<Map<String, String>>>("tabs")
                        val valid = tabs != null && tabs.isNotEmpty() && tabs.all { tab ->
                            val id = tab["id"].orEmpty()
                            val name = tab["name"]?.trim().orEmpty()
                            val url = tab["url"]?.trim().orEmpty()
                            validProfileId(id) && name.isNotEmpty() && allowedUrl(url)
                        } && tabs.map { it["id"] }.toSet().size == tabs.size
                        if (!valid || tabs == null) {
                            result.success(false)
                        } else {
                            val array = JSONArray()
                            tabs.forEach { tab ->
                                array.put(
                                    JSONObject()
                                        .put("id", tab["id"])
                                        .put("name", tab["name"]!!.trim())
                                        .put("url", Uri.parse(tab["url"]!!.trim()).toString())
                                )
                            }
                            result.success(
                                getSharedPreferences("web_tab_configs", Context.MODE_PRIVATE)
                                    .edit().putString("tabs_json", array.toString()).commit()
                            )
                        }
                    }
                    "loadAccountUrl" -> {
                        val profile = call.argument<String>("profileName")
                        val url = call.argument<String>("url")
                        result.success(profile != null && url != null &&
                            validProfileId(profile) && allowedUrl(url) &&
                            ChatGPTWebPlatformView.loadUrl(profile, url))
                    }
                    "handleBack" -> {
                        val profile = call.argument<String>("profileName")
                        result.success(profile?.let { ChatGPTWebPlatformView.goBack(it) } ?: false)
                    }
                    "reloadAccount" -> {
                        val profile = call.argument<String>("profileName")
                        result.success(profile?.let { ChatGPTWebPlatformView.reload(it) } ?: false)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun readTabConfigs(): List<Map<String, String>> {
        val prefs = getSharedPreferences("web_tab_configs", Context.MODE_PRIVATE)
        val stored = prefs.getString("tabs_json", null)
        if (!stored.isNullOrBlank()) {
            try {
                val array = JSONArray(stored)
                val result = mutableListOf<Map<String, String>>()
                for (i in 0 until array.length()) {
                    val item = array.optJSONObject(i) ?: continue
                    val id = item.optString("id")
                    val name = item.optString("name")
                    val url = item.optString("url")
                    if (validProfileId(id) && name.isNotBlank() && allowedUrl(url)) {
                        result.add(mapOf(
                            "id" to id,
                            "name" to name,
                            "url" to url,
                            "lastUrl" to (prefs.getString("last_url_" + id, url) ?: url)
                        ))
                    }
                }
                if (result.isNotEmpty()) return result
            } catch (_: Exception) {
                // Continue with migration/default values.
            }
        }

        // Keep old profile names so sessions from the fixed three-tab version remain available.
        val defaults = listOf(
            Triple("web_tab_profile_one", "صفحه اول", "https://chatgpt.com/"),
            Triple("web_tab_profile_two", "صفحه دوم", "https://chatgpt.com/"),
            Triple("web_tab_profile_three", "صفحه سوم", "https://chatgpt.com/")
        )
        val migrated = defaults.mapIndexed { index, item ->
            val oldUrl = prefs.getString("url_" + index, item.third) ?: item.third
            val safeUrl = if (allowedUrl(oldUrl)) oldUrl else item.third
            val name = prefs.getString("name_" + index, item.second) ?: item.second
            mapOf(
                "id" to item.first,
                "name" to name,
                "url" to safeUrl,
                "lastUrl" to (prefs.getString("last_url_" + item.first, safeUrl) ?: safeUrl)
            )
        }
        val array = JSONArray()
        migrated.forEach { tab ->
            array.put(JSONObject()
                .put("id", tab["id"])
                .put("name", tab["name"])
                .put("url", tab["url"]))
        }
        prefs.edit().putString("tabs_json", array.toString()).apply()
        return migrated
    }

    private fun validProfileId(value: String): Boolean =
        value.matches(Regex("^[A-Za-z0-9_]{1,80}$"))

    private fun allowedUrl(value: String): Boolean {
        return try {
            val uri = Uri.parse(value.trim())
            uri.scheme.equals("https", ignoreCase = true) &&
                !uri.host.isNullOrBlank() && uri.userInfo.isNullOrEmpty()
        } catch (_: Exception) {
            false
        }
    }
}

private class ChatGPTWebViewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = args as? Map<*, *> ?: error("Missing WebView parameters")
        val profile = params["profileName"] as? String ?: error("Missing profile name")
        val url = params["initialUrl"] as? String ?: "https://chatgpt.com/"
        require(profile.matches(Regex("^[A-Za-z0-9_]{1,80}$"))) { "Invalid profile name." }
        require(url.startsWith("https://", ignoreCase = true)) { "Only HTTPS URLs are allowed." }
        return ChatGPTWebPlatformView(context, profile, url)
    }
}

private class ChatGPTWebPlatformView(
    context: Context,
    private val profileName: String,
    initialUrl: String
) : PlatformView {
    private val container = FrameLayout(context)
    private val webView = WebView(context)
    private val progress = ProgressBar(context)
    private val error = TextView(context).apply {
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
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean =
                !request.url.scheme.equals("https", ignoreCase = true)

            override fun onPageStarted(view: WebView, url: String?, favicon: android.graphics.Bitmap?) {
                progress.visibility = View.VISIBLE
                error.visibility = View.GONE
                saveLastUrl(url)
            }

            override fun onPageFinished(view: WebView, url: String?) {
                progress.visibility = View.GONE
                saveLastUrl(url)
            }

            override fun onReceivedError(
                view: WebView,
                request: WebResourceRequest,
                errorInfo: android.webkit.WebResourceError
            ) {
                if (request.isForMainFrame) {
                    progress.visibility = View.GONE
                    error.visibility = View.VISIBLE
                }
            }

            override fun onReceivedSslError(
                view: WebView,
                handler: android.webkit.SslErrorHandler,
                sslError: android.net.http.SslError
            ) {
                handler.cancel()
                progress.visibility = View.GONE
                error.visibility = View.VISIBLE
            }
        }

        webView.webChromeClient = object : WebChromeClient() {
            override fun onPermissionRequest(request: PermissionRequest) {
                val secure = request.origin.scheme.equals("https", ignoreCase = true) &&
                    !request.origin.host.isNullOrBlank()
                val audioOnly = request.resources.size == 1 &&
                    request.resources.contains(PermissionRequest.RESOURCE_AUDIO_CAPTURE)
                if (!secure || !audioOnly) {
                    request.deny()
                    return
                }
                if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
                    PackageManager.PERMISSION_GRANTED
                ) {
                    request.grant(arrayOf(PermissionRequest.RESOURCE_AUDIO_CAPTURE))
                } else {
                    (context as? MainActivity)?.requestWebMicrophonePermission(request) ?: request.deny()
                }
            }

            override fun onPermissionRequestCanceled(request: PermissionRequest) {
                (context as? MainActivity)?.cancelWebMicrophonePermissionRequest(request)
            }
        }

        container.addView(webView, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        container.addView(progress, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.CENTER))
        container.addView(error, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.CENTER))
        webViews[profileName] = webView
        webView.loadUrl(initialUrl)
    }

    private fun saveLastUrl(value: String?) {
        if (value.isNullOrBlank()) return
        val uri = Uri.parse(value)
        if (!uri.scheme.equals("https", ignoreCase = true) || uri.host.isNullOrBlank()) return
        webView.context.getSharedPreferences("web_tab_configs", Context.MODE_PRIVATE)
            .edit().putString("last_url_" + profileName, value).apply()
    }

    override fun getView(): View = container

    override fun dispose() {
        // Preserve WebView profile data and the persisted last URL on Activity disposal.
        webView.stopLoading()
        webView.removeAllViews()
        webView.destroy()
        if (webViews[profileName] === webView) webViews.remove(profileName)
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
