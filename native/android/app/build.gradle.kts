import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.serialization")
    id("org.jetbrains.kotlin.plugin.compose")
    id("com.google.devtools.ksp")
}

// Load signing credentials from keystore.properties (gitignored — copy from keystore.properties.example)
val keystoreProps = Properties().also { props ->
    val f = rootProject.file("keystore.properties")
    if (f.exists()) props.load(f.inputStream())
}

android {
    namespace = "fr.armandmgt.velo"
    // compileSdk 37 is required by material3 1.5.0-alpha (the Expressive ToggleButton).
    compileSdk = 37

    defaultConfig {
        applicationId = "fr.armandmgt.velo"
        minSdk = 30
        targetSdk = 36
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
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    kotlinOptions {
        jvmTarget = "21"
    }

    sourceSets {
        named("main") { java { srcDirs("src/main/kotlin") } }
        named("test") { java { srcDirs("src/test/kotlin") } }
    }
}

// Compile with whatever JDK 21+ is running while targeting Java 21 bytecode.
// Avoids pinning an exact toolchain that must be installed.

dependencies {
    implementation("dev.hotwire:core:1.2.8")
    implementation("dev.hotwire:navigation-fragments:1.2.8")

    implementation("com.google.android.material:material:1.14.0")
    implementation("androidx.constraintlayout:constraintlayout:2.2.1")
    implementation("androidx.activity:activity-ktx:1.13.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.9.0")

    // Fused Location Provider — streams GPS fixes for the native recording (#55).
    implementation("com.google.android.gms:play-services-location:21.4.0")

    // MapLibre GL Native — the live map behind the recording screen (Recording.dc.html
    // redesign). Consumes the same MapTiler style the web uses, via the style URL
    // delivered in the path configuration's `settings` (ConfigurationsController).
    implementation("org.maplibre.gl:android-sdk:11.8.0")

    // Room — persists the in-progress recording session + ordered points so a ride
    // survives a process kill (#56). room-ktx adds coroutine/suspend support.
    implementation("androidx.room:room-runtime:2.8.4")
    implementation("androidx.room:room-ktx:2.8.4")
    ksp("androidx.room:room-compiler:2.8.4")

    // Jetpack Compose — the native recording screen (#54) is the first Compose
    // surface; the rest of the app stays webview/ViewBinding-based.
    implementation(platform("androidx.compose:compose-bom:2026.06.00"))
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    // material3 is pinned ABOVE the Compose BOM (which only ships stable, i.e. 1.4.0)
    // because the Material 3 Expressive `ToggleButton` used by the recording screen
    // only exists in the 1.5.0-alpha line. It's an experimental API
    // (@OptIn(ExperimentalMaterial3ExpressiveApi::class)); revisit once 1.5.0 is stable.
    implementation("androidx.compose.material3:material3:1.5.0-alpha22")
    debugImplementation("androidx.compose.ui:ui-tooling")

    // Pure-JVM unit tests (e.g. the GPX encoder's locale-safe formatting, #57).
    testImplementation("junit:junit:4.13.2")
}
