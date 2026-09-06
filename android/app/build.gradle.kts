plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.zanzibarr.zanzibarr"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.zanzibarr.zanzibarr"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

// unrar C++ runtime paylaşımlı libc++ kullanır; libc++_shared.so NDK'dan
// her ABI için jniLibs'e kopyalanır (yoksa dlopen "libc++_shared.so not
// found" ile düşer). NDK dizini sürümden bağımsız çözülür.
val ndkHome: String? = System.getenv("ANDROID_NDK_HOME")
    ?: System.getenv("ANDROID_NDK_ROOT")
    ?: System.getenv("ANDROID_HOME")?.let { home ->
        File("$home/ndk").takeIf { it.isDirectory }
            ?.listFiles()?.filter { it.isDirectory }?.maxByOrNull { it.name }
            ?.absolutePath
    }
val llvmHostTag = when {
    System.getProperty("os.name").startsWith("Windows", true) -> "windows-x86_64"
    System.getProperty("os.name").startsWith("Mac", true) ->
        if (System.getProperty("os.arch") == "aarch64") "darwin-arm64" else "darwin-x86_64"
    else -> "linux-x86_64"
}
val libcxxAbis = mapOf(
    "arm64-v8a" to "aarch64-linux-android",
    "armeabi-v7a" to "arm-linux-androideabi",
    "x86" to "i686-linux-android",
    "x86_64" to "x86_64-linux-android",
)
val libcxxOut = layout.buildDirectory.dir("libcxx/jniLibs")
val copyLibcxxShared = tasks.register("copyLibcxxShared") {
    doLast {
        libcxxAbis.forEach { (abi, triple) ->
            val src = File(
                "$ndkHome/toolchains/llvm/prebuilt/$llvmHostTag/sysroot/usr/lib/$triple/libc++_shared.so",
            )
            if (src.exists()) {
                val dst = File(libcxxOut.get().asFile, "$abi/libc++_shared.so")
                dst.parentFile.mkdirs()
                src.copyTo(dst, overwrite = true)
            } else {
                logger.warn("libc++_shared.so bulunamadı: ${src.absolutePath}")
            }
        }
    }
}
android.sourceSets.getByName("main").jniLibs.srcDir(libcxxOut)
tasks.named("preBuild").configure { dependsOn(copyLibcxxShared) }

dependencies {
    // OTA güncelleme: indirilen APK'yı sistem yükleyicisine veren FileProvider.
    implementation("androidx.core:core-ktx:1.13.1")
}

flutter {
    source = "../.."
}
