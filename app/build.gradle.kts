plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.dsh.lancontrol"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.dsh.lancontrol"
        minSdk = 24
        targetSdk = 34
        versionCode = 10
        versionName = "2.0.0"

        // Default DSH address baked into the APK; override with -Pdsh.url=...
        val dshUrl = (project.findProperty("dsh.url") as String?)
            ?: "http://192.168.1.4:8787/"
        buildConfigField("String", "DSH_URL", "\"$dshUrl\"")
    }

    buildFeatures {
        buildConfig = true
    }

    buildTypes {
        debug {
            isMinifyEnabled = false
            isDebuggable = true
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

// No third-party runtime dependencies: platform APIs only, keeps builds fast and offline-friendly.
