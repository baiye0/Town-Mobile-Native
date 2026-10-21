plugins { id("com.android.application"); id("org.jetbrains.kotlin.android"); id("org.jetbrains.kotlin.plugin.compose") }
android {
    namespace = "town.nativeapp"
    compileSdk = 36
    defaultConfig { applicationId = "town.beings.nativeapp"; minSdk = 28; targetSdk = 36; versionCode = 1; versionName = "0.1.0"; testInstrumentationRunner = providers.gradleProperty("testRunner").orElse("town.nativeapp.ChatScrollInstrumentation").get() }
    defaultConfig.manifestPlaceholders["appLabel"] = "Being"
    if (providers.gradleProperty("portalQa").orNull == "true") {
        defaultConfig.applicationId = "town.beings.nativeapp.portalqa"
        defaultConfig.manifestPlaceholders["appLabel"] = "Being Portal QA"
    }
    buildFeatures { compose = true; buildConfig = true }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17" }
    // The executable must live in the package manager's executable native directory.
    sourceSets["main"].jniLibs.srcDir(project(":portal-runtime").layout.buildDirectory.dir("jniLibs"))
    packaging { jniLibs { useLegacyPackaging = true; keepDebugSymbols += "**/libheart_portal.so" } }
}
tasks.named("preBuild") { dependsOn(":portal-runtime:buildPortal") }
dependencies {
    implementation(platform("androidx.compose:compose-bom:2025.09.01"))
    implementation("androidx.activity:activity-compose:1.11.0")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-core")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.9.4")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.9.4")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("androidx.health.connect:connect-client:1.1.0")
    implementation("com.google.android.gms:play-services-location:21.3.0")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
    androidTestImplementation("com.squareup.okhttp3:mockwebserver:4.12.0")
}
