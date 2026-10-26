// Permette di compilare e testare la logica pura da sola, senza Android SDK né Google Maven:
//   ./gradlew -p core test
// Nella build completa (Android Studio) questo file viene ignorato e vale ../settings.gradle.kts.
pluginManagement {
    repositories {
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositories {
        mavenCentral()
    }
    versionCatalogs {
        create("libs") {
            from(files("../gradle/libs.versions.toml"))
        }
    }
}

rootProject.name = "core"
