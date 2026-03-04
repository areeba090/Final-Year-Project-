plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.areebakhan.transport_app"
    compileSdk = 35

    ndkVersion = "27.0.12077973"

    defaultConfig {
        applicationId = "com.areebakhan.transport_app"
        minSdk = 23
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {

    // ✅ Firebase BOM (version control here)
    implementation(platform("com.google.firebase:firebase-bom:33.4.0"))

    // ✅ Firebase Analytics
    implementation("com.google.firebase:firebase-analytics-ktx")
}
