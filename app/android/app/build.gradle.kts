import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The Play upload key, from android/key.properties (never committed; see
// docs/PLAY-STORE.md): storeFile, storePassword, keyAlias, keyPassword. Without
// it a release build signs with the debug key, which Play refuses.
val uploadKey = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

android {
    namespace = "com.arpit.glyf"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // BuildConfig.DEBUG drives the dev/production backend switch.
    buildFeatures {
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Glyf's ID on Google Play and the iPhone app's too; fixed for good at
        // the first upload (2026-10-04). It was com.demo.glyf before that.
        applicationId = "com.arpit.glyf"
        // 26+ for java.time in the stores; Android 8.0 covers ~97% of devices.
        // 28: first set for Privy's wallet SDK (gone); kept as the tested floor.
        minSdk = maxOf(28, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (uploadKey.getProperty("storeFile") != null) {
            create("upload") {
                storeFile = rootProject.file(uploadKey.getProperty("storeFile"))
                storePassword = uploadKey.getProperty("storePassword")
                keyAlias = uploadKey.getProperty("keyAlias")
                keyPassword = uploadKey.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // The upload key when android/key.properties names one; the debug
            // key otherwise, so `flutter run --release` still works.
            signingConfig = signingConfigs.findByName("upload") ?: signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Sign in with Google (Credential Manager), for the ID token the server checks.
    implementation("androidx.credentials:credentials:1.5.0")
    // The emoji board's grids (emoji paging sideways, GIFs in columns).
    implementation("androidx.recyclerview:recyclerview:1.3.2")
    implementation("androidx.credentials:credentials-play-services-auth:1.5.0")
    implementation("com.google.android.libraries.identity.googleid:googleid:1.1.1")
    // Google Calendar and Meet for the keyboard: Play services' authorization
    // hands out access tokens; the version Credential Manager already brings.
    implementation("com.google.android.gms:play-services-auth:21.1.1")
    // Google Play Billing, for Plus and Max on Android. In the bundle before the
    // paywall uses it: Play lets subscriptions be created only for an app with a
    // billing library, and read a bare BILLING permission as the retired AIDL
    // billing (it asked for 8.0.0 or newer).
    implementation("com.android.billingclient:billing-ktx:9.1.0")
    // JVM unit tests for the IME's pure logic (gestures, typing engine) —
    // the same cases RunnerTests covers on iOS.
    testImplementation("junit:junit:4.13.2")
    // The real org.json (android.jar only ships stubs to JVM tests).
    testImplementation("org.json:json:20240303")
}

android {
    sourceSets {
        // The typing engine's base dictionary (tools/build_dictionary.py).
        getByName("main") { assets.srcDir("../../dict") }
    }
    testOptions {
        // android.* calls in pure-logic tests return defaults instead of throwing.
        unitTests.isReturnDefaultValues = true
    }
}
