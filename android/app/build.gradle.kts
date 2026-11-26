plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.yossefjoo.joohub"
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
        applicationId = "com.yossefjoo.joohub"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

// Auto-clean any corrupted .png files uploaded by mobile IDEs (e.g. Klencod IDE)
// before AAPT2 compiles resources — our app uses pure XML vector @drawable/ic_joohub_v7
val cleanCorruptResPngs by tasks.registering {
    doLast {
        val resDir = file("src/main/res")
        if (resDir.exists()) {
            resDir.walkTopDown().forEach { f ->
                if (f.isFile && f.extension.equals("png", ignoreCase = true)) {
                    f.delete()
                }
            }
        }
    }
}

tasks.configureEach {
    if (name.startsWith("merge") && name.endsWith("Resources")) {
        dependsOn(cleanCorruptResPngs)
    }
    if (name.startsWith("map") && name.endsWith("SourceSetPaths")) {
        dependsOn(cleanCorruptResPngs)
    }
}
