plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.serialization")
}

android {
    namespace = "fr.armandmgt.velo"
    compileSdk = 35

    defaultConfig {
        applicationId = "fr.armandmgt.velo"
        minSdk = 28
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"
    }

    buildTypes {
        debug {
            isDebuggable = true
            // The Android emulator reaches the host's localhost via 10.0.2.2.
            buildConfigField("String", "BASE_URL", "\"http://10.0.2.2:3000\"")
        }
        release {
            isMinifyEnabled = false
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
}
