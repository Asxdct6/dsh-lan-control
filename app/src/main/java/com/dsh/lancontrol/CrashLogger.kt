package com.dsh.lancontrol

import android.content.Context
import android.os.Build
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 崩溃日志采集：把未捕获异常的堆栈写到私有目录，下次启动时由 MainActivity 读出来显示。
 * 手机上不用连电脑、不用 adb 也能拿到崩溃原因。
 */
object CrashLogger {

    private const val FILE_NAME = "last_crash.txt"

    fun install(ctx: Context) {
        val app = ctx.applicationContext
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            try {
                File(app.filesDir, FILE_NAME).writeText(
                    buildString {
                        appendLine("时间: " + SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date()))
                        appendLine("线程: " + thread.name)
                        appendLine(deviceInfo(app))
                        appendLine()
                        appendLine(error.stackTraceToString())
                    }
                )
                // 外部目录也放一份，方便用文件管理器导出
                app.getExternalFilesDir(null)?.let { dir ->
                    runCatching { File(dir, FILE_NAME).writeText(File(app.filesDir, FILE_NAME).readText()) }
                }
            } catch (_: Throwable) {
                // 记录失败就算了，绝不能在这里再抛
            }
            previous?.uncaughtException(thread, error)
        }
    }

    /** 读出上次崩溃并删除文件（只报一次） */
    fun take(ctx: Context): String? = try {
        val f = File(ctx.filesDir, FILE_NAME)
        if (f.exists()) f.readText().also { f.delete() } else null
    } catch (_: Throwable) {
        null
    }

    fun deviceInfo(ctx: Context? = null): String = buildString {
        append("Android ").append(Build.VERSION.RELEASE)
        append(" (API ").append(Build.VERSION.SDK_INT).append(")")
        append(" · ").append(Build.MANUFACTURER).append(' ').append(Build.MODEL)
        append(" · ABI ").append(Build.SUPPORTED_ABIS.joinToString("/"))
        if (ctx != null) {
            append(" · ").append(ctx.packageName)
            runCatching {
                val pm = ctx.packageManager
                val info = pm.getPackageInfo(ctx.packageName, 0)
                append(' ').append(info.versionName)
            }
        }
    }
}
