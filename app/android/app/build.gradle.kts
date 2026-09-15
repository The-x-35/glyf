plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.demo.glyf"
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
        applicationId = "com.demo.glyf"
        // 26+ for java.time in the stores; Android 8.0 covers ~97% of devices.
        minSdk = maxOf(26, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
