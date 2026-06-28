// Top-level build file. Plugin versions are declared here and applied in :app.
plugins {
    id("com.android.application") version "9.2.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.21" apply false
    id("org.jetbrains.kotlin.plugin.serialization") version "2.2.21" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.2.21" apply false
    // KSP runs Room's annotation processor; version is pinned to the Kotlin 2.2.21 release.
    // KSP has no 2.3/2.4 build yet, so Kotlin is held at 2.2.21 to keep Room's processor working.
    id("com.google.devtools.ksp") version "2.3.2" apply false
}
