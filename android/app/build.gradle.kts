plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}
android {
    namespace = "com.review.x"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    val signingPath = System.getenv("REVIEW_X_STORE_FILE")
    signingConfigs {
        if (signingPath != null) {
            create("release") {
                storeFile = file(signingPath)
                storeType = "PKCS12"
                storePassword = System.getenv("REVIEW_X_STORE_PASSWORD")
                keyPassword = System.getenv("REVIEW_X_KEY_PASSWORD")
                keyAlias = System.getenv("REVIEW_X_KEY_ALIAS")
            }
        }
    }
    defaultConfig {
        applicationId = "com.review.x"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk { abiFilters.add("arm64-v8a") }
    }
    buildTypes {
        release {
            // Never silently produce a debug-signed release.
            signingConfig = signingConfigs.findByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
    packaging {
        jniLibs {
            excludes.add("lib/armeabi-v7a/**")
            excludes.add("lib/x86/**")
            excludes.add("lib/x86_64/**")
        }
    }
}
kotlin { compilerOptions { jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17 } }
flutter { source = "../.." }
dependencies {
    implementation("androidx.work:work-runtime-ktx:2.11.2")
    implementation("androidx.webkit:webkit:1.14.0")
}
gradle.taskGraph.whenReady {
    if (allTasks.any { it.name.contains("Release") } && System.getenv("REVIEW_X_STORE_FILE") == null) {
        throw GradleException("ReviewX release signing environment is required")
    }
}
