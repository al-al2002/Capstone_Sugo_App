pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.9.1" apply false
    // Bumped from 2.1.0: firebase_auth 6.x ships Kotlin metadata newer
    // than 2.1.0 can read, so `:firebase_auth:compileDebugKotlin` failed
    // to compile until the plugin caught up.
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
    // Reads android/app/google-services.json, which `flutterfire configure`
    // writes. Without it Firebase has no project config at runtime and
    // initializeApp fails on Android.
    id("com.google.gms.google-services") version "4.4.2" apply false
}

include(":app")
