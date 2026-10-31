import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // END: FlutterFire Configuration
    id("dev.flutter.flutter-gradle-plugin")
}

val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties()
if (keyPropertiesFile.exists()) {
    keyProperties.load(keyPropertiesFile.inputStream())
}

android {
    namespace = "th.ac.acat.healthcarestation"
    // Google Play บังคับ target API 36 (Android 16) สำหรับแอปใหม่ตั้งแต่ 31 ส.ค. 2026
    // ใช้ maxOf เพื่อไม่ให้ต่ำกว่า 36 แต่ถ้า Flutter รุ่นใหม่ตั้งค่าสูงกว่าก็ใช้ของ Flutter
    compileSdk = maxOf(flutter.compileSdkVersion, 36)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    if (keyPropertiesFile.exists()) {
        signingConfigs {
            create("release") {
                keyAlias = keyProperties["keyAlias"] as String
                keyPassword = keyProperties["keyPassword"] as String
                storeFile = file(keyProperties["storeFile"] as String)
                storePassword = keyProperties["storePassword"] as String
            }
        }
    }

    defaultConfig {
        applicationId = "th.ac.acat.healthcarestation"
        minSdk = flutter.minSdkVersion
        targetSdk = maxOf(flutter.targetSdkVersion, 36)
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // ไม่มี key.properties → ไม่ตั้ง signingConfig เลย แล้วให้ build release
            // ล้มด้านล่าง (เดิม fallback ไป debug key แบบเงียบๆ — Play ไม่รับ และ
            // ถ้าเผลอแจก APK ที่เซ็นด้วย debug key ไป ผู้ใช้จะอัปเดตทับไม่ได้)
            if (keyPropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

// กัน release build ที่ไม่มี upload key — เช็คตอนจะรันจริงเท่านั้น
// เพื่อไม่ให้ debug build (flutter run) พังไปด้วย
gradle.taskGraph.whenReady {
    val buildingRelease = allTasks.any { it.project == project && it.name.contains("Release") }
    if (buildingRelease && !keyPropertiesFile.exists()) {
        throw GradleException(
            "ไม่พบ android/key.properties — release build ต้องเซ็นด้วย upload key " +
            "(ดูขั้นตอนสร้าง keystore ใน docs/play-store-release.md)"
        )
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
