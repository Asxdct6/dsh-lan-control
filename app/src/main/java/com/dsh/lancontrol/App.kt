package com.dsh.lancontrol

import android.app.Application

class App : Application() {
    override fun onCreate() {
        super.onCreate()
        CrashLogger.install(this)
    }
}
