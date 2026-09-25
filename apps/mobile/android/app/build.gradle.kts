plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.transpose_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        prefab = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        // Integration targets must never install over the user's app. Flutter
        // drive may uninstall its target during cleanup, even after a failure.
        val flutterTarget = providers.gradleProperty("target").orNull
            ?.replace('\\', '/') ?: "lib/main.dart"
        applicationId = if (flutterTarget.contains("integration_test/")) {
            "com.example.transpose_mobile.qa"
        } else {
            "com.example.transpose_mobile"
        }
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
        externalNativeBuild {
            cmake {
                arguments("-DANDROID_STL=c++_shared")
                val rubberBandSourceDir = (System.getenv("TRANSPOSE_RUBBERBAND_SOURCE_DIR") ?: "")
                    .replace('\\', '/')
                arguments("-DTRANSPOSE_RUBBERBAND_SOURCE_DIR=$rubberBandSourceDir")
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("../../../../packages/audio_core/native/CMakeLists.txt")
            version = "3.22.1"
        }
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
    implementation("com.google.oboe:oboe:1.10.0")
    // Same Media3 version as the endorsed video_player_android backend.
    implementation("androidx.media3:media3-exoplayer:1.9.2")
}
