plugins { base }

val sdk = providers.environmentVariable("ANDROID_HOME").orNull
    ?: java.util.Properties().apply {
        rootProject.file("local.properties").takeIf { it.exists() }?.inputStream()?.use { load(it) }
    }.getProperty("sdk.dir")
val ndkVersion = "27.2.12479018"
val windows = System.getProperty("os.name").startsWith("Windows")
val host = if (windows) "windows-x86_64" else if (System.getProperty("os.name").contains("Mac")) "darwin-x86_64" else "linux-x86_64"
val bin = file("$sdk/ndk/$ndkVersion/toolchains/llvm/prebuilt/$host/bin")
val selectedAbis = providers.gradleProperty("portalAbis").orElse("arm64-v8a,x86_64").get().split(",")
val targets = mapOf("arm64-v8a" to "aarch64-linux-android", "x86_64" to "x86_64-linux-android")
require(selectedAbis.isNotEmpty() && selectedAbis.all { it in targets }) { "portalAbis supports arm64-v8a,x86_64" }
val cargoTarget = layout.buildDirectory.dir("cargo").get().asFile
val source = file("upstream")
val buildPortal = tasks.register("buildPortal")
selectedAbis.forEach { abi ->
    val target = targets.getValue(abi)
    val compiler = File(bin, "$target${28}-clang${if (windows) ".cmd" else ""}")
    val output = layout.buildDirectory.file("jniLibs/$abi/libheart_portal.so")
    val build = tasks.register<Exec>("buildPortal_$abi") {
        inputs.files(fileTree("upstream/portal") { exclude("**/target/**") }, fileTree("upstream/scripts"), file("upstream/Cargo.toml"), file("upstream/Cargo.lock"), file("upstream/portal.example.toml"), fileTree("upstream/.cargo"))
        inputs.file(file("build.gradle.kts"))
        outputs.file(output)
        workingDir(source)
        environment("CARGO_TARGET_DIR", cargoTarget.absolutePath)
        environment("CARGO_TARGET_${target.uppercase().replace('-', '_')}_LINKER", compiler.absolutePath)
        environment("CC_${target.replace('-', '_')}", compiler.absolutePath)
        environment("AR_${target.replace('-', '_')}", File(bin, "llvm-ar${if (windows) ".exe" else ""}").absolutePath)
        // Android 15+ devices can use 16 KiB pages.
        environment("CARGO_TARGET_${target.uppercase().replace('-', '_')}_RUSTFLAGS", "-C link-arg=-Wl,-z,max-page-size=16384")
        commandLine("cargo${if (windows) ".exe" else ""}", "+1.90.0", "build", "--locked", "--release", "--target", target)
        doFirst {
            check(File(source, "Cargo.toml").isFile) { "Initialize Portal: git submodule update --init --recursive" }
            check(compiler.isFile) { "Install Android NDK $ndkVersion and Rust 1.90.0 target $target; see docs/ANDROID-PORTAL.md" }
        }
        doLast {
            val dest = output.get().asFile
            dest.parentFile.mkdirs()
            File(cargoTarget, "$target/release/heart-portal").copyTo(dest, overwrite = true)
        }
    }
    buildPortal.configure { dependsOn(build) }
}
