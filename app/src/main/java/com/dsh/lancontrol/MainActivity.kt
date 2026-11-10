package com.dsh.lancontrol

import android.annotation.SuppressLint
import android.app.Activity
import android.app.AlertDialog
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Color
import android.graphics.Typeface
import android.net.Uri
import android.os.Bundle
import android.text.InputType
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast

/**
 * 局域网控制 DSH —— DSH Web UI 的 Android 薄壳。
 *
 * 启动流程全部包在 try/catch 里：任何初始化异常都会直接渲染在屏幕上，
 * 而不是让 App 一声不响地闪退。
 */
class MainActivity : Activity() {

    companion object {
        private const val PREFS = "dsh_lan_prefs"
        private const val KEY_URL = "dsh_url"
        private const val KEY_LAST_GOOD = "dsh_last_good"
        private const val REQ_FILE = 1001

        private const val BG = "#0B1220"
        private const val FG = "#FFFFFF"
        private const val MUTED = "#9AA4B2"

        /** 构建时的占位地址；首次启动检测到它就弹设置框 */
        private const val PLACEHOLDER_HOST = "192.168.1.100"
    }

    private lateinit var root: FrameLayout
    private lateinit var webView: WebView
    private lateinit var errorView: View
    private lateinit var prefs: SharedPreferences

