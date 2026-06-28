// Top-level build file. Plugin versions are declared here and applied in :app.
plugins {
    id("com.android.application") version "8.9.1" apply false
    id("org.jetbrains.kotlin.android") version "2.1.20" apply false
    id("org.jetbrains.kotlin.plugin.serialization") version "2.1.20" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.1.20" apply false
    // KSP runs Room's annotation processor; version is pinned to the Kotlin 2.1.20 release.
    id("com.google.devtools.ksp") version "2.1.20-1.0.31" apply false
}
