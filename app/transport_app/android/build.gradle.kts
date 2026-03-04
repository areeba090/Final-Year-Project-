buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        // Android Gradle Plugin
        classpath("com.android.tools.build:gradle:8.3.0")
        
        // Kotlin plugin (stable)
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:1.9.22")
        
        // Google services (Firebase)
        classpath("com.google.gms:google-services:4.4.2")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Flutter clean support
tasks.register<Delete>("clean") {
    delete(rootProject.buildDir)
}
