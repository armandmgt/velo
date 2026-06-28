import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.serialization")
    id("org.jetbrains.kotlin.plugin.compose")
}

// Load signing credentials from keystore.properties (gitignored — copy from keystore.properties.example)
val keystoreProps = Properties().also { props ->
    val f = rootProject.file("keystore.properties")
    if (f.exists()) props.load(f.inputStream())
}

android {
    namespace = "fr.armandmgt.velo"
    compileSdk = 35

    defaultConfig {
        applicationId = "fr.armandmgt.velo"
        minSdk = 28
        targetSdk = 35
        // Override at build time with `-Pvelo.versionCode=N` (fastlane does this from
        // the latest Play Console internal-track code + 1).
        versionCode = (project.findProperty("velo.versionCode") as String?)?.toIntOrNull() ?: 1
        versionName = "0.1.0"
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProps.getProperty("keyAlias") ?: ""
            keyPassword = keystoreProps.getProperty("keyPassword") ?: ""
            storeFile = keystoreProps.getProperty("storeFile")?.let { file(it) }
            storePassword = keystoreProps.getProperty("storePassword") ?: ""
        }
    }

    buildTypes {
        debug {
            isDebuggable = true
            // The Android emulator reaches the host's localhost via 10.0.2.2.
            buildConfigField("String", "BASE_URL", "\"http://10.0.2.2:3000\"")
        }
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("release")
            buildConfigField("String", "BASE_URL", "\"https://velo.armandmgt.fr\"")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    buildFeatures {
        viewBinding = true
        buildConfig = true
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    sourceSets {
        named("main") { java { srcDirs("src/main/kotlin") } }
    }
}

// Compile with whatever JDK 17+ is running (e.g. JDK 21) while targeting
// Java 17 bytecode. Avoids pinning an exact toolchain that must be installed.

dependencies {
    implementation("dev.hotwire:core:1.2.0")
    implementation("dev.hotwire:navigation-fragments:1.2.0")

    implementation("com.google.android.material:material:1.12.0")
    implementation("androidx.constraintlayout:constraintlayout:2.2.1")
    implementation("androidx.activity:activity-ktx:1.9.3")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.8.1")

    // Fused Location Provider — streams GPS fixes for the native recording (#55).
    implementation("com.google.android.gms:play-services-location:21.3.0")

    // Jetpack Compose — the native recording screen (#54) is the first Compose
    // surface; the rest of the app stays webview/ViewBinding-based.
    implementation(platform("androidx.compose:compose-bom:2024.12.01"))
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    debugImplementation("androidx.compose.ui:ui-tooling")
}
