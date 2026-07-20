plugins {
    id("com.android.library")
    kotlin("android")
    kotlin("plugin.serialization")
    id("org.jetbrains.kotlin.plugin.compose")
    `maven-publish`
}

// The published Android artifact — `ai.2389:mermaidkit-android`. Versioned
// independently of the Swift package (this bridge is younger); 0.x while the
// measure/theme/interaction surface still settles.
group = "ai.2389"
version = "0.1.0"

android {
    namespace = "ai.mermaidkit"
    compileSdk = 34

    defaultConfig {
        minSdk = 24
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    buildFeatures {
        compose = true
    }
    // The jniLibs are already stripped by android/native/build-jni.sh
    // (llvm-objcopy) — AGP does not strip prebuilt native libs, only ones it
    // builds itself.
    publishing {
        singleVariant("release") {
            withSourcesJar()
        }
    }
}

publishing {
    publications {
        register<MavenPublication>("release") {
            groupId = "ai.2389"
            artifactId = "mermaidkit-android"
            version = project.version.toString()
            afterEvaluate { from(components["release"]) }
            pom {
                name.set("MermaidKit for Android")
                description.set("Native Mermaid diagram rendering for Android — " +
                    "source string to a themed, accessible Canvas diagram.")
                url.set("https://github.com/2389-research/MermaidKit")
                licenses {
                    license {
                        name.set("MIT License")
                        url.set("https://github.com/2389-research/MermaidKit/blob/main/LICENSE")
                    }
                }
            }
        }
    }
}

dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")

    // Compose — the snap-in surface. `MermaidView` (classic View) has no Compose
    // dependency of its own; only the `MermaidDiagram` composable needs these.
    val composeBom = platform("androidx.compose:compose-bom:2024.09.02")
    implementation(composeBom)
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.ui:ui")
    // material3 supplies ColorScheme for MermaidTheme.fromMaterial + MermaidDiagram's
    // default theme. Only the Compose surface uses it.
    implementation("androidx.compose.material3:material3")

    testImplementation(kotlin("test"))

    androidTestImplementation(composeBom)
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test:runner:1.6.1")
    androidTestImplementation("androidx.test:core:1.6.1")
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}
