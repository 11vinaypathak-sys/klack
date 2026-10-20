plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.klack.keyboard"
    compileSdk = 35
    buildToolsVersion = "35.0.0"

    defaultConfig {
        applicationId = "com.klack.keyboard"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
}

// ---------------------------------------------------------------------------
// Sound packs.
//
// The packs are *generated*, never sampled: ../Resources/generate_sounds.py
// synthesises every WAV from scratch (pure-stdlib Python). The Mac app keeps
// them out of git for the same reason, so the Android build copies them from
// the shared Resources/ folder into assets/ at build time.
// ---------------------------------------------------------------------------
val klackResources = rootProject.file("../Resources")
val profilesSource = File(klackResources, "profiles")
val profilesAssets = layout.projectDirectory.dir("src/main/assets/profiles")

val generateSoundPacks by tasks.registering(Exec::class) {
    group = "klack"
    description = "Runs ../Resources/generate_sounds.py to (re)synthesise all sound packs."
    workingDir = klackResources
    commandLine("python3", "generate_sounds.py")
    outputs.dir(profilesSource)
}

val syncSoundPacks by tasks.registering(Sync::class) {
    group = "klack"
    description = "Copies ../Resources/profiles into src/main/assets/profiles (run generateSoundPacks first if missing)."
    doFirst {
        if (!File(profilesSource, "clicky/click_down_1.wav").exists()) {
            throw GradleException(
                "No sound packs at $profilesSource. Run `./gradlew generateSoundPacks` " +
                    "(needs python3) or `python3 ../Resources/generate_sounds.py` first."
            )
        }
    }
    // Everything in Resources/profiles ships, including the three "real_*"
    // packs recorded from a real board -- they are the packs the Mac app
    // ships and what a user should hear first.
    from(profilesSource) {
        include("*/*.wav")
    }
    into(profilesAssets)
}

tasks.named("preBuild") { dependsOn(syncSoundPacks) }
