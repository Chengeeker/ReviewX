plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}
android {
    namespace = "com.review.x"
    compileSdk = 36
    defaultConfig {
        applicationId = "com.review.x"
        minSdk = 24
        targetSdk = 36
        versionCode = 136
        versionName = "2.0.11"
        ndk { abiFilters.add("arm64-v8a") }
    }
    signingConfigs {
        if (System.getenv("REVIEW_X_STORE_FILE") != null) {
            create("release") {
                storeFile = file(System.getenv("REVIEW_X_STORE_FILE"))
                storeType = "PKCS12"
                storePassword = System.getenv("REVIEW_X_STORE_PASSWORD")
                keyPassword = System.getenv("REVIEW_X_KEY_PASSWORD")
                keyAlias = System.getenv("REVIEW_X_KEY_ALIAS")
            }
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
            isMinifyEnabled = false
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }
    buildFeatures { compose = true; buildConfig = true }
    testOptions {
        unitTests.isIncludeAndroidResources = true
        unitTests.all { it.systemProperty("robolectric.dependency.repo.url", "https://maven.aliyun.com/repository/public") }
    }
    packaging { jniLibs.excludes.addAll(listOf("lib/armeabi-v7a/**", "lib/x86/**", "lib/x86_64/**")) }
}
kotlin { compilerOptions { jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17 } }
dependencies {
    debugImplementation("androidx.compose.ui:ui-test-manifest")

    implementation("io.github.kyant0:backdrop:1.0.6")
    implementation("com.github.QWEA0:liquidglass:v2.0.11")
    implementation(platform("androidx.compose:compose-bom:2026.02.00"))
    implementation("androidx.compose.material3:material3:1.4.0")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.10.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.10.0")
    implementation("androidx.webkit:webkit:1.14.0")
    implementation("androidx.security:security-crypto:1.1.0")
    implementation("androidx.work:work-runtime-ktx:2.11.2")
    implementation("androidx.browser:browser:1.9.0")
    implementation("androidx.media3:media3-exoplayer:1.9.2")
    implementation("androidx.media3:media3-ui:1.9.2")
    implementation("androidx.media3:media3-datasource-okhttp:1.9.2")
    implementation("io.coil-kt:coil-compose:2.7.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
    testImplementation("org.robolectric:robolectric:4.16.1")
    testImplementation("androidx.compose.ui:ui-test-junit4")
}
gradle.taskGraph.whenReady {
    if (allTasks.any { it.name == "assembleRelease" } && System.getenv("REVIEW_X_STORE_FILE") == null) {
        throw GradleException("Release signing environment is required")
    }
}

// A transitive runtime upgrade must not leave app bytecode compiled against an older Compose API.
val verifyComposeAlignment by tasks.registering {
    doLast {
        val report = mutableListOf<String>()
        val mismatches = mutableListOf<String>()
        for (variant in listOf("debug", "release")) {
            fun versions(suffix: String) = configurations.getByName(variant + suffix)
                .incoming.resolutionResult.allComponents.mapNotNull { it.moduleVersion }
                .filter { it.group.startsWith("androidx.compose.") }
                .associate { "${it.group}:${it.name}" to it.version }
            val compile = versions("CompileClasspath")
            val runtime = versions("RuntimeClasspath")
            for ((module, version) in compile.toSortedMap()) {
                val packaged = runtime[module]
                val line = "$variant $module compile=$version runtime=$packaged"
                report += line
                if (version != packaged) mismatches += line
            }
        }
        val output = layout.buildDirectory.file("reports/compose-alignment.txt").get().asFile
        output.parentFile.mkdirs()
        output.writeText(report.joinToString("\n"))
        check(mismatches.isEmpty()) { "Compose compile/runtime mismatch:\n" + mismatches.joinToString("\n") }
        logger.lifecycle("Compose compile/runtime alignment verified for debug and release")
    }
}
tasks.matching { it.name == "preBuild" }.configureEach { dependsOn(verifyComposeAlignment) }
