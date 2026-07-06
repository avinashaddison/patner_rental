allprojects {
    repositories {
        google()
        mavenCentral()
        // Mapbox SDK downloads. Auth uses the secret DOWNLOADS:READ token read
        // from ~/.gradle/gradle.properties (MAPBOX_DOWNLOADS_TOKEN) so it never
        // lives in the repo.
        maven {
            url = uri("https://api.mapbox.com/downloads/v2/releases/maven")
            authentication { create<BasicAuthentication>("basic") }
            credentials {
                username = "mapbox"
                password = (project.findProperty("MAPBOX_DOWNLOADS_TOKEN") as String?) ?: ""
            }
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// mapbox_maps_flutter 2.25's native SDK requires compiling against Android API
// 36, but Flutter pins plugin modules to compileSdk 35. Bump every Android
// module (app + plugins) to 36 (the 36 platform is installed). Reflection keeps
// this working across AGP versions without importing AGP types.
subprojects {
    val bumpCompileSdk = {
        val android = extensions.findByName("android")
        if (android != null) {
            runCatching {
                val setter = android.javaClass.methods.firstOrNull {
                    it.name == "setCompileSdk" && it.parameterCount == 1
                }
                if (setter != null) {
                    setter.invoke(android, 36)
                } else {
                    android.javaClass.methods.firstOrNull {
                        it.name == "compileSdkVersion" &&
                            it.parameterCount == 1 &&
                            it.parameterTypes[0] == Int::class.javaPrimitiveType
                    }?.invoke(android, 36)
                }
            }
        }
        Unit
    }
    // :app is already evaluated (evaluationDependsOn above) and is set to 36 in
    // its own build.gradle; plugin modules go through afterEvaluate.
    if (state.executed) bumpCompileSdk() else afterEvaluate { bumpCompileSdk() }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
