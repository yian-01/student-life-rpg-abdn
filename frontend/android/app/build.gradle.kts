import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeyFile = rootProject.file("key.properties")
val releaseKey = Properties()
if (releaseKeyFile.isFile) {
    releaseKeyFile.reader(Charsets.UTF_8).use { releaseKey.load(it) }
    val missing = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
        .filter { releaseKey.getProperty(it).isNullOrBlank() }
    require(missing.isEmpty()) {
        "Android signing configuration is incomplete. Missing keys: ${missing.joinToString()}"
    }
    require(rootProject.file(releaseKey.getProperty("storeFile")).isFile) {
        "Android signing keystore does not exist. Check storeFile in android/key.properties."
    }
}
val acceptanceSigning = providers.gradleProperty("studentLifeAcceptanceSigning").orNull == "true"
val hasReleaseKey = releaseKeyFile.isFile

// Acceptance signing must be explicit. A normal release must never silently
// receive the machine's disposable Android Debug certificate.
gradle.taskGraph.whenReady {
    val packagesRelease = allTasks.any {
        it.project == project && it.name in setOf("assembleRelease", "bundleRelease", "packageRelease")
    }
    if (packagesRelease && !hasReleaseKey && !acceptanceSigning) {
        throw GradleException(
            "Release signing is not configured. Create android/key.properties with the existing " +
                "release keystore. For a TEST-ONLY acceptance APK, explicitly set " +
                "ORG_GRADLE_PROJECT_studentLifeAcceptanceSigning=true. " +
                "Do not uninstall an old app to bypass a signing mismatch."
        )
    }
}

android {
    namespace = "com.example.student_life_rpg"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.student_life_rpg"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = rootProject.file(releaseKey.getProperty("storeFile"))
                storePassword = releaseKey.getProperty("storePassword")
                keyAlias = releaseKey.getProperty("keyAlias")
                keyPassword = releaseKey.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = when {
                hasReleaseKey -> signingConfigs.getByName("release")
                acceptanceSigning -> signingConfigs.getByName("debug")
                else -> null
            }
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
