import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing comes from android/key.properties (gitignored) — see
// android/key.properties.example for the format and how to generate a
// keystore. Falls back to debug signing when it's absent so `flutter run
// --release` still works for local/CI builds that don't need a real signature.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    namespace = "com.genzplus.app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Overridden per-flavor below; kept here as the fallback Gradle
        // itself expects a value for before flavor resolution.
        applicationId = "com.genzplus.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Two build variants of one codebase — see lib/main.dart (phone) and
    // lib/main_tv.dart (TV) — but ONE Play Console app project. Play's
    // Android TV support for an existing app is a form-factor-scoped
    // release *inside* that app (Release > choose "Android TV" release),
    // not a separate app listing — Play rejected a distinct
    // com.genzplus.app.tv package ("needs to have package name
    // com.genzplus.app") and rejected an independent TV versionCode
    // sequence starting at 1 ("already used", since Play requires a
    // strictly increasing versionCode across every release in the app,
    // TV included). So both flavors must always share applicationId, and
    // any versionCode either one uses must still fit into that one shared,
    // increasing sequence — that's a different constraint from requiring
    // both flavors to use the *same* versionCode, which is why each flavor
    // now sets its own (still both higher than any previous release, still
    // distinct from each other). versionName still comes from defaultConfig
    // above (pubspec.yaml's version: line) — only versionCode is overridden
    // per flavor here. What still makes this a dedicated TV build is the
    // manifest overlay in src/tv/ (leanback support, TV banner,
    // LEANBACK_LAUNCHER) and the kIsTv-gated Dart entry point, not the
    // applicationId.
    flavorDimensions += "platform"
    productFlavors {
        create("phone") {
            dimension = "platform"
            applicationId = "com.genzplus.app"
            versionCode = 55
        }
        create("tv") {
            dimension = "platform"
            applicationId = "com.genzplus.app"
            versionCode = 56
        }
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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
