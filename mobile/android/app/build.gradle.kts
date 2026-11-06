import groovy.json.JsonSlurper

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

/// Push through Firebase Cloud Messaging, when the build has the Firebase project's
/// google-services.json: in android/app (never committed) or where ANYPS5_GOOGLE_SERVICES_JSON
/// points. Without it the app has no Android push, and its settings say so. The values the
/// google-services plugin would write are written here, so the build needs no extra plugin.
val packageName = "org.anyps5.anyps5_remote"
val googleServices: Map<String, String>? = run {
    val file = System.getenv("ANYPS5_GOOGLE_SERVICES_JSON")?.takeIf { it.isNotBlank() }?.let { file(it) }
        ?: file("google-services.json")
    if (!file.exists()) return@run null
    @Suppress("UNCHECKED_CAST")
    val json = JsonSlurper().parse(file) as Map<String, Any?>
    val project = json["project_info"] as Map<String, Any?>
    val clients = json["client"] as List<Map<String, Any?>>
    val client = clients.firstOrNull {
        val info = (it["client_info"] as Map<String, Any?>)["android_client_info"] as Map<String, Any?>
        info["package_name"] == packageName
    } ?: throw GradleException("google-services.json has no Android app for $packageName")
    val keys = client["api_key"] as List<Map<String, Any?>>
    mapOf(
        "google_app_id" to ((client["client_info"] as Map<String, Any?>)["mobilesdk_app_id"] as String),
        "gcm_defaultSenderId" to (project["project_number"] as String),
        "project_id" to (project["project_id"] as String),
        "google_api_key" to (keys.first()["current_key"] as String),
    )
}

android {
    namespace = "org.anyps5.anyps5_remote"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = packageName
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        googleServices?.forEach { (name, value) -> resValue("string", name, value) }
    }

    buildFeatures {
        resValues = true
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
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
    // Push: the token and the messages. It starts only with the values above.
    implementation("com.google.firebase:firebase-messaging:24.1.0")
}