    private var fileCallback: ValueCallback<Array<Uri>>? = null
    private var currentUrl: String = ""

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        try {
            buildUi()
            showPreviousCrashIfAny()
        } catch (t: Throwable) {
            showFatal("界面初始化失败", t)
        }
    }

    // ------------------------------------------------------------------- 启动

    private fun buildUi() {
        root = FrameLayout(this)
        root.setBackgroundColor(Color.parseColor(BG))

        webView = WebView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            setBackgroundColor(Color.parseColor(BG))
        }
        root.addView(webView)

        configureWebView()
        root.addView(buildSettingsButton())
        errorView = buildErrorView()
        root.addView(errorView)
        errorView.visibility = View.GONE

        setContentView(root)

        currentUrl = prefs.getString(KEY_URL, null) ?: BuildConfig.DSH_URL
        load(currentUrl)
        // 首次启动且仍是占位地址时，直接让用户填真实地址
        if (prefs.getString(KEY_URL, null) == null &&
            BuildConfig.DSH_URL.contains(PLACEHOLDER_HOST)
        ) {
            root.post { showUrlDialog() }
        }
    }

    /** 上次崩溃（如果有）在启动后弹一次，方便截图反馈 */
    private fun showPreviousCrashIfAny() {
        val report = CrashLogger.take(this) ?: return
        try {
            AlertDialog.Builder(this)
                .setTitle("上次启动崩溃了")
                .setMessage(report.take(4000))
                .setPositiveButton("复制堆栈") { _, _ -> copyToClipboard(report) }
                .setNegativeButton("关闭", null)
                .show()
        } catch (_: Throwable) {
            // 弹窗本身失败就忽略，不影响正常使用
        }
    }

    private fun showFatal(title: String, t: Throwable) {
        val info = buildString {
            appendLine(title)
            appendLine()
            appendLine(CrashLogger.deviceInfo(this@MainActivity))
            appendLine("内置地址: " + BuildConfig.DSH_URL)
            appendLine()
            appendLine(t.stackTraceToString())
        }

        val tv = TextView(this).apply {
            typeface = Typeface.MONOSPACE
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
            setTextIsSelectable(true)
            setTextColor(Color.parseColor("#FFB4B4"))
            setPadding(dp(16), dp(16), dp(16), dp(16))
            text = info
        }
        val copy = Button(this).apply {
            text = "复制诊断信息"
            setOnClickListener { copyToClipboard(info) }
        }
        val box = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.BLACK)
            addView(copy)
            addView(ScrollView(this@MainActivity).apply { addView(tv) })
        }
        setContentView(box)
    }

    private fun copyToClipboard(text: String) {
        try {
            val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            cm.setPrimaryClip(ClipData.newPlainText("dsh-crash", text))
            Toast.makeText(this, "已复制，粘贴给开发者即可", Toast.LENGTH_SHORT).show()
        } catch (_: Throwable) {
        }
    }

    // ---------------------------------------------------------------- WebView

    @SuppressLint("SetJavaScriptEnabled")
    private fun configureWebView() {
        val s = webView.settings
        s.javaScriptEnabled = true
        s.domStorageEnabled = true
        s.databaseEnabled = true
        s.builtInZoomControls = false
        s.displayZoomControls = false
        s.mediaPlaybackRequiresUserGesture = false
        s.cacheMode = WebSettings.LOAD_DEFAULT
        s.mixedContentMode = WebSettings.MIXED_CONTENT_COMPATIBILITY_MODE
        // 关键：不要用「宽视口 + 概览缩放」，否则页面按桌面 980px 排版再整体缩小，
        // 字会小到看不清，移动端插件的 <=1023px 断点也不会按预期生效。
        s.useWideViewPort = false
        s.loadWithOverviewMode = false
        s.setSupportZoom(false)
        s.textZoom = 100
        runCatching {
            s.userAgentString = (s.userAgentString ?: "") + " DshLanControl/2.0"
        }

        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(
                view: WebView,
                request: WebResourceRequest
            ): Boolean {
                val url = request.url
                if (isSameOrigin(url)) return false
                return openExternally(url)
            }

            override fun onPageFinished(view: WebView, url: String?) {
                super.onPageFinished(view, url)
                errorView.visibility = View.GONE
                webView.visibility = View.VISIBLE
                url?.let { prefs.edit().putString(KEY_LAST_GOOD, it).apply() }
            }

            override fun onReceivedError(
                view: WebView,
                request: WebResourceRequest,
                error: WebResourceError
            ) {
                super.onReceivedError(view, request, error)
                if (request.isForMainFrame) showError()
            }
        }

        webView.webChromeClient = object : WebChromeClient() {
            override fun onShowFileChooser(
                webView: WebView,
                callback: ValueCallback<Array<Uri>>,
                params: FileChooserParams
            ): Boolean {
                fileCallback?.onReceiveValue(null)
                fileCallback = callback
                return try {
                    startActivityForResult(params.createIntent(), REQ_FILE)
                    true
                } catch (e: ActivityNotFoundException) {
                    fileCallback = null
                    false
                }
            }
        }
    }

    private fun isSameOrigin(target: Uri): Boolean {
        val base = Uri.parse(currentUrl)
        return target.host == base.host && target.port == base.port
    }

    private fun openExternally(target: Uri): Boolean = try {
        startActivity(Intent(Intent.ACTION_VIEW, target))
        true
    } catch (e: ActivityNotFoundException) {
        Toast.makeText(this, "没有可打开该链接的应用", Toast.LENGTH_SHORT).show()
        false
    }

    private fun load(url: String) {
        currentUrl = url
        errorView.visibility = View.GONE
        webView.visibility = View.VISIBLE
        runCatching { webView.loadUrl(url) }
            .onFailure { showFatal("加载地址失败: $url", it) }
    }

    // ------------------------------------------------------------- 错误页/设置

    private fun buildErrorView(): View {
        val box = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(28), dp(28), dp(28), dp(28))
            setBackgroundColor(Color.parseColor(BG))
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }

        val title = TextView(this).apply {
            text = getString(R.string.load_failed)
            setTextColor(Color.parseColor(FG))
            textSize = 18f
        }
        val hint = TextView(this).apply {
            text = getString(R.string.load_failed_hint)
            setTextColor(Color.parseColor(MUTED))
            textSize = 13f
            gravity = Gravity.CENTER
            setPadding(0, dp(10), 0, dp(22))
        }
        val retry = Button(this).apply {
            text = getString(R.string.retry)
            setOnClickListener { load(currentUrl) }
        }
        val edit = Button(this).apply {
            text = getString(R.string.edit_url)
            setOnClickListener { showUrlDialog() }
        }

        box.addView(title)
        box.addView(hint)
        box.addView(retry)
        box.addView(edit)
        return box
    }

    /** 页头下方的半透明「设置」，避开 DSH 右上角自己的图标 */
    private fun buildSettingsButton(): View = TextView(this).apply {
        text = "设置"
        textSize = 10f
        setTextColor(Color.parseColor("#C8D0DC"))
        gravity = Gravity.CENTER
        alpha = 0.40f
        setBackgroundColor(Color.parseColor("#33000000"))
        setOnClickListener { showUrlDialog() }
        layoutParams = FrameLayout.LayoutParams(dp(40), dp(22), Gravity.TOP or Gravity.END).apply {
            topMargin = dp(64)
            rightMargin = dp(8)
        }
    }

    private fun showError() {
        webView.visibility = View.GONE
        errorView.visibility = View.VISIBLE
    }

    private fun showUrlDialog() {
        val input = EditText(this).apply {
            inputType = InputType.TYPE_TEXT_VARIATION_URI
            setText(currentUrl)
            setSelection(text.length)
            hint = getString(R.string.conn_hint)
            setSingleLine()
        }
        val wrap = FrameLayout(this).apply {
            setPadding(dp(20), dp(8), dp(20), 0)
            addView(input)
        }

        AlertDialog.Builder(this)
            .setTitle(R.string.conn_settings)
            .setView(wrap)
            .setPositiveButton(R.string.conn_save) { _, _ ->
                var url = input.text.toString().trim()
                if (!url.startsWith("http://") && !url.startsWith("https://")) {
                    Toast.makeText(this, R.string.conn_bad_url, Toast.LENGTH_LONG).show()
                    return@setPositiveButton
                }
                if (!url.endsWith("/")) url += "/"
                prefs.edit().putString(KEY_URL, url).apply()
                load(url)
            }
            .setNegativeButton(R.string.conn_cancel, null)
            .show()
    }

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

    // ------------------------------------------------------------------ 生命周期

    @Deprecated("Deprecated in API 33, kept for minSdk 24")
    override fun onBackPressed() {
        when {
            ::webView.isInitialized && webView.canGoBack() -> webView.goBack()
            else -> super.onBackPressed()
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQ_FILE) {
            val cb = fileCallback
            fileCallback = null
            if (cb == null) return
            val uris: Array<Uri>? =
                if (resultCode == RESULT_OK && data != null) {
                    data.clipData?.let { clip ->
                        Array(clip.itemCount) { clip.getItemAt(it).uri }
                    } ?: data.data?.let { arrayOf(it) }
                } else null
            cb.onReceiveValue(uris)
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        runCatching {
            root.removeView(webView)
            webView.destroy()
        }
        super.onDestroy()
    }
}
