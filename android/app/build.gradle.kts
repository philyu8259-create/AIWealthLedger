import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

apply(plugin = "com.huawei.agconnect")

val releaseKeystorePropertiesFile = rootProject.file("key.properties")
val releaseKeystoreProperties = Properties().apply {
    if (releaseKeystorePropertiesFile.exists()) {
        releaseKeystorePropertiesFile.inputStream().use { load(it) }
    }
}

fun releaseSigningValue(propertyName: String, environmentName: String): String? {
    return releaseKeystoreProperties.getProperty(propertyName)
        ?.trim()
        ?.takeIf { it.isNotEmpty() }
        ?: System.getenv(environmentName)?.trim()?.takeIf { it.isNotEmpty() }
}

val releaseStoreFilePath = releaseSigningValue(
    "storeFile",
    "AI_ACCOUNTANT_ANDROID_KEYSTORE_FILE"
)
val releaseStorePassword = releaseSigningValue(
    "storePassword",
    "AI_ACCOUNTANT_ANDROID_STORE_PASSWORD"
)
val releaseKeyAlias = releaseSigningValue(
    "keyAlias",
    "AI_ACCOUNTANT_ANDROID_KEY_ALIAS"
)
val releaseKeyPassword = releaseSigningValue(
    "keyPassword",
    "AI_ACCOUNTANT_ANDROID_KEY_PASSWORD"
)

android {
    namespace = "com.aiaccountant.ai_accountant"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.aiaccountant.ai_accountant"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += "region"

    productFlavors {
        create("cn") {
            dimension = "region"
            applicationId = "com.aiaccountant.ai_accountant.cn"
            minSdk = 24
        }
        create("intl") {
            dimension = "region"
            applicationId = "com.aiaccountant.ai_accountant.intl"
        }
    }

    signingConfigs {
        create("release") {
            releaseStoreFilePath?.let { storeFile = rootProject.file(it) }
            releaseStorePassword?.let { storePassword = it }
            releaseKeyAlias?.let { keyAlias = it }
            releaseKeyPassword?.let { keyPassword = it }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    "cnImplementation"("com.pangle.cn:mediation-sdk:7.6.1.1")
    "cnImplementation"("com.squareup.okhttp3:okhttp:3.12.1")
}

// Keep flavorless entrypoints blocked to avoid producing accidental cn/intl-mixed builds.
gradle.taskGraph.whenReady {
    val releaseTasks = allTasks.filter { task ->
        task.name.contains("Release", ignoreCase = true)
    }
    if (releaseTasks.isNotEmpty()) {
        val missingSigningValues = mutableListOf<String>().apply {
            if (releaseStoreFilePath == null) add("storeFile / AI_ACCOUNTANT_ANDROID_KEYSTORE_FILE")
            if (releaseStorePassword == null) add("storePassword / AI_ACCOUNTANT_ANDROID_STORE_PASSWORD")
            if (releaseKeyAlias == null) add("keyAlias / AI_ACCOUNTANT_ANDROID_KEY_ALIAS")
            if (releaseKeyPassword == null) add("keyPassword / AI_ACCOUNTANT_ANDROID_KEY_PASSWORD")
            if (releaseStoreFilePath != null && !rootProject.file(releaseStoreFilePath).isFile) {
                add("existing keystore file at $releaseStoreFilePath")
            }
        }
        if (missingSigningValues.isNotEmpty()) {
            throw GradleException(
                "Release builds require a production Android signing config. " +
                    "Set android/key.properties or environment variables for: " +
                    missingSigningValues.joinToString(", ") + ". " +
                    "Do not submit debug-signed builds to Huawei AppGallery."
            )
        }
    }

    if (allTasks.any { task ->
        task.name in setOf(
            "assembleDebug",
            "installDebug",
            "bundleDebug",
            "assembleProfile",
            "installProfile",
            "bundleProfile",
            "assembleRelease",
            "installRelease",
            "bundleRelease"
        )
    }) {
        throw GradleException(
            "Flavorless Android tasks are blocked because CN and EN are independent apps. Use one of:\n" +
                "  flutter run --flavor cn --dart-define=APP_FLAVOR=cn\n" +
                "  flutter run --flavor intl --dart-define=APP_FLAVOR=intl\n" +
                "  flutter build appbundle --release --flavor cn --dart-define=APP_FLAVOR=cn\n" +
                "  flutter build appbundle --release --flavor intl --dart-define=APP_FLAVOR=intl"
        )
    }
}
